#!/usr/bin/perl -w
#
# Luminum Server Configuration Backup/Restore
# by Christopher R. Curzio (ccurzio@luminum.net)
#
# Exports and imports the entire configuration of a running Luminum Server
# as a password-protected zip archive.
#
# export produces a zip containing:
#   config/       the install root's complete configuration tree
#                 (broker.conf, console.conf, ssl/, mosquitto/,
#                 lumys_enabled/)
#   database.sql  a mysqldump of all Luminum databases (which also carries
#                 SYSTEM.CONFIG, the database-stored configuration)
#   manifest.txt  creation metadata and a contents listing
#
# import stops the Luminum services (broker, mosquitto, web console),
# replaces the install root's config/ tree with the archived one, loads
# the database dump, and starts the services again - an in-place restore
# of the running server.
#
# The archive password is taken from --password, or entered
# interactively (no echo) when the flag is not given.
#
# Usage:
#   perl luminum-backup.pl export [--out FILE] [--password PASS]
#   perl luminum-backup.pl import ARCHIVE.zip [--password PASS]
#   perl luminum-backup.pl --help
#
# The install root is the directory containing this script (the installer
# syncs it to the root), so run the installed copy to back up or restore
# that install. export needs read access to the install's config/ and
# database credentials; import needs the privileges the stop/start
# scripts require (root on system installs).

use strict;
use Cwd qw(abs_path);
use File::Spec;
use File::Temp qw(tempdir);
use POSIX qw(strftime);
use DBI;

# Term::ReadKey is only needed for no-echo password entry.
eval { require Term::ReadKey; Term::ReadKey->import(); };
my $have_readkey = !$@;

# The fixed Luminum database names (must match sql/schema.sql and the
# installer's GRANT list).
my @DBS = qw(AUTH CLIENTS CONTENT DISCOVERY INTEGRITY INVENTORY LOGS POLICY QUERY SUMMARY SYSTEM);

# --- install root (same resolution as mkprovision.pl) ------------------------
my $mgrpath = abs_path($0);
my $mgrname = $mgrpath;
$mgrname =~ s{^(\/.*\/)}{};
my $root = $mgrpath;
$root =~ s{\/$mgrname}{};

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

sub usage {
	print <<'EOF';
Luminum Server Configuration Backup/Restore

Usage:
  perl luminum-backup.pl export [--out FILE] [--password PASS]
  perl luminum-backup.pl import ARCHIVE.zip [--password PASS]

Commands:
  export   Dump all Luminum databases and the install's complete config/
           tree into a password-protected zip archive.
  import   Stop the Luminum services, restore the config/ tree and the
           database from an archive, and start the services again.

Options:
  --out FILE       export: write the archive to FILE (default
                   luminum-backup-<hostname>-<timestamp>.zip in the
                   current directory; created mode 0600)
  --password PASS  archive password (export: encrypt with it, import:
                   decrypt with it); when omitted the password is
                   prompted for with no echo
  -h, --help       show this help

The install root is the directory containing this script, so run the
installed copy (e.g. /opt/Luminum/LuminumServer/luminum-backup.pl) to
back up or restore that install.
EOF
	}

sub die_err {
	my ($msg) = @_;
	die "FATAL: $msg\n";
	}

# Prompt for the archive password with no echo (Term::ReadKey), falling
# back to a plain read when it is unavailable or cannot take the tty.
#
sub ask_password {
	print "Enter the archive password: ";
	my $pass;
	if ($have_readkey) {
		if (eval { Term::ReadKey::ReadMode("noecho"); 1 }) {
			$pass = <STDIN>;
			eval { Term::ReadKey::ReadMode("restore") };
			}
		else {
			$pass = <STDIN>;
			}
		}
	else {
		$pass = <STDIN>;
		}
	print "\n" unless defined $pass && $pass =~ /\n$/;
	chomp($pass) if defined $pass;
	die_err("no archive password supplied") unless defined $pass && $pass ne "";
	return $pass;
	}

