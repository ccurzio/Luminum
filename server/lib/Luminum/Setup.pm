#
# Luminum Server Setup Backend
# by Christopher R. Curzio (ccurzio@luminum.net)
#
# Installer backend for the Luminum Server. setup.pl (wizard, text, or
# non-interactive) collects parameters and hands them to Luminum::Setup::run.
#
# The installation is a self-contained tree (default /opt/Luminum/LuminumServer):
#
#   <root>/broker.pl            broker entry point (synced from source)
#   <root>/lib/                 Luminum Perl modules
#   <root>/sql/schema.sql       database schema (synced from source)
#   <root>/console/             web console (html + nginx reference files)
#   <root>/config/broker.conf   broker configuration (generated)
#   <root>/config/console.conf  console configuration (generated)
#   <root>/config/ssl/          server certificate, private key, public key
#   <root>/config/lumys_enabled/ enabled Lumy modules
#   <root>/console/nginx/luminum.conf    standalone nginx configuration
#   <root>/console/nginx/luminum-fpm.conf dedicated php-fpm configuration
#   <root>/bin/                 start/stop scripts (or systemd units)
#   <root>/run/                 pid files and sockets
#   <root>/log/                 broker and web logs
#
# Re-running the installer refreshes the synced code and regenerates the
# generated configuration; the database schema is applied idempotently and
# existing SYSTEM.CONFIG values are preserved unless overridden.

package Luminum::Setup;

use strict;
use warnings;
use File::Path qw(make_path);
use File::Copy qw(copy);
use File::Basename qw(dirname);
use FindBin qw($Bin);
use DBI;
use IO::Socket::INET;
use MIME::Base64;

our $VERSION = "0.0.1";

# ---------------------------------------------------------------------------
# Public entry point
# ---------------------------------------------------------------------------

