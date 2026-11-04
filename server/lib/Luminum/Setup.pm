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
#   <root>/config/admin-credentials.txt  console admin credentials (0600)
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
#   start         start services after install (default 1; 0 to skip)
#   quiet         suppress progress output
#
# Returns 0 on success, nonzero on failure.
#
sub run {
	my (%o) = @_;

	my $root = $o{install_root} || "/opt/Luminum/LuminumServer";
	my $srcdir = $o{srcdir} || default_srcdir();
	my $log = $o{quiet} ? sub {} : sub { print "[setup] $_[0]\n"; };

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
	$log->("Setting up database ...");
	my $dbh = admin_connect($dbadmin, $dbadminpass, $dbhost, $dbsocket);
	unless ($dbh) { return $fail->("cannot connect to database as $dbadmin (socket: $dbsocket)"); }

	unless (apply_schema($dbh, "$root/sql/schema.sql", $log)) {
		return $fail->("database schema application failed");
		}
	unless (setup_dbuser($dbh, $dbuser, $dbpass)) {
		return $fail->("database user setup failed");
		}
	my $adminnote;
	unless (seed_admin_user($dbh, $adminuser, \$adminpass, \$adminnote, $adminemail)) {
		return $fail->("console admin user setup failed");
		}

	# --- Step 3: server certificate ------------------------------------------
	$log->("Generating server certificate for $shost ...");
	my ($cert, $key, $pub) = ("$dir{ssl}/server.crt", "$dir{ssl}/server.key", "$dir{ssl}/server.pub");
	unless (generate_ssl($shost, $cert, $key, $pub)) {
		return $fail->("certificate generation failed");
		}

	# --- Step 4: server identity ---------------------------------------------
	my $sid = randomtoken(16);
	my $skey = randomtoken(24);

	# --- Step 5: configuration files ------------------------------------------
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
dbuser = $dbuser
dbpass = $dbpass
EOF

	# --- Step 6: SYSTEM.CONFIG rows --------------------------------------------
	$log->("Seeding SYSTEM.CONFIG ...");
	my %rows = (
		SID         => $sid,
		SKEY        => $skey,
		SHOST       => $shost,
		LADDR       => $laddr,
		LPORT       => "$lport",
		MADDR       => $laddr,
		MPORT       => "8883",
		CMDTIMEOUT  => "120",
		DEPLTIMEOUT => "3600",
		CHECKININT  => "5",
		MISSINGAFTER => "90",
		INVESTIGATE => "Enabled",
		SSLCERT     => $cert,
		SSLPRVKEY   => $key,
		SSLPUBKEY   => $pub,
		INSTALLDATE => scalar(localtime),
		);
	unless (seed_config($dbh, \%rows)) {
		return $fail->("SYSTEM.CONFIG seeding failed");
		}
	$dbh->disconnect();

	# --- Step 7: web console (nginx + php-fpm) ---------------------------------
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
	$log->("Installing service management ...");
	unless (install_service({
		root => $root, bin => $dir{bin}, run => $dir{run}, logdir => $dir{logdir},
		nginxconf => $nginxconf, fpmconf => $fpmconf, fpmbin => $fpmbin,
		perl5lib => $perl5lib,
		})) {
		return $fail->("service installation failed");
		}

	# --- Step 9: credentials file -------------------------------------------------
	my $credfile = "$dir{config}/admin-credentials.txt";
	my $crednote = $adminnote || "password generated";
	writefile($credfile, <<EOF, 0600) or return $fail->("cannot write $credfile");
# Luminum Console Administrator Account (generated by setup)
#
username: $adminuser
password: $adminpass
note: $crednote
EOF

	# --- Step 10: start and verify ---------------------------------------------------
	my $rc = 0;
	if ($startsvc) {
		$log->("Starting services ...");
		start_now({ bin => $dir{bin}, run => $dir{run}, logdir => $dir{logdir},
			laddr => $laddr, lport => $lport }) == 0 or $rc = 1;
		if ($rc == 0) {
			$log->("Verifying installation ...");
			verify({ root => $root, laddr => $laddr, lport => $lport, wport => $wport,
				dbsocket => $dbsocket, dbhost => $dbhost, dbuser => $dbuser, dbpass => $dbpass })
				or $rc = 1;
			}
		}
	else {
		$log->("Skipping service start (start=0).");
		}

	if ($rc == 0) {
		print "[setup] Luminum Server installed at $root\n";
		print "[setup]   Broker listener:  $laddr:$lport\n";
		print "[setup]   Web console:      https://$shost:$wport\n";
		print "[setup]   Server ID:        $sid\n";
		print "[setup]   Server key:       $skey\n";
		print "[setup]   Console admin:    $adminuser (see $credfile)\n";
		print "[setup]   Start/stop:       $dir{bin}/start-broker, $dir{bin}/stop-broker, $dir{bin}/start-web, $dir{bin}/stop-web\n";
		}
	return $rc;
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

sub writefile {
	my ($path, $content, $mode) = @_;
	open(my $fh, ">", $path) or return 0;
	print $fh $content;
	close($fh);
	chmod($mode, $path) if defined $mode;
	return 1;
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
			# Backfill REGDATE on accounts created before it was tracked;
			# never overwrite a value that is already set.
			$set .= ", REGDATE = COALESCE(NULLIF(REGDATE, '0000-00-00 00:00:00'), NOW())" if $have{REGDATE};
			my $sth = $dbh->prepare("update AUTH.USERS set $set where USERNAME = ?");
			$sth->execute($hash, $username) or die "AUTH.USERS update failed: " . ($sth->errstr || "unknown error");
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

# bcrypt hash via the PHP CLI (cost 13, matching the console login check).
#
sub bcrypt_hash {
	my ($pass) = @_;
	my $cmd = "php -r 'echo password_hash(\$argv[1], PASSWORD_BCRYPT, [\"cost\"=>13]);'";
	my $hash = `$cmd $pass 2>/dev/null`;
	chomp($hash);
	return ($hash =~ /^\$2y\$13\$.{53}$/) ? $hash : undef;
	}

# Self-signed server certificate (CN + SAN = $shost).
#
sub generate_ssl {
	my ($shost, $cert, $key, $pub) = @_;
	my $san = $shost =~ /^\d+\.\d+\.\d+\.\d+$/ ? "IP:$shost" : "DNS:$shost";
	my $cmd = "openssl req -x509 -newkey rsa:2048 -nodes -days 3650 "
		. "-keyout \"$key\" -out \"$cert\" "
		. "-subj \"/CN=$shost\" -addext \"subjectAltName=$san\" 2>/dev/null";
	return 0 unless system($cmd) == 0;
	my $pubkey = `openssl x509 -in "$cert" -pubkey -noout 2>/dev/null`;
	return 0 if $? != 0 || $pubkey eq "";
	open(my $pfh, ">", $pub) or return 0;
	print $pfh $pubkey;
	close($pfh);
	chmod(0600, $key);
	chmod(0644, $cert, $pub);
	return 1;
	}

# Insert or update SYSTEM.CONFIG rows. Existing values are preserved unless
# the caller passes a value; here all values are authoritative (generated or
# user-supplied), except INSTALLDATE which is only set once.
#
sub seed_config {
	my ($dbh, $rows) = @_;
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
cd "$p->{root}"
nohup perl "$broker" >> "$p->{logdir}/broker-stdout.log" 2>&1 &
echo \$! > "$p->{run}/broker.pid"
echo "Luminum broker started (PID \$(cat "$p->{run}/broker.pid"))"
EOF
	my $stop_broker = "#!/bin/sh\n"
		. "# Luminum broker stop script (generated by setup)\n"
		. "if [ -f \"$p->{run}/broker.pid\" ]; then\n"
		. "\tPID=\$(cat \"$p->{run}/broker.pid\")\n"
		. "\tkill \"\$PID\" 2>/dev/null && echo \"Luminum broker stopped (PID \$PID)\"\n"
		. "\trm -f \"$p->{run}/broker.pid\"\n"
		. "else\n"
		. "\techo \"Luminum broker is not running (no pid file)\"\n"
		. "fi\n";
	# php-fpm first (nginx needs the socket), then nginx.
	my $start_web = "#!/bin/sh\n"
		. "# Luminum web console start script (generated by setup)\n"
		. "$p->{fpmbin} -y \"$p->{fpmconf}\" || exit 1\n"
		. "nginx -c \"$p->{nginxconf}\" || exit 1\n"
		. "echo \"Luminum web console started\"\n";
	my $stop_web = "#!/bin/sh\n"
		. "# Luminum web console stop script (generated by setup)\n"
		. "nginx -c \"$p->{nginxconf}\" -s quit 2>/dev/null\n"
		. "if [ -f \"$p->{run}/php-fpm.pid\" ]; then\n"
		. "\tkill \"\$(cat \"$p->{run}/php-fpm.pid\")\" 2>/dev/null\n"
		. "\trm -f \"$p->{run}/php-fpm.pid\"\n"
		. "fi\n"
		. "echo \"Luminum web console stopped\"\n";

	for my $s ([$start_broker, "start-broker"], [$stop_broker, "stop-broker"],
			[$start_web, "start-web"], [$stop_web, "stop-web"]) {
		my $path = "$p->{bin}/$s->[1]";
		writefile($path, $s->[0], 0700) or return 0;
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
	system("$bin/stop-web") if -x "$bin/stop-web";
	sleep(1);
	# A broker left over from a *different* install root was not stopped
	# above; fail with a clear message instead of a cryptic bind error.
	my $probe_addr = ($p->{laddr} && $p->{laddr} ne "0.0.0.0") ? $p->{laddr} : "127.0.0.1";
	if (my $s = IO::Socket::INET->new(PeerAddr => "$probe_addr:$p->{lport}", Timeout => 1)) {
		close($s);
		warn "[setup] port $p->{lport} is already in use - a broker from a previous install is probably still running; stop it (its bin/stop-broker) and re-run setup";
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