# Database credentials from an install's config/broker.conf (same format
# as the one the installer generates; parsed like mkprovision.pl does).
#
sub read_broker_conf {
	my ($path) = @_;
	open(my $bc, "<", $path)
		or die_err("cannot read broker configuration: $path ($!)");
	my ($dbuser, $dbpass, $dbhost, $dbsock);
	while (my $line = <$bc>) {
		next if $line =~ /^#/;
		if ($line =~ /^DBUSER[\s|\t]?+\=[\s|\t]?+(\S+)$/) { $dbuser = $1; }
		elsif ($line =~ /^DBPASS[\s|\t]?+\=[\s|\t]?+(.*)$/) { $dbpass = $1; chomp($dbpass); }
		elsif ($line =~ /^DBHOST[\s|\t]?+\=[\s|\t]?+(\S+)$/) { $dbhost = $1; }
		elsif ($line =~ /^DBSOCKET[\s|\t]?+\=[\s|\t]?+(\S+)$/) { $dbsock = $1; }
		}
	close($bc);
	die_err("broker configuration incomplete: $path") unless defined $dbuser && defined $dbpass;
	return ($dbuser, $dbpass, $dbhost, $dbsock);
	}

# Connect to a Luminum database with the install's credentials.
#
sub db_connect {
	my ($dbname, $dbuser, $dbpass, $dbhost, $dbsock) = @_;
	my %attr = (PrintError => 0, RaiseError => 1);
	$attr{mysql_socket} = $dbsock if defined $dbsock && $dbsock ne "" && -e $dbsock;
	$attr{mysql_host} = $dbhost if defined $dbhost && $dbhost ne "";
	my $dbh = eval { DBI->connect("DBI:mysql:$dbname", $dbuser, $dbpass, \%attr) };
	return $dbh;
	}

# All SYSTEM.CONFIG rows as a hash (the database-stored configuration).
#
sub config_rows {
	my ($dbuser, $dbpass, $dbhost, $dbsock) = @_;
	my $dbh = db_connect("SYSTEM", $dbuser, $dbpass, $dbhost, $dbsock)
		or die_err("cannot connect to the SYSTEM database ($@)");
	my %c;
	my $sth = $dbh->prepare("select CKEY, CVAL from CONFIG");
	$sth->execute();
	while (my ($k, $v) = $sth->fetchrow_array()) { $c{$k} = $v; }
	$dbh->disconnect();
	return %c;
	}

# The web console port from the generated nginx configuration
# ("listen <addr>:<port> ssl;").
#
sub nginx_wport {
	my ($path) = @_;
	return unless open(my $fh, "<", $path);
	while (<$fh>) { return $1 if /^\s*listen\s+\S+:(\d+)\s+ssl/; }
	close($fh);
	return;
	}

# The mosquitto log path from the generated mosquitto.conf
# ("log_dest file <path>").
#
sub mosq_log {
	my ($path) = @_;
	return unless open(my $fh, "<", $path);
	while (<$fh>) { return $1 if /^\s*log_dest\s+file\s+(\S+)/; }
	close($fh);
	return;
	}

# ---------------------------------------------------------------------------
# export
# ---------------------------------------------------------------------------