# run(%opts)
#
# Required (unless an existing config is being reused):
#   shost     server hostname (certificate CN/SAN; must match the name the
#             clients connect to)
#   laddr     broker listener address
#   lport     broker listener port (default 10465)
# Optional:
#   install_root  default /opt/Luminum/LuminumServer
#   srcdir        source tree to sync from (default: the repo server/ dir
#                 that contains this module)
#   waddr/wport   web console address/port (default 0.0.0.0/443)
#   dbuser        database user (default luminum)
#   dbpass        database password (default: generated)
#   dbhost        database host (default: socket connection)
#   dbsocket      database socket path (default /var/run/mysqld/mysqld.sock)
#   dbadmin       admin user for schema setup (default root)
#   dbadminpass   admin password (default: empty)
#   adminuser     console admin username (default lumadmin)
#   adminpass     console admin password (default: generated)
#   adminemail    email for the admin account (set at creation)
#   perl5lib      PERL5LIB path to export in the broker start script
#   ssl           certificate handling (see prepare_ssl):
#                   { mode => 'generate'|'import',
#                     keymode => 'new'|'existing',
#                     cert => path, key => path, keypass => passphrase }
#                   Default: generate a new self-signed certificate/key.
#   start         start services after install (default 1; 0 to skip)
#   quiet         suppress progress output
#   progress      CODE ref called as progress($n, $total, $text) at the
#                 start of each install step (for progress UIs)
#   redact_log    print the completion summary to stdout with the console
#                 admin password replaced by "Console Admin Password has
#                 been set" / "has not been changed" - for callers whose
#                 stdout is captured into a persistent log file. The
#                 returned summary (for transient dialogs) keeps the real
#                 value either way.
#
# Returns (summary, rc): summary is the completion summary text (empty on
# failure), rc is 0 on success, nonzero on failure. In scalar context
# returns rc.
#
sub run {
	my (%o) = @_;

	my $root = $o{install_root} || "/opt/Luminum/LuminumServer";
	my $srcdir = $o{srcdir} || default_srcdir();
	my $log = $o{quiet} ? sub {} : sub { print "[setup] $_[0]\n"; };

	# progress($n, $total, $text) at the start of each install step.
	my $totalsteps = 11;
	my $stepn = 0;
	my $step = sub {
		$stepn++;
		$o{progress}->($stepn, $totalsteps, $_[0]) if ref($o{progress}) eq "CODE";
		};

	my $fail = sub {
		print "[setup] ERROR: $_[0]\n";
		return 1;
		};

	# --- Validate parameters ------------------------------------------------
	my $shost = $o{shost};
	my $laddr = $o{laddr};
	my $lport = $o{lport} || 10465;
	my $waddr = $o{waddr} || "0.0.0.0";
	my $wport = $o{wport} || 443;
	my $dbuser = $o{dbuser} || "luminum";
	my $dbpass = $o{dbpass} || randomtoken(24);
	my $dbhost = $o{dbhost};
	my $dbsocket = $o{dbsocket} || "/var/run/mysqld/mysqld.sock";
	my $dbadmin = $o{dbadmin} || "root";
	my $dbadminpass = defined $o{dbadminpass} ? $o{dbadminpass} : "";
	my $adminuser = $o{adminuser} || "lumadmin";
	my $adminpass = $o{adminpass};
	my $adminemail = $o{adminemail};
	my $perl5lib = $o{perl5lib};
	my $startsvc = exists $o{start} ? $o{start} : 1;
	# MQTT broker (mosquitto) listener: same address as the bootstrap listener,
	# fixed port 8883 (protocol 4.1). Kept in sync with the MPORT CONFIG row and
	# the generated mosquitto.conf.
	my $maddr = $laddr;
	my $mport = 8883;

	unless (defined $shost && $shost ne "") { return $fail->("shost is required"); }
	unless (defined $laddr && $laddr ne "") { return $fail->("laddr is required"); }
	unless ($lport =~ /^([1-9][0-9]{0,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])$/) {
		return $fail->("invalid lport: $lport");
		}
	unless ($wport =~ /^[0-9]+$/ && $wport > 0 && $wport < 65536) {
		return $fail->("invalid wport: $wport");
		}
	unless ($adminuser =~ /^[A-Za-z0-9]+$/) { return $fail->("invalid adminuser: $adminuser"); }
	unless (-d $srcdir) { return $fail->("source directory not found: $srcdir"); }
	unless (-e "$srcdir/broker.pl") { return $fail->("source tree incomplete (no broker.pl in $srcdir)"); }

	# --- Step 0: dependency check (before any files are written) -------------
	# The host must be able to run the result before anything is written.
	# Missing dependencies are reported, and - when the interface can ask
	# (deps_offer callback, interactive modes) - the user is offered
	# installing them now or cancelling. Either way, no file is written
	# before this point.
	$step->("Checking dependencies...");
	my @missing = find_missing_dependencies();
	if (@missing) {
		$log->("Missing dependencies: " . join(", ", @missing));
		my $resolved = 0;
		if (ref($o{deps_offer}) eq "CODE" && $> == 0) {
			if ($o{deps_offer}->(\@missing, $log)) {
				@missing = install_missing_dependencies(\@missing, $log);
				$resolved = !@missing;
				}
			}
		unless ($resolved) {
			return $fail->("missing dependencies: " . join(", ", @missing)
				. " - install them and re-run setup (no files were written)");
			}
		}
	# The database must be reachable (it is not installable through the
	# offer above).
	my $dbh = admin_connect($dbadmin, $dbadminpass, $dbhost, $dbsocket);
	unless ($dbh) {
		return $fail->("cannot connect to database as $dbadmin (socket: $dbsocket); if the admin account uses a password, supply it (dbadminpass / --dbadminpass)");
		}
	# A broker left running from a previous install (or a different install
	# root, or the systemd unit) holds the listener port this run rebinds;
	# stop it before any files are copied.
	stop_running_broker($root, $log);
	# A mosquitto left running from a previous install (or started
	# manually) holds the listener port and the password/ACL files this
	# run rewrites; stop it before any files are copied.
	stop_running_mosquitto($root, $log);
	# A nginx left running (this install's, the distro's, or another
	# install root's) holds the web port this run rebinds; stop it before
	# any files are copied.
	stop_running_nginx($root, $log);

	# --- Layout -------------------------------------------------------------
	my %dir = (
		root    => $root,
		config  => "$root/config",
		ssl     => "$root/config/ssl",
		lumys   => "$root/config/lumys_enabled",
		console => "$root/console",
		nginx   => "$root/console/nginx",
		bin     => "$root/bin",
		run     => "$root/run",
		logdir  => "$root/log",
		mosquitto => "$root/config/mosquitto",
		);
	for my $d (values %dir) {
		make_path($d, { mode => 0700, verbose => 0 }) unless -d $d;
		return $fail->("cannot create directory: $d") unless -d $d;
		}
	chmod(0755, $dir{console}, $dir{nginx}) if $> == 0;
	# The web user must traverse run/ (FPM socket) and config/
	# (console.conf) without being able to list them.
	chmod(0711, $dir{run}, $dir{config}) if $> == 0;
	# make_path creates every new directory 0700, which also locks the web
	# user out of the install root and any parent we created. The nginx and
	# php-fpm workers run as the web user and must reach the console files
	# and the FPM socket, so open up traversal on any directory in the
	# chain from / to the install root that lacks it. This also repairs
	# trees left 0700 by a previous install on re-runs.
	fix_traversal($root) if $> == 0;

	# --- Step 1: sync code from the source tree ------------------------------
	$step->("Synchronizing server files...");
	$log->("Synchronizing server files from $srcdir ...");
	for my $item (qw(broker.pl lib sql)) {
		my $s = "$srcdir/$item";
		my $d = "$root/$item";
		next unless -e $s;
		unlink($d) if -e $d && !-d $d;
		if (-d $s) {
			system("rm", "-rf", $d) == 0 or return $fail->("cannot clean $d");
			system("cp", "-a", $s, $d) == 0 or return $fail->("cannot copy $s to $d");
			}
		else {
			copy($s, $d) or return $fail->("cannot copy $s to $d: $!");
			}
		}
	if (-d "$srcdir/console") {
		# Refresh the console tree but keep generated nginx configs in place.
		for my $sub (qw(html)) {
			my $s = "$srcdir/console/$sub";
			my $d = "$root/console/$sub";
			next unless -d $s;
			system("rm", "-rf", $d) == 0 or return $fail->("cannot clean $d");
			system("cp", "-a", $s, $d) == 0 or return $fail->("cannot copy $s to $d");
			}
		}
	chmod(0755, "$root/console/html") if -d "$root/console/html";

	# --- Step 2: database ----------------------------------------------------
	# $dbh was already connected by the step 0 dependency check.
	$step->("Setting up database...");
	$log->("Setting up database ...");

	unless (apply_schema($dbh, "$root/sql/schema.sql", $log)) {
		return $fail->("database schema application failed");
		}
	unless (migrate_users($dbh, $log)) {
		return $fail->("AUTH.USERS migration failed");
		}
	unless (migrate_clients_auth($dbh, $log)) {
		return $fail->("CLIENTS.AUTH migration failed");
		}
	unless (migrate_commands($dbh, $log)) {
		return $fail->("CLIENTS.COMMANDS migration failed");
		}
	unless (setup_dbuser($dbh, $dbuser, $dbpass)) {
		return $fail->("database user setup failed");
		}
	my $adminnote;
	unless (seed_admin_user($dbh, $adminuser, \$adminpass, \$adminnote, $adminemail)) {
		return $fail->("console admin user setup failed");
		}
	unless (seed_default_cset($dbh, $adminuser, $log)) {
		return $fail->("default content set setup failed");
		}

	# --- Step 3: server certificate ------------------------------------------
	my $sslspec = $o{ssl} || {};
	my $sslwhat = $sslspec->{mode} eq "import"
		? "Importing server certificate"
		: ($sslspec->{keymode} eq "existing"
			? "Generating server certificate from existing key"
			: "Generating server certificate");
	$step->("$sslwhat...");
	$log->("$sslwhat for $shost ...");
	my ($slok, $cert, $key, $pub, $signseed, $signpub, $sslerr) =
		prepare_ssl($shost, $dir{ssl}, $sslspec, $log);
	unless ($slok) {
		return $fail->("certificate setup failed: $sslerr");
		}

	# --- Step 3b: MQTT broker (mosquitto) -------------------------------------
	# Mosquitto is the MQTT 3.1.1 broker the clients and the forked worker use
	# (protocol 4). It presents a leaf certificate signed by the server
	# certificate (CA:TRUE, the client's TLS trust anchor); rustls/webpki on the
	# client refuses a CA:TRUE cert as the presented leaf, so mosquitto presents
	# a real leaf that chains to the anchor. The broker maintains the
	# password_file and ACL file at runtime and reloads mosquitto (SIGHUP) after
	# changes; here we provision the TLS, mosquitto.conf, and a bootstrap
	# (empty) password_file + comment-only ACL so mosquitto can start before the
	# broker regenerates the full ACL.
	$step->("Provisioning MQTT broker...");
	$log->("Provisioning MQTT broker (mosquitto) ...");
	my ($mqttslok, $mcrt, $mkey, $mqtttlserr) =
		prepare_mqtt_tls($shost, $dir{ssl}, $cert, $key, $log);
	unless ($mqttslok) {
		return $fail->("MQTT broker TLS setup failed: $mqtttlserr");
		}
	my $mosqconf = "$dir{mosquitto}/mosquitto.conf";
	my $mosqpasswd = "$dir{mosquitto}/passwd";
	my $mosqacl = "$dir{mosquitto}/acl";
	# The pid file and log live in the system-standard locations on root
	# installs: the system mosquitto runs as the unprivileged 'mosquitto'
	# user and cannot write into the 0700 root-owned install tree. These
	# are the distro's own locations (verified against the Debian package:
	# /etc/mosquitto/mosquitto.conf uses "log_dest file
	# /var/log/mosquitto/mosquitto.log" and its unit provisions
	# /run/mosquitto; /var/run is a symlink to /run). A non-root install
	# runs the broker as the invoking user, which can write the install
	# tree, so it keeps the in-tree locations (the system dirs cannot be
	# provisioned without root).
	my $sysmosq = ($> == 0);
	my $mosqrundir = $sysmosq ? "/var/run/mosquitto" : "$dir{mosquitto}";
	my $mosqlogdir = $sysmosq ? "/var/log/mosquitto" : "$dir{logdir}";
	my $mosqpid = "$mosqrundir/mosquitto.pid";
	my $mosqlog = "$mosqlogdir/mosquitto.log";
	unless (writefile($mosqconf,
		"# Mosquitto MQTT broker (generated by setup; protocol 4)\n"
		. "listener $mport $maddr\n"
		. "cafile $cert\n"
		. "certfile $mcrt\n"
		. "keyfile $mkey\n"
		. "password_file $mosqpasswd\n"
		. "acl_file $mosqacl\n"
		. "pid_file $mosqpid\n"
		. "allow_anonymous false\n"
		. "max_packet_size 65536\n"
		. "log_dest file $mosqlog\n"
		. "log_type error\n"
		. "log_type warning\n"
		. "log_type notice\n", 0600)) {
		return $fail->("cannot write $mosqconf");
		}
	# Bootstrap password_file (empty) and ACL (comment-only): mosquitto starts
	# cleanly with these; the broker's startmqtt() adds the server user and
	# regenerates the full ACL, then reloads mosquitto.
	open(my $pfh, ">", $mosqpasswd) or return $fail->("cannot write $mosqpasswd");
	close($pfh);
	chmod(0600, $mosqpasswd);
	unless (writefile($mosqacl, "# initial ACL - the broker regenerates this on startup\n", 0600)) {
		return $fail->("cannot write $mosqacl");
		}
	# On hosts where the mosquitto package runs the broker as the
	# unprivileged 'mosquitto' user (the process does not keep the
	# invoking user's privileges), it cannot reach the 0700 root-owned
	# install tree: hand it the config dir and the password/ACL files
	# it reads, and give it the system-standard pid/log dirs it writes
	# to (the distro's unit does the same in ExecStartPre). /var/run is
	# tmpfs, so the generated start script re-creates them after a
	# reboot. No-op when no such user exists (source builds, broker
	# running as root).
	if ($> == 0) {
		my @mpw = getpwnam("mosquitto");
		if (@mpw) {
			chown($mpw[2], $mpw[3], $dir{mosquitto}, $mosqconf, $mosqpasswd, $mosqacl);
			# The generated config sets no 'user' directive, and mosquitto
			# defaults to user=mosquitto when started as root - so after the
			# privilege drop it must still read the TLS files it loads, and on
			# every SIGHUP reload it re-reads mosquitto.conf as that user. Hand
			# it the CA/cert and the MQTT key, and let it traverse config/ssl
			# to reach them. The server private key and the Ed25519 signing
			# key stay root-only (0600, not chowned).
			chown($mpw[2], $mpw[3], $cert, $mcrt, $mkey);
			chmod(0711, $dir{ssl});
			for my $d ($mosqrundir, $mosqlogdir) {
				mkdir($d, 0740) unless -d $d;
				chown($mpw[2], $mpw[3], $d);
				chmod(0740, $d);
				}
			}
		}

	# --- Step 4: server identity ---------------------------------------------
	# 256-bit random server ID (32 bytes, 64 lowercase hex chars).
	$step->("Generating server identity...");
	my $sid = randomhex(32);
	my $skey = randomtoken(24);

	# --- Step 5: configuration files ------------------------------------------
	$step->("Writing configuration files...");
	$log->("Writing configuration files ...");
	my $brokerconf = "$dir{config}/broker.conf";
	my $dbhostline = (defined $dbhost && $dbhost ne "") ? "DBHOST = $dbhost\n" : "";
	writefile($brokerconf, "# Luminum Broker Configuration (generated by setup)\n"
		. "LOGDIR = $dir{logdir}\n"
		. "DBUSER = $dbuser\n"
		. "DBPASS = $dbpass\n"
		. "DBSOCKET = $dbsocket\n"
		. $dbhostline, 0600) or return $fail->("cannot write $brokerconf");
	my $consoleconf = "$dir{config}/console.conf";
	writefile($consoleconf, <<EOF, 0600) or return $fail->("cannot write $consoleconf");
# Luminum Console Configuration (generated by setup)
instdir = $root
hostname = $shost
dbuser = $dbuser
dbpass = $dbpass
EOF

	# --- Step 6: SYSTEM.CONFIG rows --------------------------------------------
	$step->("Seeding database configuration...");
	$log->("Seeding SYSTEM.CONFIG ...");
	my %rows = (
		SID         => $sid,
		SKEY        => $skey,
		SHOST       => $shost,
		LADDR       => $laddr,
		LPORT       => "$lport",
		MADDR       => $laddr,
		MPORT       => "$mport",
		SSLCERT     => $cert,
		SSLPRVKEY   => $key,
		SSLPUBKEY   => $pub,
		# Server Ed25519 signing keypair (protocol 7.1): the broker signs
		# envelopes with this key; its public key is the one carried in
		# the server-signing.crt distributed to clients.
		SRVPRV      => encode_base64($signseed, ""),
		SRVPUB      => encode_base64($signpub, ""),
		INSTALLDATE => scalar(localtime),
		# Where mosquitto writes its pid file (system-standard on root
		# installs, in-tree otherwise) - the broker's SIGHUP reloads
		# target this path, so it must track the generated mosquitto.conf.
		MQTTPIDFILE => $mosqpid,
		);
	# The admin email is optional; only seed it when supplied so an
	# existing value (e.g. changed later in the console) is preserved.
	$rows{OWNEREMAIL} = $adminemail if defined $adminemail && $adminemail ne "";
	# Default-only rows: seeded on first install (ENDPOINTCOMM = mqtt,
	# MISSINGAFTER = 90 days, CMDTIMEOUT = 120s, DEPLTIMEOUT = 3600s,
	# CHECKININT = 5 min, TCONFTHRESHOLD = 250 endpoints, 2FA = Optional,
	# MINPASS = 8, COMPLEXPASS = Disabled, UTIMEOUT = 15M, UTIMEOUTWARN =
	# Enabled, SENREVS = 5, PKGREVS = 5, INVESTIGATE = Enabled), but a
	# value later changed in the console survives re-runs. SENREVS and
	# PKGREVS are revision counts; any value > 0 is "Enabled" in the
	# console, 0 is "Disabled".
	my %defaults = (
		ENDPOINTCOMM    => "mqtt",
		MISSINGAFTER    => "90",
		CMDTIMEOUT      => "120",
		DEPLTIMEOUT     => "3600",
		CHECKININT      => "5",
		TCONFTHRESHOLD  => "250",
		"2FA"           => "Optional",
		MINPASS         => "8",
		COMPLEXPASS     => "Disabled",
		UTIMEOUT        => "15M",
		UTIMEOUTWARN    => "Enabled",
		SENREVS         => "5",
		PKGREVS         => "5",
		INVESTIGATE     => "Enabled",
		);
	unless (seed_config($dbh, \%rows, \%defaults)) {
		return $fail->("SYSTEM.CONFIG seeding failed");
		}
	# Verify every seeded row is present with a non-null value. The
	# columns are NOT NULL in the schema, but that does not guarantee the
	# row exists (e.g. hand-removed), and the console and broker read
	# these keys unconditionally.
	my @bad;
	my $ok = eval {
		my @missing;
		for my $ckey (sort(keys(%rows), keys(%defaults))) {
			my $sth = $dbh->prepare("select CVAL from SYSTEM.CONFIG where CKEY = ?");
			$sth->execute($ckey);
			my ($cval) = $sth->fetchrow_array();
			push @missing, $ckey unless defined $cval && $cval ne "";
			}
		@bad = @missing;
		1;
		};
	unless ($ok) {
		return $fail->("SYSTEM.CONFIG verification failed: " . ($@ || "unknown error"));
		}
	if (@bad) {
		return $fail->("SYSTEM.CONFIG rows missing or null after seeding: " . join(", ", @bad));
		}
	$dbh->disconnect();

	# --- Step 7: web console (nginx + php-fpm) ---------------------------------
	$step->("Writing web console configuration...");
	$log->("Writing web console configuration ...");
	my $nginxconf = "$dir{nginx}/luminum.conf";
	my $fpmconf = "$dir{nginx}/luminum-fpm.conf";
	my $fpmsock = "$dir{run}/php-fpm.sock";
	my $fpmbin = find_php_fpm();
	unless (write_web_conf($nginxconf, $fpmconf, {
		waddr => $waddr, wport => $wport, shost => $shost,
		root => $root, cert => $cert, key => $key,
		fpmsock => $fpmsock, fpmbin => $fpmbin,
		consoleconf => $consoleconf, dbsocket => $dbsocket, dbhost => $dbhost,
		})) {
		return $fail->("web console configuration failed");
		}

	# --- Step 8: service management ---------------------------------------------
	$step->("Installing service management...");
	$log->("Installing service management ...");
	unless (install_service({
		root => $root, bin => $dir{bin}, run => $dir{run}, logdir => $dir{logdir},
		nginxconf => $nginxconf, fpmconf => $fpmconf, fpmbin => $fpmbin,
		perl5lib => $perl5lib,
		mosqconf   => "$dir{mosquitto}/mosquitto.conf",
		mosqpid    => $mosqpid,
		mosqlog    => $mosqlog,
		mosqrundir => $mosqrundir,
		mosqlogdir => $mosqlogdir,
		sysmosq    => $sysmosq,
		})) {
		return $fail->("service installation failed");
		}

	# --- Step 9: start and verify ---------------------------------------------------
	$step->("Starting and verifying services...");
	my $rc = 0;
	if ($startsvc) {
		$log->("Starting services ...");
		start_now({ bin => $dir{bin}, run => $dir{run}, logdir => $dir{logdir},
			laddr => $laddr, lport => $lport, maddr => $maddr, mport => $mport,
			wport => $wport, mosqlog => $mosqlog }) == 0 or $rc = 1;
		if ($rc == 0) {
			$log->("Verifying installation ...");
			verify({ root => $root, laddr => $laddr, lport => $lport, wport => $wport,
				maddr => $maddr, mport => $mport,
				dbsocket => $dbsocket, dbhost => $dbhost, dbuser => $dbuser, dbpass => $dbpass })
				or $rc = 1;
			}
		}
	else {
		$log->("Skipping service start (start=0).");
		}

	if ($rc == 0) {
		my $adminpw = (defined $adminpass && $adminpass ne "")
			? $adminpass
			: ($adminnote || "existing account, password unchanged");
		my @summary = (
			"Luminum Server installed at $root",
			"- Database Admin User: $dbadmin",
			"- Web Console: https://$shost:$wport",
			"- Console Admin Username: $adminuser",
			"- Console Admin Password: $adminpw",
			);
		my $summary = join("\n", @summary) . "\n";
		my $printed = $summary;
		if ($o{redact_log}) {
			# The printed summary lands in a persistent log file; never
			# store the password in it. $adminnote is set only when an
			# existing account's password was left in place.
			my $pwline = defined $adminnote
				? "Console Admin Password has not been changed"
				: "Console Admin Password has been set";
			$printed =~ s/^- Console Admin Password: .*$/$pwline/m;
			}
		print $printed;
		return ($summary, $rc);
		}
	return ("", $rc);
	}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# The repo server/ directory containing this module (lib/Luminum/Setup.pm).
#
sub default_srcdir {
	my $self = abs_self();
	$self =~ s{/lib/Luminum/Setup\.pm$}{};
	return $self;
	}

sub abs_self {
	my ($pkg, $file) = caller;
	return $file if $file =~ m{^/};
	return "$Bin/$file";
	}

# Add "other-execute" to any directory from $path up to (not including) /
# that lacks it, so an unprivileged user can traverse the chain. Returns
# the directories changed.
#
sub fix_traversal {
	my ($path) = @_;
	my @changed;
	while (length($path) > 1) {
		my @st = stat($path);
		if (@st && !($st[2] & 0o001)) {
			chmod(($st[2] & 0o7777) | 0o001, $path);
			push @changed, $path;
			}
		last if $path eq "/";
		$path = dirname($path);
		}
	return @changed;
	}

# Random base36 token from /dev/urandom.
#
sub randomtoken {
	my $n = shift;
	my $bytes;
	if (open(my $ur, "<:raw", "/dev/urandom")) { read($ur, $bytes, $n * 2); close($ur); }
	else { $bytes = join("", map { chr(int(rand(256))) } 1 .. ($n * 2)); }
	my @alphabet = ('0'..'9', 'a'..'z');
	my $out = join("", map { $alphabet[ord($_) % 36] } unpack("C*", $bytes));
	return substr($out, 0, $n);
	}

# Random lowercase hex string: $nbytes random bytes from /dev/urandom,
# hex-encoded (2*$nbytes chars, n bytes of entropy).
#
sub randomhex {
	my $n = shift;
	my $bytes;
	if (open(my $ur, "<:raw", "/dev/urandom")) { read($ur, $bytes, $n); close($ur); }
	else { $bytes = join("", map { chr(int(rand(256))) } 1 .. $n); }
	return unpack("H*", $bytes);
	}

sub writefile {
	my ($path, $content, $mode) = @_;
	open(my $fh, ">", $path) or return 0;
	print $fh $content;
	close($fh);
	chmod($mode, $path) if defined $mode;
	return 1;
	}

# Detect the dependencies the install needs, run BEFORE any file is
# written: the external binaries the installer shells out to (including
# the php CLI used for bcrypt hashing - the php-fpm package does not
# pull it in) and the non-core Perl modules the broker and the forked
# MQTT worker load (checked in this process's @INC, which is what
# detect_perl5lib bakes into the generated start scripts). Returns the
# missing item names; empty when the host is ready.
#
sub find_missing_dependencies {
	my @missing;
	for my $bin (qw(mosquitto mosquitto_passwd nginx openssl php)) {
		my $p = `command -v $bin 2>/dev/null`;
		push @missing, $bin unless defined $p && $p ne "";
		}
	my $fpmbin = find_php_fpm();
	push @missing, "php-fpm" unless $fpmbin;
	# DBD::mysql is not caught by a compile check (DBI->connect loads it),
	# so it is listed explicitly.
	my %modfile = (
		"DBI"                    => "DBI.pm",
		"DBD::mysql"             => "DBD/mysql.pm",
		"IO::Socket::SSL"        => "IO/Socket/SSL.pm",
		"Crypt::Perl::Ed25519"   => "Crypt/Perl/Ed25519/PrivateKey.pm",
		"Net::MQTT::Simple"      => "Net/MQTT/Simple.pm",
		"Net::MQTT::Simple::SSL" => "Net/MQTT/Simple/SSL.pm",
		);
	for my $mod (sort keys %modfile) {
		my $ok = eval { require $modfile{$mod}; 1 };
		push @missing, $mod unless $ok;
		}
	return @missing;
	}

# System packages providing each dependency, per package-manager family.
# Net::MQTT::Simple is mapped for apt only: libnet-mqtt-simple-perl
# (verified in Debian trixie/main) provides both Net::MQTT::Simple and
# Net::MQTT::Simple::SSL. The dnf/apk equivalents are unverified, so
# they are reported as unmapped rather than guessed; Alpine's PHP
# packages are version-prefixed (php83-fpm, ...) and likewise unmapped.
#
my %DEPPKGS = (
	apt => {
		mosquitto         => "mosquitto",
		mosquitto_passwd  => "mosquitto-clients",
		nginx             => "nginx",
		openssl           => "openssl",
		php               => "php-cli",
		"php-fpm"         => "php-fpm",
		"DBI"             => "libdbi-perl",
		"DBD::mysql"      => "libdbd-mysql-perl",
		"IO::Socket::SSL" => "libio-socket-ssl-perl",
		"Crypt::Perl::Ed25519" => "libcrypt-perl-ed25519-perl",
		"Net::MQTT::Simple"    => "libnet-mqtt-simple-perl",
		},
	dnf => {
		mosquitto         => "mosquitto",
		mosquitto_passwd  => "mosquitto-clients",
		nginx             => "nginx",
		openssl           => "openssl",
		php               => "php-cli",
		"php-fpm"         => "php-fpm",
		"DBI"             => "perl-DBI",
		"DBD::mysql"      => "perl-DBD-MySQL",
		"IO::Socket::SSL" => "perl-IO-Socket-SSL",
		"Crypt::Perl::Ed25519" => "perl-Crypt-Perl-Ed25519",
		},
	apk => {
		mosquitto         => "mosquitto",
		mosquitto_passwd  => "mosquitto-clients",
		nginx             => "nginx",
		openssl           => "openssl",
		"DBI"             => "perl-DBI",
		"DBD::mysql"      => "perl-DBD-mysql",
		"IO::Socket::SSL" => "perl-IO-Socket-SSL",
		"Crypt::Perl::Ed25519" => "perl-Crypt-Perl-Ed25519",
		},
	);

my %DEPCMD = (
	apt => "apt-get",
	dnf => "dnf",
	yum => "yum",
	apk => "apk",
	);

# The package mapping table for a family (the table itself is lexical);
# exposed for the tests.
sub dep_packages {
	my ($fam) = @_;
	return $DEPPKGS{$fam} || {};
	}

# Detect the system package manager. Returns (family, full path);
# (undef, undef) when none of apt/dnf/yum/apk is available.
#
sub detect_package_manager {
	for my $fam (qw(apt dnf yum apk)) {
		my $p = `command -v $DEPCMD{$fam} 2>/dev/null`;
		chomp($p) if defined $p;
		return ($fam, $p) if defined $p && $p ne "";
		}
	return (undef, undef);
	}

# Install missing dependencies through the system package manager
# (requires root). Returns the items still missing afterwards: install
# failures and items with no package mapping.
#
sub install_missing_dependencies {
	my ($missing, $log) = @_;
	my ($fam, $pm) = detect_package_manager();
	if (!defined $fam) {
		$log->("  no supported package manager found (apt/dnf/yum/apk); install the missing dependencies manually and re-run setup");
		return @$missing;
		}
	if ($> != 0) {
		$log->("  installing packages requires root; re-run setup as root or install the missing dependencies manually");
		return @$missing;
		}
	my $table = $DEPPKGS{$fam} || {};
	my %pkgset;
	my @unmapped;
	for my $item (@$missing) {
		if (defined $table->{$item}) {
			$pkgset{$table->{$item}} = 1;
		} else {
			push @unmapped, $item;
		}
		}
	my @pkgs = sort keys %pkgset;
	if (@unmapped) {
		$log->("  no package mapping for: " . join(", ", @unmapped));
		my @cpan = grep { /::/ } @unmapped;
		$log->("  (Perl modules can be installed from CPAN: cpanm " . join(" ", @cpan) . ")") if @cpan;
		}
	unless (@pkgs) {
		return @$missing;
		}
	$log->("  installing via $fam: " . join(" ", @pkgs));
	my $rc;
	if ($fam eq "apt") {
		system($pm, "update");
		$rc = system($pm, "install", "-y", @pkgs);
		}
	elsif ($fam eq "apk") {
		$rc = system($pm, "add", @pkgs);
		}
	else {
		$rc = system($pm, "install", "-y", @pkgs);
		}
	if ($rc != 0) {
		$log->("  package installation failed (exit " . int($rc / 256) . "); install the missing dependencies manually and re-run setup");
		return find_missing_dependencies();
		}
	my @still = find_missing_dependencies();
	if (@still) {
		$log->("  still missing after installation: " . join(", ", @still));
		}
	return @still;
	}

# Stop a Luminum broker that is still running before the install copies or
# rewrites any files. Three layers, mirroring stop_running_mosquitto: the
# generated systemd unit (Restart=on-failure would bring a killed broker
# straight back), the installed stop script (pid file, with a command-line
# fallback for a broker started without one), then any surviving process
# matched by command line - e.g. a broker left over from a different
# install root, which this install's stop script does not touch but which
# still holds the listener port.
#
sub stop_running_broker {
	my ($root, $log) = @_;
	if (systemd_available()) {
		for my $u (glob("/etc/systemd/system/*-broker.service")) {
			(my $name = $u) =~ s{.*/}{};
			$log->("Stopping $name ...");
			system("/usr/bin/systemctl", "stop", $name);
			}
		}
	if (-x "$root/bin/stop-broker") {
		$log->("Stopping existing Luminum broker ...");
		system("$root/bin/stop-broker");
		}
	my @pids = broker_pids();
	if (@pids) {
		$log->("Stopping broker process(es) " . join(", ", @pids) . " ...");
		kill("TERM", @pids);
		my $t = 0;
		while ($t < 5) {
			@pids = broker_pids();
			last unless @pids;
			sleep(1);
			$t++;
			}
		if (@pids) {
			$log->("  broker " . join(", ", @pids) . " did not exit; starting the new broker may fail to bind the listener port");
			}
		}
	}

# PIDs of running Luminum broker processes, matched by command line
# ("perl <path>/broker.pl") rather than pid file: a broker left over from
# another install root is invisible to this install's stop script (its
# pid file and command-line fallback both cover only this install's
# broker.pl) yet still holds the listener port. The broker's forked MQTT
# worker shares the command line and is included.
#
sub broker_pids {
	my @pids = `pgrep -f 'broker\.pl' 2>/dev/null`;
	chomp(@pids);
	@pids = grep { /^\d+$/ } @pids;
	return @pids unless -d "/proc";
	my @verified;
	for my $pid (@pids) {
		my $raw;
		{
			open(my $fh, "<", "/proc/$pid/cmdline") or next;
			local $/;
			$raw = <$fh>;
			}
		next unless defined $raw;                        # zombie: empty cmdline
		my @c = grep { length } split(/\0/, $raw);
		next unless @c == 2;
		my ($interp, $script) = @c;
		$interp =~ s{.*/}{};
		$script =~ s{.*/}{};
		push @verified, $pid if $interp =~ /^perl/ && $script eq "broker.pl";
		}
	return @verified;
	}