sub do_export {
	my ($out, $pass) = @_;
	unless (-d "$root/config") {
		die_err("$root does not look like a Luminum install root (no config/ directory)");
		}
	my ($dbuser, $dbpass, $dbhost, $dbsock) = read_broker_conf("$root/config/broker.conf");

	# Server hostname (for the default file name and the manifest) from
	# the generated console.conf.
	my $shost = "";
	if (open(my $cc, "<", "$root/config/console.conf")) {
		while (<$cc>) { $shost = $1 if /^hostname\s*=\s*(\S+)/; }
		close($cc);
		}
	my $hostpart = $shost;
	$hostpart =~ s/[^\w.\-]/_/g;
	my $stamp = strftime("%Y%m%d-%H%M%S", localtime);
	$out = "luminum-backup-" . ($hostpart || "server") . "-$stamp.zip" unless defined $out && $out ne "";
	# Resolve before the staging chdir below: a relative --out must mean
	# the caller's directory, not the staging directory.
	$out = File::Spec->rel2abs($out);
	die_err("$out already exists; refusing to overwrite") if -e $out;

	my $stage = tempdir("luminum-backup-XXXXXX", TMPDIR => 1, CLEANUP => 1)
		or die_err("cannot create a temporary staging directory");

	print "[backup] Dumping databases (" . join(", ", @DBS) . ") ...\n";
	my @dump = ("mysqldump", "--single-transaction", "--user=$dbuser",
		"--databases", @DBS);
	push @dump, "--socket=$dbsock" if defined $dbsock && $dbsock ne "";
	push @dump, "--host=$dbhost"   if defined $dbhost && $dbhost ne "";
	# The password goes through MYSQL_PWD, not --password, so it does not
	# appear in the mysqldump command line.
	$ENV{MYSQL_PWD} = $dbpass;
	my $rc = system(@dump, "--result-file=$stage/database.sql");
	delete $ENV{MYSQL_PWD};
	die_err("database dump failed (exit " . ($rc >> 8) . ")") unless $rc == 0;

	print "[backup] Copying configuration tree ...\n";
	system("cp", "-a", "$root/config", "$stage/config") == 0
		or die_err("cannot copy $root/config to the staging directory");

	open(my $mf, ">", "$stage/manifest.txt")
		or die_err("cannot write the manifest ($!)");
	print $mf "Luminum Server Configuration Backup\n";
	print $mf "Created: " . scalar(localtime) . "\n";
	print $mf "Source install root: $root\n";
	print $mf "Server hostname: " . ($shost || "unknown") . "\n";
	print $mf "Databases: " . join(", ", @DBS) . "\n";
	print $mf "\nContents:\n";
	print $mf "  config/       complete server configuration tree\n";
	print $mf "  database.sql  dump of the Luminum databases\n";
	print $mf "  manifest.txt  this file\n";
	close($mf);

	print "[backup] Creating password-protected archive $out ...\n";
	chdir($stage) or die_err("cannot enter the staging directory ($!)");
	my $zrc = system("zip", "-r", "-q", "-9", "-X", "-P", $pass, $out, ".");
	die_err("zip failed (exit " . ($zrc >> 8) . ")") unless $zrc == 0;
	chmod(0600, $out);
	print "[backup] Export complete: $out\n";
	return 0;
	}

# ---------------------------------------------------------------------------
# import
# ---------------------------------------------------------------------------