# Command line of a running process (from /proc), space-joined; "" when
# unavailable (no /proc, or the process already exited).
#
sub proc_cmdline {
	my ($pid) = @_;
	return "" unless -r "/proc/$pid/cmdline";
	open(my $fh, "<", "/proc/$pid/cmdline") or return "";
	my $raw;
	{
		local $/;
		$raw = <$fh>;
		}
	my @c = grep { length } split(/\0/, $raw);
	return @c ? join(" ", @c) : "";
	}

# PID of the process listening on TCP $port (any local address), or ""
# when none is found or /proc is unavailable. /proc/net/tcp{,6} lists
# LISTEN sockets with their inode; /proc/<pid>/fd maps the inode back to
# a PID.
#
sub port_holder {
	my ($port) = @_;
	return "" unless -d "/proc";
	my $hex = sprintf("%04X", $port);
	my %inodes;
	for my $f ("/proc/net/tcp", "/proc/net/tcp6") {
		open(my $fh, "<", $f) or next;
		while (my $line = <$fh>) {
			# The line is blank-padded, so split yields a leading empty
			# field: $c[1] is the slot, $c[2] local_address, $c[4] st,
			# $c[10] inode.
			my @c = split(/\s+/, $line);
			next unless @c >= 11;
			next unless $c[1] =~ /^\d+:$/;                # skips the header
			next unless $c[4] eq "0A";                    # TCP_LISTEN
			my ($addr, $lport) = split(/:/, $c[2]);
			next unless defined $lport && $lport eq $hex;
			$inodes{$c[10]} = 1 if $c[10] > 0;
			}
		close($fh);
		}
	return "" unless keys %inodes;
	for my $d (glob("/proc/[0-9]*")) {
		my ($pid) = $d =~ m{^/proc/(\d+)$};
		for my $fd (glob("$d/fd/*")) {
			my $t = readlink($fd);
			return $pid if defined $t && $t =~ /^socket:\[(\d+)\]$/ && $inodes{$1};
			}
		}
	return "";
	}

# Stop a mosquitto that is still running before the install copies or
# rewrites any files. The installed stop script (pid file) is tried
# first; any surviving mosquitto process - e.g. one started manually with
# a different pid file or in the foreground - is then terminated
# directly.
#
sub stop_running_mosquitto {
	my ($root, $log) = @_;
	if (-x "$root/bin/stop-mosquitto") {
		$log->("Stopping existing MQTT broker (mosquitto) ...");
		system("$root/bin/stop-mosquitto");
		}
	my @pids = `pgrep -x mosquitto 2>/dev/null`;
	chomp(@pids);
	@pids = grep { /^\d+$/ } @pids;
	if (@pids) {
		$log->("Stopping mosquitto process(es) " . join(", ", @pids) . " ...");
		kill("TERM", @pids);
		my $t = 0;
		while ($t < 5) {
			@pids = `pgrep -x mosquitto 2>/dev/null`;
			chomp(@pids);
			@pids = grep { /^\d+$/ } @pids;
			last unless @pids;
			sleep(1);
			$t++;
			}
		if (@pids) {
			$log->("  mosquitto " . join(", ", @pids) . " did not exit; starting the new broker may fail to bind the MQTT port");
			}
		}
	}

# Stop an nginx that is still running before the install copies or
# rewrites any files. Three layers, mirroring stop_running_broker: the
# distro's nginx systemd unit (a directly killed unit would be brought
# straight back), the installed stop-web script (our config's pid file,
# with a command-line fallback), then any surviving process matched by
# command line - e.g. a nginx that came up while the install was running.
#
sub stop_running_nginx {
	my ($root, $log) = @_;
	if (systemd_available()
			&& system("/usr/bin/systemctl", "is-active", "--quiet", "nginx") == 0) {
		$log->("Stopping nginx service ...");
		system("/usr/bin/systemctl", "stop", "nginx");
		}
	if (-x "$root/bin/stop-web") {
		$log->("Stopping existing Luminum web console ...");
		system("$root/bin/stop-web");
		}
	my @pids = nginx_pids();
	if (@pids) {
		$log->("Stopping nginx process(es) " . join(", ", @pids) . " ...");
		kill("QUIT", @pids);
		my $t = 0;
		while ($t < 5) {
			@pids = nginx_pids();
			last unless @pids;
			sleep(1);
			$t++;
			}
		if (@pids) {
			$log->("  nginx " . join(", ", @pids) . " did not exit; the web console may fail to bind its port");
			kill("TERM", @pids);
			}
		}
	}

# PIDs of running nginx processes, matched by command line rather than
# pid file: a nginx started from a different config (another install
# root, or the distro's) is invisible to this install's stop-web yet
# still holds the web port. nginx keeps the comm "nginx" and rewrites
# its process title to "nginx: master process ..." / "nginx: worker
# process ...", so pgrep -x nginx plus a command-line check reaches
# master and workers alike; a process whose command line does not look
# like nginx is never matched.
#
sub nginx_pids {
	my @pids = `pgrep -x nginx 2>/dev/null`;
	chomp(@pids);
	@pids = grep { /^\d+$/ } @pids;
	return @pids unless -d "/proc";
	my @verified;
	for my $pid (@pids) {
		my $raw;
		{
			open(my $fh, "<", "/proc/$pid/cmdline") or next;
			local $/;
			$raw = <$fh>;
			}
		next unless defined $raw && length $raw;
		my $cmd = $raw;
		$cmd =~ s/\0/ /g;
		push @verified, $pid
			if $cmd =~ /^nginx(:| |$)/ || $cmd =~ m{^.*?/nginx( |$)};
		}
	return @verified;
	}

# Connect to the database as the administrator (schema setup only).
#
sub admin_connect {
	my ($user, $pass, $host, $socket) = @_;
	my %attr = (PrintError => 0, RaiseError => 1);
	$attr{mysql_socket} = $socket if $socket && -e $socket;
	$attr{mysql_host} = $host if $host;
	my $dbh = eval { DBI->connect("DBI:mysql:", $user, $pass, \%attr) };
	return $dbh unless $@;
	warn "[setup] database connect failed: $@";
	return undef;
	}

# Apply schema.sql (idempotent DDL).
#
sub apply_schema {
	my ($dbh, $schemafile, $log) = @_;
	open(my $fh, "<", $schemafile) or do { $log->("  cannot read $schemafile: $!"); return 0; };
	my $sql = do { local $/; <$fh> };
	close($fh);
	# Split into statements; strip full-line comments.
	my @stmts = split /;\s*(?:\n|$)/, $sql;
	for my $stmt (@stmts) {
		$stmt =~ s/^[ \t]*--[^\n]*\n//gm;
		$stmt =~ s/\s+/ /g;
		next if $stmt =~ /^\s*$/;
		# The installer must never drop data: schema.sql is maintained in
		# idempotent form (CREATE ... IF NOT EXISTS). A raw mysqldump
		# contains DROP TABLE statements; refuse it instead of wiping the
		# databases.
		if ($stmt =~ /\bDROP\s+(?:TABLE|DATABASE)\b/i) {
			$log->("  schema contains a DROP statement; schema.sql must stay idempotent (no DROP TABLE/DATABASE): " . substr($stmt, 0, 80));
			return 0;
			}
		my $rc = eval { $dbh->do($stmt); 1 };
		unless ($rc) {
			# "database/table already exists" style errors are acceptable
			# only for statements we know are idempotent; report the rest.
			my $err = $@ || "";
			unless ($err =~ /already exists|Duplicate/) {
				$log->("  schema statement failed: $err");
				return 0;
				}
			}
		}
	$log->("  schema applied.");
	return 1;
	}

# Upgrade CLIENTS.AUTH to the protocol v1 layout: add any column the
# current schema defines that the table lacks. The MQTTSECRET column
# (SHA-256 hash of the client's MQTT secret, protocol 3.1) was added
# after the first production installs; a NOT NULL DEFAULT is used here
# because strict mode refuses a bare NOT NULL addition on a table that
# already has rows. Pre-existing rows carry an empty hash, which the
# MQTT login check (when it lands) must treat as "secret not issued".
#
sub migrate_clients_auth {
	my ($dbh, $log) = @_;
	my %defs = (
		MQTTSECRET => "MQTTSECRET char(64) NOT NULL DEFAULT ''",
		);
	my %have = map { $_->[0] => 1 }
		@{ $dbh->selectall_arrayref(qq{select COLUMN_NAME from information_schema.COLUMNS where TABLE_SCHEMA = 'CLIENTS' and TABLE_NAME = 'AUTH'}) || [] };
	for my $col (sort keys %defs) {
		next if $have{$col};
		my $rc = eval { $dbh->do("alter table CLIENTS.AUTH add " . $defs{$col}); 1 };
		unless ($rc) { $log->("  CLIENTS.AUTH migration failed for $col: $@"); return 0; }
		$log->("  CLIENTS.AUTH: added missing column $col");
		}
	return 1;
	}

# COMMANDS.SID stores the Luminum Server ID (the SYSTEM.CONFIG SID value,
# which is also used to build the MQTT topic tree) - an alphanumeric
# string. The original schema declared it int, under which strict mode
# refused every real insert; change the column on existing installs.
#
sub migrate_commands {
	my ($dbh, $log) = @_;
	my ($type) = map { $_->[0] }
		@{ $dbh->selectall_arrayref(qq{select COLUMN_TYPE from information_schema.COLUMNS where TABLE_SCHEMA = 'CLIENTS' and TABLE_NAME = 'COMMANDS' and COLUMN_NAME = 'SID'}) || [] };
	return 1 unless defined $type; # table absent: nothing to migrate
	return 1 unless $type =~ /^int/; # already the string type
	my $rc = eval { $dbh->do("alter table CLIENTS.COMMANDS modify SID tinytext NOT NULL"); 1 };
	unless ($rc) { $log->("  CLIENTS.COMMANDS migration failed for SID: $@"); return 0; }
	$log->("  CLIENTS.COMMANDS: changed SID from int to tinytext");
	return 1;
	}

# Upgrade AUTH.USERS from the pre-1.0 layout: add any column the current
# schema defines that the table lacks. CREATE TABLE IF NOT EXISTS in
# schema.sql cannot extend an existing table, so older installations keep
# the narrower layout unless migrated here.
#
sub migrate_users {
	my ($dbh, $log) = @_;
	my %defs = (
		EMAIL      => "EMAIL tinytext DEFAULT NULL",
		PHONE      => "PHONE tinytext NOT NULL DEFAULT ''",
		TYPE       => "TYPE tinytext NOT NULL DEFAULT 'local'",
		REGDATE    => "REGDATE datetime NOT NULL DEFAULT '1970-01-01 00:00:00'",
		CHANGEPASS => "CHANGEPASS tinyint(1) NOT NULL DEFAULT 0",
		);
	my %have = map { $_->[0] => 1 }
		@{ $dbh->selectall_arrayref(qq{select COLUMN_NAME from information_schema.COLUMNS where TABLE_SCHEMA = 'AUTH' and TABLE_NAME = 'USERS'}) || [] };
	for my $col (sort keys %defs) {
		next if $have{$col};
		my $rc = eval { $dbh->do("alter table AUTH.USERS add " . $defs{$col}); 1 };
		unless ($rc) { $log->("  AUTH.USERS migration failed for $col: $@"); return 0; }
		$log->("  AUTH.USERS: added missing column $col");
		}
	return 1;
	}

# Create (or update) the application database user and grant it access to
# the Luminum databases.
#
sub setup_dbuser {
	my ($dbh, $user, $pass) = @_;
	my $host = "localhost";
	my $qpass = $pass;
	$qpass =~ s/'/'\\''/g;
	$qpass = "'$qpass'";
	my $ref = "'$user'\@'$host'";
	my $rc = eval {
		$dbh->do("CREATE USER IF NOT EXISTS $ref IDENTIFIED BY $qpass");
		$dbh->do("ALTER USER $ref IDENTIFIED BY $qpass");
		foreach my $db (qw(AUTH CLIENTS CONTENT DISCOVERY INTEGRITY INVENTORY LOGS POLICY QUERY SUMMARY SYSTEM)) {
			$dbh->do("GRANT ALL PRIVILEGES ON $db.* TO $ref");
			}
		$dbh->do("FLUSH PRIVILEGES");
		1;
		};
	return $rc ? 1 : 0;
	}

# Ensure the console administrator account exists. If $passref points to an
# empty value, one is generated (unless the account already exists, in which
# case the existing password is left in place and a note is recorded).
#
sub seed_admin_user {
	my ($dbh, $username, $passref, $noteref, $email) = @_;
	my $exists = eval {
		my $sth = $dbh->prepare("select ID from AUTH.USERS where USERNAME = ?");
		$sth->execute($username);
		my @row = $sth->fetchrow_array();
		scalar(@row) > 0;
		};
	if ($@) { warn "[setup] AUTH.USERS lookup failed: $@"; return 0; }

	if ($exists && (!defined $$passref || $$passref eq "")) {
		$$noteref = "existing account preserved (password unchanged)";
		return 1;
		}
	$$passref = randomtoken(16) unless defined $$passref && $$passref ne "";

	my $hash = bcrypt_hash($$passref);
	unless ($hash) { warn "[setup] unable to generate bcrypt hash (php CLI required)"; return 0; }

	my $rc = eval {
		# The current schema's AUTH.USERS has NOT NULL columns without
		# defaults (PHONE, TYPE, REGDATE); older installations may still
		# have the narrower table. Introspect the table so both layouts
		# work.
		my %have = map { $_->[0] => 1 }
			@{ $dbh->selectall_arrayref(qq{select COLUMN_NAME from information_schema.COLUMNS where TABLE_SCHEMA = 'AUTH' and TABLE_NAME = 'USERS'}) || [] };
		if ($exists) {
			my $set = "PASSWORD = ?, ROLE = 1, ENABLED = 1";
			my @vals = ($hash);
			# Backfill REGDATE on accounts created before it was tracked;
			# never overwrite a value that is already set.
			$set .= ", REGDATE = COALESCE(NULLIF(REGDATE, '0000-00-00 00:00:00'), NOW())" if $have{REGDATE};
			if ($have{EMAIL} && defined $email && $email ne "") {
				$set .= ", EMAIL = ?";
				push(@vals, $email);
				}
			my $sth = $dbh->prepare("update AUTH.USERS set $set where USERNAME = ?");
			$sth->execute(@vals, $username) or die "AUTH.USERS update failed: " . ($sth->errstr || "unknown error");
			}
		else {
			my @cols = ("USERNAME", "FULLNAME", "PASSWORD");
			my @vals = ($username, "Administrator", $hash);
			if ($have{EMAIL} && defined $email && $email ne "") { push(@cols, "EMAIL"); push(@vals, $email); }
			if ($have{PHONE}) { push(@cols, "PHONE"); push(@vals, ""); }
			if ($have{TYPE})  { push(@cols, "TYPE");  push(@vals, "local"); }
			push(@cols, "ROLE");
			push(@vals, 1);
			if ($have{REGDATE}) {
				my @t = localtime();
				push(@cols, "REGDATE");
				push(@vals, sprintf("%04d-%02d-%02d %02d:%02d:%02d", $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1], $t[0]));
				}
			push(@cols, "ENABLED");
			push(@vals, 1);
			my $sth = $dbh->prepare("insert into AUTH.USERS (" . join(",", @cols) . ") values (" . join(",", map { "?" } 1 .. scalar(@cols)) . ")");
			$sth->execute(@vals) or die "AUTH.USERS insert failed: " . ($sth->errstr || "unknown error");
			}
		1;
		};
	return $rc ? 1 : 0;
	}

# Ensure the "Luminum Default" content set exists in CONTENT.SETS: the
# console assigns new sensors/packages (and orphaned content) to a
# default set, so an install must start with one. Owned by the console
# administrator. REQUIRED = 1: the set is needed by the system and
# cannot be deleted. LOCKED = 0: it must stay selectable in the server
# options' "Default Content Set" dropdowns (which list only unlocked
# sets) and editable by the administrator.
# Idempotent: an existing set with the same name is left untouched.
#
sub seed_default_cset {
	my ($dbh, $adminuser, $log) = @_;
	my $rc = eval {
		my $sth = $dbh->prepare("select ID from AUTH.USERS where USERNAME = ?");
		$sth->execute($adminuser);
		my ($owner) = $sth->fetchrow_array();
		die "AUTH.USERS lookup failed for $adminuser" unless defined $owner;
		$sth = $dbh->prepare("select ID from CONTENT.SETS where NAME = ?");
		$sth->execute("Luminum Default");
		if ($sth->fetchrow_array()) {
			$log->("  content set 'Luminum Default' already exists; leaving it in place");
			return 1;
			}
		$sth = $dbh->prepare("insert into CONTENT.SETS (NAME, DESCRIPTION, REQUIRED, LOCKED, OWNER, CREATED) values (?, ?, 1, 0, ?, now())");
		$sth->execute("Luminum Default", "Default content set created by the Luminum installer", $owner)
			or die "CONTENT.SETS insert failed: " . ($sth->errstr || "unknown error");
		$log->("  created content set 'Luminum Default'");
		1;
		};
	unless ($rc) { warn "[setup] default content set seed failed: $@"; return 0; }
	return 1;
	}

# bcrypt hash via the PHP CLI (cost 13, matching the console login check).
#
sub bcrypt_hash {
	my ($pass) = @_;
	my $cmd = "php -r 'echo password_hash(\$argv[1], PASSWORD_BCRYPT, [\"cost\"=>13]);'";
	my $hash = `$cmd $pass 2>/dev/null`;
	chomp($hash);
	return ($hash =~ /^\$2y\$13\$.{53}$/) ? $hash : undef;
	}

# Write $pass to a 0600 temp file for use with "openssl -passin file:...".
# Returns the path, or undef on failure. The caller must unlink it.
#
sub passtofile {
	my ($pass) = @_;
	my $f = "/tmp/luminum-setup-pass.$$";
	open(my $fh, ">", $f) or return undef;
	print $fh $pass;
	close($fh);
	chmod(0600, $f);
	return $f;
	}

# Check a private key file. Returns (status, message):
#   ok        key loads without a passphrase
#   encrypted key loads with $pass
#   needpass  key is encrypted and no passphrase was supplied
#   badpass   a passphrase was supplied but the key does not load
#   error     file is not a usable private key (message explains)
#
sub key_check {
	my ($file, $pass) = @_;
	my $pem = "";
	if (open(my $fh, "<", $file)) { $pem = do { local $/; <$fh> }; close($fh); }
	unless ($pem =~ /-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----/) {
		return ("error", "no private key found in $file");
		}
	my $encrypted = ($pem =~ /ENCRYPTED/) ? 1 : 0;
	# An encrypted key with no passphrase would make openssl prompt on the
	# terminal; answer from the PEM marker instead.
	return ("needpass", "") if $encrypted && !(defined $pass && $pass ne "");
	my $pf = (defined $pass && $pass ne "") ? passtofile($pass) : undef;
	my $passarg = $pf ? "-passin file:$pf" : "";
	my $out = `openssl pkey -in "$file" $passarg -noout 2>&1`;
	my $rc = ($? >> 8);
	unlink($pf) if $pf;
	if ($rc == 0) {
		return ($encrypted ? "encrypted" : "ok", "");
		}
	if ($encrypted || $out =~ /bad decrypt|passphrase|encrypted|STORE routine/i) {
		return ((defined $pass && $pass ne "") ? "badpass" : "needpass", "");
		}
	$out =~ s/\s+/ /g;
	return ("error", "cannot read private key $file: $out");
	}

# Public key (PEM) of a private key file, or "" if it cannot be read.
#
sub key_pubkey {
	my ($file, $pass) = @_;
	my $pf = (defined $pass && $pass ne "") ? passtofile($pass) : undef;
	my $passarg = $pf ? "-passin file:$pf" : "";
	# Note: no -noout here; with "pkey -pubout" it suppresses the key itself.
	my $out = `openssl pkey -in "$file" $passarg -pubout 2>/dev/null`;
	unlink($pf) if $pf;
	return ($? == 0) ? $out : "";
	}

# Place the private key at $dst. Encrypted keys are decrypted: the broker
# (IO::Socket::SSL) and nginx cannot supply a key passphrase at runtime, so
# the installed key must be unencrypted (0600).
#
sub install_key {
	my ($src, $dst, $pass) = @_;
	my $rc;
	if (defined $pass && $pass ne "") {
		my $pf = passtofile($pass) or return 0;
		$rc = system("openssl pkey -in \"$src\" -passin file:$pf -out \"$dst\" 2>/dev/null");
		unlink($pf);
		}
	else {
		$rc = system("cp", "-f", $src, $dst);
		}
	return 0 unless $rc == 0;
	chmod(0600, $dst);
	return 1;
	}

# Public key (PEM) of a certificate written to $pub.
#
sub derive_pub {
	my ($cert, $pub) = @_;
	my $pk = `openssl x509 -in "$cert" -pubkey -noout 2>/dev/null`;
	return 0 if $? != 0 || $pk eq "";
	open(my $fh, ">", $pub) or return 0;
	print $fh $pk;
	close($fh);
	chmod(0644, $pub);
	return 1;
	}

# Does the certificate cover $shost (SAN or subject CN)? Used for a
# warning only - an operator may intentionally use a broader certificate.
#
sub cert_covers {
	my ($cert, $shost) = @_;
	my $txt = `openssl x509 -in "$cert" -noout -subject -ext subjectAltName 2>/dev/null`;
	return 1 if $txt =~ /DNS:\Q$shost\E\b/i;
	# OpenSSL renders IP SANs as "IP Address:..." in this output.
	return 1 if $txt =~ /IP(?: Address)?:\Q$shost\E\b/i;
	return 1 if $txt =~ /CN\s*=\s*\Q$shost\E\s*(?:$|,)/i;
	return 0;
	}

# Generate the Ed25519 signing keypair and signing certificate
# (protocol 7.1 bootstrap trust anchor): server-signing.key (0600) and
# server-signing.crt in $ssldir. The signing certificate is the client's
# out-of-band anchor for the server's envelope signatures. When $tls_issued
# is true it is issued by the server TLS certificate (the same trust root
# the client already uses for the handshake); otherwise - import mode,
# where the operator's CA is not available - it is self-signed and travels
# to the client as a standalone anchor.
#
# Returns (1, $seed, $pub, $signcert, $signkey) on success,
# (0, undef, undef, undef, undef, $err) on failure.
#
sub prepare_signing {
	my ($shost, $ssldir, $tls_cert, $tls_key, $tls_issued, $log) = @_;
	my $signkey  = "$ssldir/server-signing.key";
	my $signcert = "$ssldir/server-signing.crt";
	my $csr      = "$ssldir/server-signing.csr";
	my $ext      = "$ssldir/server-signing.ext";
	my $fail = sub { return (0, undef, undef, undef, undef, $_[0]) };

	my $priv = eval {
		require Crypt::Perl::Ed25519::PrivateKey;
		Crypt::Perl::Ed25519::PrivateKey->new();
		};
	return $fail->("Crypt::Perl::Ed25519 is not available (PERL5LIB missing the module)")
		unless $priv;
	my $seed = $priv->get_private();
	my $pub  = $priv->get_public_key()->get_public();

	# PKCS#8 for an Ed25519 seed is a fixed 48-byte structure:
	# AlgorithmIdentifier (id-Ed25519) + OCTET STRING wrapping the seed.
	my $der = pack("H*", "302e020100300506032b657004220420") . $seed;
	open(my $kf, ">", $signkey) or return $fail->("cannot write $signkey: $!");
	print $kf "-----BEGIN PRIVATE KEY-----\n";
	print $kf "$_\n" for encode_base64($der, "") =~ /(.{1,64})/g;
	print $kf "-----END PRIVATE KEY-----\n";
	close($kf);
	chmod(0600, $signkey);

	open(my $ef, ">", $ext) or return $fail->("cannot write $ext: $!");
	print $ef "basicConstraints=critical,CA:FALSE\n";
	print $ef "keyUsage=critical,digitalSignature\n";
	close($ef);

	my $rc;
	if ($tls_issued) {
		$rc = system("openssl", "req", "-new", "-key", $signkey,
			"-subj", "/CN=$shost", "-out", $csr) == 0
			&& system("openssl", "x509", "-req", "-in", $csr,
				"-CA", $tls_cert, "-CAkey", $tls_key,
				"-set_serial", "0x" . randomhex(16),
				"-days", "3650", "-extfile", $ext, "-out", $signcert) == 0;
	} else {
		$rc = system("openssl", "req", "-x509", "-key", $signkey, "-days", "3650",
			"-subj", "/CN=$shost", "-out", $signcert) == 0;
	}
	unlink($csr, $ext);
	return $fail->("signing certificate generation failed") unless $rc;
	chmod(0644, $signcert);
	$log->("  Ed25519 signing certificate: $signcert"
		. ($tls_issued ? " (issued by the server TLS certificate)" : " (self-signed)"));
	return (1, $seed, $pub, $signcert, $signkey);
	}