sub do_import {
	my ($file, $pass) = @_;
	die_err("archive not found: $file") unless -f $file;
	unless (-d "$root/config") {
		die_err("$root does not look like a Luminum install root (no config/ directory)");
		}

	my $stage = tempdir("luminum-backup-XXXXXX", TMPDIR => 1, CLEANUP => 1)
		or die_err("cannot create a temporary staging directory");

	print "[backup] Extracting $file ...\n";
	my $rc = system("unzip", "-o", "-q", "-P", $pass, $file, "-d", $stage);
	die_err("cannot open archive (wrong password, or not a valid zip): $file")
		unless $rc == 0;
	unless (-f "$stage/config/broker.conf" && -f "$stage/database.sql") {
		die_err("$file is not a Luminum Server backup archive (missing config/broker.conf or database.sql)");
		}

	# The stop/start helpers live in the install's own copy of the
	# backend (the same one the installer uses). @INC is extended at run
	# time (a "use lib" here would run at compile time, before $root is
	# known).
	push @INC, "$root/lib" unless grep { $_ eq "$root/lib" } @INC;
	eval { require Luminum::Setup; 1 }
		or die_err("cannot load Luminum::Setup from $root/lib ($@)");
	my $log = sub { print "[backup] $_[0]\n" };

	print "[backup] Stopping services ...\n";
	Luminum::Setup::stop_running_broker($root, $log);
	Luminum::Setup::stop_running_mosquitto($root, $log);
	Luminum::Setup::stop_running_nginx($root, $log);

	print "[backup] Restoring configuration files ...\n";
	system("rm", "-rf", "$root/config") == 0
		or die_err("cannot remove $root/config");
	system("cp", "-a", "$stage/config", "$root/config") == 0
		or die_err("cannot restore the configuration tree");

	print "[backup] Restoring database ...\n";
	my ($dbuser, $dbpass, $dbhost, $dbsock) = read_broker_conf("$root/config/broker.conf");
	my @sql = ("mysql", "--user=$dbuser");
	push @sql, "--socket=$dbsock" if defined $dbsock && $dbsock ne "";
	push @sql, "--host=$dbhost"   if defined $dbhost && $dbhost ne "";
	$ENV{MYSQL_PWD} = $dbpass;
	open(my $in, "<", "$stage/database.sql")
		or die_err("cannot read the database dump from the archive ($!)");
	my $pipe = open(my $outh, "|-", @sql);
	die_err("cannot start the mysql client ($!)") unless defined $pipe;
	while (my $line = <$in>) { print $outh $line; }
	close($in);
	my $ok = close($outh);
	delete $ENV{MYSQL_PWD};
	die_err("database restore failed") unless $ok;

	print "[backup] Starting services ...\n";
	my %cfg = config_rows($dbuser, $dbpass, $dbhost, $dbsock);
	my $laddr = $cfg{LADDR} || "127.0.0.1";
	my $lport = $cfg{LPORT} || 10465;
	my $maddr = $cfg{MADDR} || $laddr;
	my $mport = $cfg{MPORT} || 8883;
	my $wport = nginx_wport("$root/console/nginx/luminum.conf") || 443;
	my $mosqlog = mosq_log("$root/config/mosquitto/mosquitto.conf") || "$root/log/mosquitto.log";
	my $serr = Luminum::Setup::start_now({
		bin => "$root/bin", run => "$root/run", logdir => "$root/log",
		laddr => $laddr, lport => $lport, maddr => $maddr, mport => $mport,
		wport => $wport, mosqlog => $mosqlog,
		});
	if ($serr != 0) {
		die_err("service start failed - the configuration and database have been restored, but the services are stopped; see the output above and the install's log/ directory");
		}

	my $vok = Luminum::Setup::verify({
		root => $root, laddr => $laddr, lport => $lport, wport => $wport,
		maddr => $maddr, mport => $mport,
		dbsocket => $dbsock, dbhost => $dbhost, dbuser => $dbuser, dbpass => $dbpass,
		});
	if ($vok) {
		print "[backup] Import complete - the server is running with the restored configuration.\n";
		return 0;
		}
	print "[backup] Import finished, but verification reported problems - check the output above.\n";
	return 1;
	}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

my $cmd = shift @ARGV;
unless (defined $cmd && $cmd =~ /^(export|import)$/) {
	print STDERR "Error: a command is required (export|import)\n\n";
	usage();
	exit 1;
	}
my $out;
my $file;
my $pass;
while (@ARGV) {
	my $a = shift @ARGV;
	if ($a eq "--out") {
		$out = shift @ARGV;
		die "ERROR: --out requires a path\n" unless defined $out;
		}
	elsif ($a =~ /^--out=(.+)$/) { $out = $1; }
	elsif ($a eq "--password") {
		$pass = shift @ARGV;
		die "ERROR: --password requires a value\n" unless defined $pass;
		}
	elsif ($a =~ /^--password=(.+)$/) { $pass = $1; }
	elsif ($a eq "--help" || $a eq "-h") { usage(); exit 0; }
	elsif ($cmd eq "import" && !defined $file && $a !~ /^--/) { $file = $a; }
	else { die "Unknown option: $a (see --help)\n"; }
	}
if ($cmd eq "import") {
	die "ERROR: import requires the archive file\n" unless defined $file && $file ne "";
	}
$pass = ask_password() unless defined $pass;

exit($cmd eq "export" ? do_export($out, $pass) : do_import($file, $pass));