# Prepare the server certificate, private key, and public key in $ssldir
# (server.crt / server.key / server.pub), plus the Ed25519 signing keypair
# and signing certificate (server-signing.key / server-signing.crt,
# protocol 7.1).
#
# $spec:
#   mode    => 'generate' (default) | 'import'
#   keymode => 'new' (default) | 'existing'   (generate only)
#   cert    => existing certificate path      (import)
#   key     => existing private key path      (import, generate/existing)
#   keypass => passphrase for an encrypted key (optional)
#
# Returns (1, $cert, $key, $pub, $signseed, $signpub) on success,
# (0, undef, undef, undef, undef, undef, $err) on failure.
#
sub prepare_ssl {
	my ($shost, $ssldir, $spec, $log) = @_;
	$spec ||= {};
	$log ||= sub {};
	my $mode = $spec->{mode} || "generate";
	my $keymode = $spec->{keymode} || "new";
	my $cert = "$ssldir/server.crt";
	my $key  = "$ssldir/server.key";
	my $pub  = "$ssldir/server.pub";
	my $fail = sub { return (0, undef, undef, undef, undef, undef, $_[0]) };

	my $san = $shost =~ /^\d+\.\d+\.\d+\.\d+$/ ? "IP:$shost" : "DNS:$shost";

	if ($mode eq "import") {
		return $fail->("certificate path is required for import")
			unless defined $spec->{cert} && $spec->{cert} ne "";
		return $fail->("private key path is required for import")
			unless defined $spec->{key} && $spec->{key} ne "";
		return $fail->("certificate not found: $spec->{cert}") unless -e $spec->{cert};
		return $fail->("private key not found: $spec->{key}") unless -e $spec->{key};
		my $cchk = `openssl x509 -in "$spec->{cert}" -noout 2>&1`;
		return $fail->("invalid certificate: $cchk") if $? != 0;
		return $fail->("certificate is expired")
			unless system("openssl", "x509", "-in", $spec->{cert},
				"-noout", "-checkend", "0") == 0;
		my ($st, $msg) = key_check($spec->{key}, $spec->{keypass});
		return $fail->("key passphrase is required (encrypted key)") if $st eq "needpass";
		return $fail->("key passphrase is incorrect") if $st eq "badpass";
		return $fail->($msg) if $st eq "error";
		# The key must match the certificate.
		my $cpub = `openssl x509 -in "$spec->{cert}" -pubkey -noout 2>/dev/null`;
		my $kpub = key_pubkey($spec->{key}, $spec->{keypass});
		(my $c = $cpub) =~ s/\s+//g;
		(my $k = $kpub) =~ s/\s+//g;
		return $fail->("private key does not match the certificate")
			if $c eq "" || $k eq "" || $c ne $k;
		unless (cert_covers($spec->{cert}, $shost)) {
			$log->("  WARNING: certificate does not list $shost in its subject/SAN; clients verifying the hostname will reject it");
			}
		copy($spec->{cert}, $cert) or return $fail->("cannot copy certificate to $cert");
		chmod(0644, $cert);
		unless (install_key($spec->{key}, $key, $spec->{keypass})) {
			return $fail->("cannot install private key");
			}
		unless (derive_pub($cert, $pub)) { return $fail->("cannot derive public key"); }
		# Imported TLS certificates come from an external CA whose key is
		# not available, so the signing certificate is self-signed.
		my ($sok, $sseed, $spub, $scert, $skey, $serr) =
			prepare_signing($shost, $ssldir, $cert, $key, 0, $log);
		return $fail->("signing certificate setup failed: $serr") unless $sok;
		return (1, $cert, $key, $pub, $sseed, $spub);
		}

	unless ($mode eq "generate") { return $fail->("unknown ssl mode: $mode"); }

	if ($keymode eq "existing") {
		return $fail->("private key path is required")
			unless defined $spec->{key} && $spec->{key} ne "";
		return $fail->("private key not found: $spec->{key}") unless -e $spec->{key};
		my ($st, $msg) = key_check($spec->{key}, $spec->{keypass});
		return $fail->("key passphrase is required (encrypted key)") if $st eq "needpass";
		return $fail->("key passphrase is incorrect") if $st eq "badpass";
		return $fail->($msg) if $st eq "error";
		unless (install_key($spec->{key}, $key, $spec->{keypass})) {
			return $fail->("cannot install private key");
			}
		# CA:TRUE: the self-signed certificate also acts as the issuing
		# CA for the Ed25519 signing certificate (protocol 7.1).
		my $cmd = "openssl req -new -x509 -key \"$key\" -days 3650 "
			. "-out \"$cert\" -subj \"/CN=$shost\" -addext \"subjectAltName=$san\" "
			. "-addext \"basicConstraints=critical,CA:TRUE\" 2>/dev/null";
		return $fail->("certificate generation failed") unless system($cmd) == 0;
		chmod(0644, $cert);
		unless (derive_pub($cert, $pub)) { return $fail->("cannot derive public key"); }
		my ($sok, $sseed, $spub, $scert, $skey, $serr) =
			prepare_signing($shost, $ssldir, $cert, $key, 1, $log);
		return $fail->("signing certificate setup failed: $serr") unless $sok;
		return (1, $cert, $key, $pub, $sseed, $spub);
		}

	unless ($keymode eq "new") { return $fail->("unknown key mode: $keymode"); }

	# generate / new: fresh RSA key + self-signed certificate (CN + SAN =
	# $shost). CA:TRUE: the self-signed certificate also acts as the
	# issuing CA for the Ed25519 signing certificate (protocol 7.1).
	my $cmd = "openssl req -x509 -newkey rsa:2048 -nodes -days 3650 "
		. "-keyout \"$key\" -out \"$cert\" "
		. "-subj \"/CN=$shost\" -addext \"subjectAltName=$san\" "
		. "-addext \"basicConstraints=critical,CA:TRUE\" 2>/dev/null";
	return $fail->("certificate generation failed") unless system($cmd) == 0;
	unless (derive_pub($cert, $pub)) { return $fail->("cannot derive public key"); }
	chmod(0600, $key);
	chmod(0644, $cert);
	my ($sok, $sseed, $spub, $scert, $skey, $serr) =
		prepare_signing($shost, $ssldir, $cert, $key, 1, $log);
	return $fail->("signing certificate setup failed: $serr") unless $sok;
	return (1, $cert, $key, $pub, $sseed, $spub);
	}

# Issue the MQTT broker's TLS leaf (protocol 4). Mosquitto presents this leaf
# to clients; it is signed by the server certificate (CA:TRUE), which is the
# client's TLS trust anchor. Returns (1, $crt, $key) on success, (0, $err) on
# failure.
#
sub prepare_mqtt_tls {
	my ($shost, $ssldir, $cacert, $cakey, $log) = @_;
	$log ||= sub {};
	my $mcrt = "$ssldir/mosquitto.crt";
	my $mkey = "$ssldir/mosquitto.key";
	my $mcsr = "$ssldir/mosquitto.csr";
	my $mext = "$ssldir/mosquitto.ext";
	# The client's MQTT stack (rustls) verifies the hostname as a DNS name even
	# when it is an IP literal, so an IP host needs a DNS: entry as well as the
	# IP: entry (the latter covers IP-aware clients such as mosquitto_sub).
	my $san = $shost =~ /^\d+\.\d+\.\d+\.\d+$/ ? "DNS:$shost,IP:$shost" : "DNS:$shost";
	my $fail = sub { return (0, undef, undef, $_[0]) };
	unless (system("openssl", "genpkey", "-algorithm", "rsa",
		"-pkeyopt", "rsa_keygen_bits:2048", "-out", $mkey) == 0) {
		return $fail->("mosquitto key generation failed");
		}
	# The leaf's subject must differ from the CA's subject (the server
	# certificate's CN is $shost). If the leaf also used /CN=$shost, its
	# subject would equal its issuer, making it look self-signed and breaking
	# chain building in rustls/webpki (and OpenSSL) even though the signature
	# is valid. Hostname verification uses the SAN, not the CN, so a fixed
	# descriptive CN is safe.
	unless (system("openssl", "req", "-new", "-key", $mkey,
		"-subj", "/CN=Luminum MQTT Broker", "-out", $mcsr) == 0) {
		return $fail->("mosquitto CSR generation failed");
		}
	open(my $ef, ">", $mext) or return $fail->("cannot write $mext");
	print $ef "subjectAltName=$san\n"
		. "basicConstraints=critical,CA:FALSE\n"
		. "keyUsage=critical,digitalSignature,keyEncipherment\n"
		. "extendedKeyUsage=serverAuth\n";
	close($ef);
	unless (system("openssl", "x509", "-req", "-in", $mcsr,
		"-CA", $cacert, "-CAkey", $cakey, "-set_serial", "0x01",
		"-days", "3650", "-extfile", $mext, "-out", $mcrt) == 0) {
		return $fail->("mosquitto certificate signing failed");
		}
	unlink($mcsr, $mext);
	chmod(0600, $mkey);
	chmod(0644, $mcrt);
	return (1, $mcrt, $mkey);
	}

# Insert or update SYSTEM.CONFIG rows. Existing values are preserved unless
# the caller passes a value; here all values in $rows are authoritative
# (generated or user-supplied), except INSTALLDATE which is only set once.
# $defaults (optional) holds default-only rows: inserted when absent but
# never updated, so a value later changed in the console survives re-runs.
#
sub seed_config {
	my ($dbh, $rows, $defaults) = @_;
	$defaults = {} unless defined $defaults;
	my $rc = eval {
		for my $ckey (sort keys %$rows) {
			my $cval = $rows->{$ckey};
			my $sth = $dbh->prepare("select CVAL from SYSTEM.CONFIG where CKEY = ?");
			$sth->execute($ckey);
			my @row = $sth->fetchrow_array();
			if (@row > 0) {
				$dbh->do("update SYSTEM.CONFIG set CVAL = ? where CKEY = ?", undef, $cval, $ckey)
					unless $ckey eq "INSTALLDATE";
				}
			else {
				$dbh->do("insert into SYSTEM.CONFIG (CKEY, CVAL) values (?, ?)", undef, $ckey, $cval);
				}
			}
		for my $ckey (sort keys %$defaults) {
			my $sth = $dbh->prepare("select CVAL from SYSTEM.CONFIG where CKEY = ?");
			$sth->execute($ckey);
			# Row count, not value truth: a stored value of "0" (e.g.
			# PKGREVS disabled in the console) is false in scalar context
			# and would look like a missing row.
			my @existing = $sth->fetchrow_array();
			next if @existing;
			$dbh->do("insert into SYSTEM.CONFIG (CKEY, CVAL) values (?, ?)", undef, $ckey, $defaults->{$ckey});
			}
		1;
		};
	return $rc ? 1 : 0;
	}

# Determine the unprivileged user the web console should run as. The
# php-fpm pool user and the nginx worker user must match so the workers
# can reach the FPM socket. Returns (user, group, uid, gid).
#
sub detect_web_user {
	for my $name (qw(www-data apache nginx nobody)) {
		my @pw = getpwnam($name);
		next unless @pw;
		my @gr = getgrgid($pw[3]);
		return ($name, ($gr[0] || $name), $pw[2], $pw[3]);
		}
	die "[setup] no suitable web user found\n";
	}

# Locate a php-fpm binary.
#
sub find_php_fpm {
	for my $cand ("/usr/sbin/php-fpm8.4", "/usr/sbin/php-fpm8.3", "/usr/sbin/php-fpm8.2", "/usr/sbin/php-fpm") {
		return $cand if -x $cand;
		}
	my $found = `command -v php-fpm 2>/dev/null`;
	chomp($found);
	return $found ne "" ? $found : undef;
	}

# Standalone nginx + dedicated php-fpm configurations for the console.
#
sub write_web_conf {
	my ($nginxconf, $fpmconf, $p) = @_;
	my $fpmbin = $p->{fpmbin} || "/usr/sbin/php-fpm";
	my ($webuser, $webgroup, $webuid, $webgid) = detect_web_user();

	# The php-fpm workers (running as the web user) read the console
	# configuration at request time; it is 0600 and root-owned.
	chown($webuid, $webgid, $p->{consoleconf}) if $> == 0;

	# The generated nginx conf includes these from its own directory;
	# copy them from the system nginx install.
	for my $inc (qw(mime.types fastcgi_params)) {
		my $dst = "$p->{root}/console/nginx/$inc";
		if (-e "/etc/nginx/$inc") {
			system("cp", "-f", "/etc/nginx/$inc", $dst) == 0 or return 0;
			}
		elsif (!-e $dst) {
			return 0;
			}
		}
	# nginx temp paths under the install root (system dirs not writable).
	# Workers run as the web user, so they must own these.
	my $ntmp = "$p->{root}/run/nginx-tmp";
	for my $t (qw(client proxy fastcgi uwsgi scgi)) {
		make_path("$ntmp/$t", { mode => 0700, verbose => 0 }) unless -d "$ntmp/$t";
		}
	chown($webuid, $webgid, $ntmp, map { "$ntmp/$_" } qw(client proxy fastcgi uwsgi scgi)) if $> == 0;

	my $nginx = <<EOF;
# Luminum Web Console - standalone nginx configuration (generated by setup)
user $webuser;
pid $p->{root}/run/nginx.pid;
error_log $p->{root}/log/nginx-error.log;

events {
	worker_connections 768;
	}

http {
	include $p->{root}/console/nginx/mime.types;
	default_type application/octet-stream;
	access_log $p->{root}/log/nginx-access.log;
	client_body_temp_path $ntmp/client;
	fastcgi_temp_path $ntmp/fastcgi;
	proxy_temp_path $ntmp/proxy;
	uwsgi_temp_path $ntmp/uwsgi;
	scgi_temp_path $ntmp/scgi;
	sendfile on;
	tcp_nopush on;

	server {
		listen $p->{waddr}:$p->{wport} ssl;
		server_name $p->{shost};

		root $p->{root}/console/html;
		index index.php;

		ssl_certificate $p->{cert};
		ssl_certificate_key $p->{key};
		ssl_protocols TLSv1.2 TLSv1.3;

		location ~ \.php\$ {
			include fastcgi_params;
			fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
			fastcgi_pass unix:$p->{fpmsock};
			}

		location / {
			try_files \$uri \$uri/ =404;
			}
		}
	}
EOF
	unless (writefile($nginxconf, $nginx, 0644)) { return 0; }

	my $dbhost = $p->{dbhost} || "localhost";
	# NOTE: the php-fpm config parser rejects a comment as the very first
	# line of the file ("value is NULL for a ZEND_INI_PARSER_ENTRY"), so
	# this file must start with [global].
	# The user/group/listen.owner lines only apply (and are only possible)
	# when the installer runs as root; a non-root php-fpm cannot chown the
	# socket and fails to start with them present.
	my $fpmuser = ($> == 0)
		? "user = $webuser\n"
		  . "group = $webgroup\n"
		  . "listen.owner = $webuser\n"
		  . "listen.group = $webgroup\n"
		  . "listen.mode = 0660\n"
		: "";
	my $fpm = <<EOF;
[global]
pid = $p->{root}/run/php-fpm.pid
error_log = $p->{root}/log/php-fpm.log
daemonize = yes

[luminum]
$fpmuser
listen = $p->{fpmsock}
pm = dynamic
pm.max_children = 5
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
env[LUMINUM_CONSOLE_CONF] = $p->{consoleconf}
env[LUMINUM_DB_SOCKET] = $p->{dbsocket}
env[LUMINUM_DB_HOST] = $dbhost
EOF
	return writefile($fpmconf, $fpm, 0644);
	}

# Service management: systemd units when systemd is usable, otherwise
# start/stop scripts in <root>/bin.
#
sub install_service {
	my ($p) = @_;
	my $broker = "$p->{root}/broker.pl";
	my $perl5lib_line = $p->{perl5lib} ? "export PERL5LIB=\"$p->{perl5lib}\"\n" : "";

	my $start_broker = <<EOF;
#!/bin/sh
# Luminum broker start script (generated by setup)
$perl5lib_line
cd "$p->{root}" || exit 1
mkdir -p "$p->{run}"
# A second start would fail to bind the listener port and die, leaving a
# dead PID in the pid file over the running broker's.
if [ -f "$p->{run}/broker.pid" ] && kill -0 "\$(cat "$p->{run}/broker.pid")" 2>/dev/null; then
	echo "Luminum broker is already running (PID \$(cat "$p->{run}/broker.pid"))"
	exit 0
	fi
nohup perl "$broker" >> "$p->{logdir}/broker-stdout.log" 2>&1 &
echo \$! > "$p->{run}/broker.pid" || { echo "cannot write $p->{run}/broker.pid" >&2; exit 1; }
echo "Luminum broker started (PID \$(cat "$p->{run}/broker.pid"))"
EOF
	my $stop_broker = <<EOF;
#!/bin/sh
# Luminum broker stop script (generated by setup)
ROOT="$p->{root}"
PIDFILE="$p->{run}/broker.pid"
BROKER="\$ROOT/broker.pl"

# A broker under the generated systemd unit would be restarted by
# Restart=on-failure if killed directly; stop the unit first.
if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet luminum-broker 2>/dev/null; then
	systemctl stop luminum-broker
fi

stopped=0
if [ -f "\$PIDFILE" ]; then
	PID=\$(cat "\$PIDFILE")
	if kill "\$PID" 2>/dev/null; then
		echo "Luminum broker stopped (PID \$PID)"
		i=0
		while [ "\$i" -lt 5 ] && kill -0 "\$PID" 2>/dev/null; do
			sleep 1
			i=\$((i+1))
		done
		if [ "\$i" -ge 5 ]; then
			echo "  broker \$PID did not exit; sending KILL" >&2
			kill -9 "\$PID" 2>/dev/null
		fi
		stopped=1
	else
		echo "Luminum broker pid file was stale (PID \$PID not running)"
	fi
	rm -f "\$PIDFILE"
fi

# A broker with no pid file (started before the pid file existed, or the
# pid file was lost) is still found by command line: interpreter perl,
# exactly one argument, this install's broker.pl - absolute, or relative
# with the working directory at the install root. The forked MQTT worker
# shares the command line and is included.
if [ "\$stopped" -eq 0 ]; then
	found=""
	for pid in \$(pgrep -f 'broker\\.pl' 2>/dev/null); do
		[ -r "/proc/\$pid/cmdline" ] || continue
		args=\$(tr '\\0' '\\n' < "/proc/\$pid/cmdline" | sed '/^\$/d')
		n=\$(printf '%s\n' "\$args" | wc -l | tr -d ' ')
		[ "\$n" = "2" ] || continue
		interp=\$(printf '%s\n' "\$args" | sed -n 1p)
		script=\$(printf '%s\n' "\$args" | sed -n 2p)
		case "\${interp##*/}" in perl*) ;; *) continue ;; esac
		if [ "\$script" = "\$BROKER" ]; then
			found="\$found \$pid"
		elif [ "\$script" = "broker.pl" ]; then
			[ "\$(readlink "/proc/\$pid/cwd" 2>/dev/null)" = "\$ROOT" ] && found="\$found \$pid"
		fi
	done
	for pid in \$found; do
		kill "\$pid" 2>/dev/null && echo "Luminum broker stopped (PID \$pid, no pid file)"
	done
	# Wait for the exit so a following start can bind the listener port.
	for pid in \$found; do
		i=0
		while [ "\$i" -lt 5 ] && kill -0 "\$pid" 2>/dev/null; do
			sleep 1
			i=\$((i+1))
		done
	done
fi
EOF
	# php-fpm first (nginx needs the socket), then nginx.
	my $start_web = "#!/bin/sh\n"
		. "# Luminum web console start script (generated by setup)\n"
		. "$p->{fpmbin} -y \"$p->{fpmconf}\" || exit 1\n"
		. "nginx -c \"$p->{nginxconf}\" || exit 1\n"
		. "echo \"Luminum web console started\"\n";
	my $stop_web = <<EOF;
#!/bin/sh
# Luminum web console stop script (generated by setup)
# A distro nginx under systemd would be restarted if killed directly;
# stop the unit first.
if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet nginx 2>/dev/null; then
	systemctl stop nginx
fi
nginx -c "$p->{nginxconf}" -s quit 2>/dev/null
if [ -f "$p->{run}/php-fpm.pid" ]; then
	kill "\$(cat "$p->{run}/php-fpm.pid")" 2>/dev/null
	rm -f "$p->{run}/php-fpm.pid"
fi
# A nginx started from a different config (another install root, or the
# distro's) does not answer "-s quit" with our config's pid file; find
# it by command line. nginx keeps the comm "nginx" and rewrites its
# process title to "nginx: master process ..." / "nginx: worker process
# ...", so pgrep -x nginx plus the command-line check reaches master and
# workers alike.
found=""
for pid in \$(pgrep -x nginx 2>/dev/null); do
	[ -r "/proc/\$pid/cmdline" ] || continue
	cmd=\$(tr '\\0' ' ' < "/proc/\$pid/cmdline")
	case "\$cmd" in
	"nginx:"*|"nginx "*|*/nginx\\ *) ;;
	*) continue ;;
	esac
	found="\$found \$pid"
done
for pid in \$found; do
	kill -QUIT "\$pid" 2>/dev/null && echo "nginx stopped (PID \$pid)"
done
# Wait for the exit so a following start can bind the web port.
for pid in \$found; do
	i=0
	while [ "\$i" -lt 5 ] && kill -0 "\$pid" 2>/dev/null; do
		sleep 1
		i=\$((i+1))
	done
done
echo "Luminum web console stopped"
EOF

	# Mosquitto (the MQTT broker) is started before the broker: the broker's
	# forked worker connects to it. mosquitto -d daemonizes and writes its
	# pid_file; stop reads the pid_file. With system-standard pid/log dirs
	# (root installs, the broker runs as the unprivileged 'mosquitto'
	# user), /var/run is tmpfs, so re-create them on every start, owned by
	# that user when it exists.
	my $mosqprovision = $p->{sysmosq}
		? "mkdir -p \"$p->{mosqrundir}\" \"$p->{mosqlogdir}\"\n"
		  . "id mosquitto >/dev/null 2>&1 && chown mosquitto \"$p->{mosqrundir}\" \"$p->{mosqlogdir}\"\n"
		: "";
	my $start_mosq = "#!/bin/sh\n"
		. "# MQTT broker (mosquitto) start script (generated by setup)\n"
		. $mosqprovision
		. "if mosquitto -c \"$p->{mosqconf}\" -d; then\n"
		. "\techo \"MQTT broker (mosquitto) started\"\n"
		. "else\n"
		. "\techo \"MQTT broker (mosquitto) failed to start (see $p->{mosqlog})\" >&2\n"
		. "\texit 1\n"
		. "fi\n";
	my $stop_mosq = "#!/bin/sh\n"
		. "# MQTT broker (mosquitto) stop script (generated by setup)\n"
		. "if [ -f \"$p->{mosqpid}\" ]; then\n"
		. "\tPID=\$(cat \"$p->{mosqpid}\")\n"
		. "\tkill \"\$PID\" 2>/dev/null && echo \"MQTT broker (mosquitto) stopped (PID \$PID)\"\n"
		. "\trm -f \"$p->{mosqpid}\"\n"
		. "else\n"
		. "\techo \"MQTT broker (mosquitto) is not running (no pid file)\"\n"
		. "fi\n";
	for my $s ([$start_broker, "start-broker"], [$stop_broker, "stop-broker"],
			[$start_mosq, "start-mosquitto"], [$stop_mosq, "stop-mosquitto"],
			[$start_web, "start-web"], [$stop_web, "stop-web"]) {
		my $path = "$p->{bin}/$s->[1]";
		writefile($path, $s->[0], 0700) or return 0;
		}

	# Verify the broker actually compiles under the PERL5LIB we just wrote
	# into the start script. Without this, an incomplete PERL5LIB (e.g. the
	# setup process's @INC missing a module dir) would let the install
	# "succeed" and only fail at first broker start - after the old broker
	# has already been stopped.
	{
		my $env = $p->{perl5lib} ? "PERL5LIB=\"$p->{perl5lib}\" " : "";
		my $out = `$env perl -c "$broker" 2>&1`;
		if ($? != 0) {
			my $pl = (defined $p->{perl5lib} && $p->{perl5lib} ne "") ? $p->{perl5lib} : "(none)";
			warn "[setup] broker compile check FAILED with the generated start script's environment\n";
			warn "[setup]   PERL5LIB = $pl\n";
			warn "[setup]   $out";
			warn "[setup] The broker would not start. Make sure PERL5LIB includes the directories that provide IO::Socket::SSL, DBI and Crypt::Perl, then re-run setup.\n";
			return 0;
		}
	}

	# systemd units when available (used on production hosts).
	if (systemd_available()) {
		my $unit = "# Luminum broker service (generated by setup)\n"
			. "[Unit]\nDescription=Luminum Server Broker\nAfter=network.target\n\n"
			. "[Service]\nType=simple\n"
			. ($p->{perl5lib} ? "Environment=PERL5LIB=\"$p->{perl5lib}\"\n" : "")
			. "WorkingDirectory=$p->{root}\nExecStart=/usr/bin/perl $broker\nRestart=on-failure\n\n"
			. "[Install]\nWantedBy=multi-user.target\n";
		writefile("/etc/systemd/system/luminum-broker.service", $unit, 0644) or return 0;
		system("/usr/bin/systemctl", "daemon-reload") == 0 or return 0;
		# Mosquitto unit: the broker unit is given Wants=/After= so mosquitto is
		# up before the broker. The unit name is derived from the broker unit just
		# written, so it always matches the install's naming. mosquitto runs in the
		# foreground under systemd (no -d).
		my @bu = glob("/etc/systemd/system/*-broker.service");
		if (@bu) {
			my $broker_unit = $bu[0];
			(my $mosq_unit = $broker_unit) =~ s/-broker\.service$/-mosquitto.service/;
			(my $mosq_name = $mosq_unit) =~ s{.*/}{};
			# With system-standard pid/log dirs, ExecStartPre mirrors the
			# distro's mosquitto.service: the pid dir is on tmpfs and the
			# chown only applies when the unprivileged broker user exists
			# on this host.
			my $mosqexecpre = $p->{sysmosq}
				? do {
					my @mpw = getpwnam("mosquitto");
					"ExecStartPre=/bin/mkdir -m 740 -p $p->{mosqrundir}\n"
					  . (@mpw ? "ExecStartPre=/bin/chown mosquitto $p->{mosqrundir}\n" : "")
					  . "ExecStartPre=/bin/mkdir -m 740 -p $p->{mosqlogdir}\n"
					  . (@mpw ? "ExecStartPre=/bin/chown mosquitto $p->{mosqlogdir}\n" : "")
					}
				: "";
			my $munit = "# MQTT broker (mosquitto) service (generated by setup)\n"
				. "[Unit]\nDescription=MQTT Broker (mosquitto)\nAfter=network.target\n\n"
				. "[Service]\nType=simple\n"
				. $mosqexecpre
				. "ExecStart=/usr/bin/mosquitto -c $p->{mosqconf}\nRestart=on-failure\n\n"
				. "[Install]\nWantedBy=multi-user.target\n";
			writefile($mosq_unit, $munit, 0644) or return 0;
			my $btext = "";
			if (open(my $bfh, "<", $broker_unit)) { local $/; $btext = <$bfh>; close($bfh); }
			if ($btext && $btext !~ /Wants=.*-mosquitto\.service/) {
				$btext =~ s/(\[Unit\][^\n]*)/$1\nWants=$mosq_name\nAfter=$mosq_name/;
				writefile($broker_unit, $btext, 0644) or return 0;
			}
			system("/usr/bin/systemctl", "daemon-reload") == 0 or return 0;
		}
		}
	return 1;
	}

sub systemd_available {
	return 0 unless -x "/usr/bin/systemctl";
	my $state = `/usr/bin/systemctl is-system-running 2>/dev/null`;
	chomp($state);
	return ($state =~ /^(running|degraded)$/) ? 1 : 0;
	}

# Start broker + web console using the installed scripts/units.
#
sub start_now {
	my ($p) = @_;
	my $bin = $p->{bin};
	# Stop anything left over from a previous install so ports and sockets
	# are free (idempotent re-runs).
	system("$bin/stop-broker") if -x "$bin/stop-broker";
	system("$bin/stop-mosquitto") if -x "$bin/stop-mosquitto";
	system("$bin/stop-web") if -x "$bin/stop-web";
	sleep(1);
	# A holder surviving the stop above (a non-Luminum process, or a broker
	# that ignored TERM) still blocks the bind; name it instead of guessing.
	my $probe_addr = ($p->{laddr} && $p->{laddr} ne "0.0.0.0") ? $p->{laddr} : "127.0.0.1";
	if (my $s = IO::Socket::INET->new(PeerAddr => "$probe_addr:$p->{lport}", Timeout => 1)) {
		close($s);
		my $holder = port_holder($p->{lport});
		my $who = $holder ne ""
			? " - held by PID $holder" . (proc_cmdline($holder) ? " (" . proc_cmdline($holder) . ")" : "")
			: "";
		warn "[setup] port $p->{lport} is already in use$who - stop that process and re-run setup";
		return 1;
		}
	# Start the MQTT broker (mosquitto) first: the broker's forked worker connects
	# to it, and the broker reloads it (SIGHUP) on startup.
	system("$bin/start-mosquitto") == 0 or do { warn "[setup] MQTT broker (mosquitto) start failed"; return 1; };
	my $mprobe = ($p->{maddr} && $p->{maddr} ne "0.0.0.0") ? $p->{maddr} : "127.0.0.1";
	my $mosq_up = 0;
	for (1 .. 15) {
		if (my $s = IO::Socket::INET->new(PeerAddr => "$mprobe:$p->{mport}", Timeout => 1)) {
			close($s); $mosq_up = 1; last;
		}
		sleep(1);
	}
	unless ($mosq_up) {
		warn "[setup] MQTT broker (mosquitto) is not listening on $mprobe:$p->{mport}";
		my @mlines = `tail -n 15 -- "$p->{mosqlog}" 2>/dev/null`;
		print "[setup]   --- mosquitto.log (last 15 lines) ---\n";
		print "[setup]   $_" for @mlines;
		return 1;
	}
	system("$bin/start-broker") == 0 or do { warn "[setup] broker start failed"; return 1; };
	# Watch the broker for a few seconds: it must be alive when the window
	# closes (a bind failure can take a moment after start to kill it), and
	# we fail fast if it dies early.
	my $pidfile = "$p->{run}/broker.pid";
	my ($pid, $state) = ("", "pending");
	for (1 .. 5) {
		if (-f $pidfile) {
			open(my $fh, "<", $pidfile);
			$pid = <$fh>;
			close($fh);
			chomp($pid);
			$state = ($pid =~ /^\d+$/ && kill(0, $pid)) ? "up" : "dead";
			last if $state eq "dead";
			}
		sleep(1);
		}
	unless ($state eq "up") {
		warn "[setup] broker process " . ($pid || "unknown") . " died during startup";
		for my $log (["$p->{logdir}/broker-stdout.log", 15], ["$p->{logdir}/broker.log", 10]) {
			next unless -r $log->[0];
			my @lines = `tail -n $log->[1] -- "$log->[0]" 2>/dev/null`;
			print "[setup]   --- $log->[0] (last $log->[1] lines) ---\n";
			print "[setup]   $_" for @lines;
			}
		return 1;
		}
	# The web console binds $wport next. stop-web only signals the nginx
	# started from this install's config, so a port held by another service
	# (or an nginx from a different install root) survives it; name the
	# holder up front instead of letting nginx dump five bind failures.
	my $wholder = port_holder($p->{wport});
	if ($wholder ne "") {
		warn "[setup] port $p->{wport} is already in use - held by PID $wholder"
			. (proc_cmdline($wholder) ? " (" . proc_cmdline($wholder) . ")" : "")
			. " - stop that service and re-run setup";
		return 1;
		}
	system("$bin/start-web") == 0 or do { warn "[setup] web console start failed"; return 1; };
	return 0;
	}

# Post-start verification: ports listening, DB reachable, config present.
#
sub verify {
	my ($p) = @_;
	my $ok = 1;

	# Probe a TCP port, retrying while the service comes up. The broker
	# binds to the listener address (which may not be loopback), so probe
	# there; loopback is used when it listens on all interfaces.
	my $probe = sub {
		my ($addr, $port, $tries) = @_;
		for (1 .. $tries) {
			my $s = IO::Socket::INET->new(PeerAddr => "$addr:$port", Timeout => 2);
			if ($s) { close($s); return 1; }
			sleep(1);
		}
		return 0;
		};
	my $laddr = $p->{laddr};
	my $lprobe = ($laddr && $laddr ne "0.0.0.0") ? $laddr : "127.0.0.1";
	if ($probe->($lprobe, $p->{lport}, 15)) {
		print "[setup]   port $p->{lport}: listening\n";
		}
	else { print "[setup]   port $p->{lport}: NOT listening\n"; $ok = 0; }
	my $mprobe = ($p->{maddr} && $p->{maddr} ne "0.0.0.0") ? $p->{maddr} : "127.0.0.1";
	if ($probe->($mprobe, $p->{mport}, 10)) {
		print "[setup]   MQTT port $p->{mport}: listening\n";
		}
	else { print "[setup]   MQTT port $p->{mport}: NOT listening\n"; $ok = 0; }
	if ($probe->("127.0.0.1", $p->{wport}, 5)) {
		print "[setup]   port $p->{wport}: listening\n";
		}
	else { print "[setup]   port $p->{wport}: NOT listening\n"; $ok = 0; }

	my %attr = (PrintError => 0, RaiseError => 1);
	$attr{mysql_socket} = $p->{dbsocket} if $p->{dbsocket} && -e $p->{dbsocket};
	$attr{mysql_host} = $p->{dbhost} if $p->{dbhost};
	my $dbh = eval { DBI->connect("DBI:mysql:SYSTEM", $p->{dbuser}, $p->{dbpass}, \%attr) };
	if ($dbh) {
		my $sth = $dbh->prepare("select count(*) from CONFIG");
		$sth->execute();
		my ($n) = $sth->fetchrow_array();
		print "[setup]   database: connected, SYSTEM.CONFIG has $n rows\n";
		$sth->finish();
		$dbh->disconnect();
		}
	else { print "[setup]   database: CONNECT FAILED ($@)\n"; $ok = 0; }

	return $ok;
	}

1;
