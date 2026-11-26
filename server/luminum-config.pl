#!/usr/bin/perl -w
#
# Luminum Server Configuration Settings
# by Christopher R. Curzio (ccurzio@luminum.net)
#
# Sets, reads, and lists the tunable Luminum Server configuration settings
# stored in SYSTEM.CONFIG - the database-stored configuration that the web
# console's Server Options page manages. This is the command-line equivalent
# of that page: the same keys and the same valid values, applied directly to
# the database. Most settings are read live by the running server (an admin
# change takes effect on the next client check-in or sweep); the rest take
# effect on the next broker start.
#
# The install-time identity rows (SID, SKEY, SHOST, the certificate paths, the
# Ed25519 signing keypair, INSTALLDATE, ...) are deliberately NOT settable
# here: they define the server's identity, and changing them out from under a
# running install breaks client trust and registration. ENLUMYS is also
# excluded - the broker maintains it from the lumys_enabled directory.
#
# Usage:
#   perl luminum-config.pl set KEY=VALUE [KEY=VALUE ...]
#   perl luminum-config.pl get [KEY ...]
#   perl luminum-config.pl list
#   perl luminum-config.pl --help
#
# Examples:
#   perl luminum-config.pl set CHECKININT=10 MISSINGAFTER=60
#   perl luminum-config.pl set 2FA=Required MINPASS=12
#   perl luminum-config.pl get CHECKININT MISSINGAFTER
#   perl luminum-config.pl list
#
# The install root is the directory containing this script (the installer
# syncs it to the root); database credentials are read from
# <root>/config/broker.conf. --conf PATH overrides that location (useful for
# pointing the tool at a non-default install or a test database).

use strict;
use Cwd qw(abs_path);
use DBI;

# --- install root (same resolution as mkprovision.pl) ------------------------
my $mgrpath = abs_path($0);
my $mgrname = $mgrpath;
$mgrname =~ s{^(\/.*\/)}{};
my $root = $mgrpath;
$root =~ s{\/$mgrname}{};

# --- the settable settings ---------------------------------------------------
# Display order (mirrors the Server Options tabs) and the per-key spec.
#   type: enum (values), int (min), duration (units), host (hostname/IP/empty)
my @ORDER = qw(
	TARGETCONF TCONFTHRESHOLD INVESTIGATE
	ENDPOINTCOMM CHECKININT MISSINGAFTER CMDTIMEOUT DEPLTIMEOUT
	2FA MINPASS COMPLEXPASS PCUPPERLOWER PCLETNUM PCSPECIAL
	UTIMEOUT UTIMEOUTWARN PASSKEYS USERLOGGING
	SENREVS PKGREVS
	REPOHTTP REPONFS REPOSMB
	P2PENABLED
	PNETCHECK SNETCHECK
);

my %SPEC = (
	TARGETCONF     => { type => 'enum',     values => ['Enabled','Disabled'],              def => 'Enabled',  desc => 'Minimum action target confirmation' },
	TCONFTHRESHOLD => { type => 'int',      min => 1,                                      def => '250',    desc => 'Endpoints that trigger action confirmation' },
	INVESTIGATE    => { type => 'enum',     values => ['Enabled','Disabled'],              def => 'Enabled',  desc => 'Enable or disable Luminum Investigate' },
	ENDPOINTCOMM   => { type => 'enum',     values => ['mqtt','direct','hybrid'],          def => 'mqtt',     desc => 'Client communication method' },
	CHECKININT     => { type => 'int',      min => 1,                                      def => '5',      desc => 'Client check-in interval (minutes)' },
	MISSINGAFTER   => { type => 'int',      min => 1,                                      def => '90',     desc => 'Days before offline clients are marked missing' },
	CMDTIMEOUT     => { type => 'int',      min => 1,                                      def => '120',    desc => 'Command timeout (seconds)' },
	DEPLTIMEOUT    => { type => 'int',      min => 1,                                      def => '3600',   desc => 'Deployment timeout (seconds)' },
	"2FA"          => { type => 'enum',     values => ['Required','Optional','Disabled'],  def => 'Optional', desc => 'Two-factor authentication policy' },
	MINPASS        => { type => 'int',      min => 8,                                      def => '8',      desc => 'Minimum password length' },
	COMPLEXPASS    => { type => 'enum',     values => ['Enabled','Disabled'],              def => 'Disabled', desc => 'Password complexity enforcement' },
	PCUPPERLOWER   => { type => 'enum',     values => ['Enabled','Disabled'],              def => 'Disabled', desc => 'Require upper and lowercase letters' },
	PCLETNUM       => { type => 'enum',     values => ['Enabled','Disabled'],              def => 'Disabled', desc => 'Require letters and numbers' },
	PCSPECIAL      => { type => 'enum',     values => ['Enabled','Disabled'],              def => 'Disabled', desc => 'Require special characters' },
	UTIMEOUT       => { type => 'duration', units => ['M','H','D'],                        def => '15M',    desc => 'User inactivity timeout' },
	UTIMEOUTWARN   => { type => 'enum',     values => ['Enabled','Disabled'],              def => 'Enabled',  desc => 'Warn before inactivity logout' },
	PASSKEYS       => { type => 'enum',     values => ['Enabled','Disabled'],              def => 'Disabled', desc => 'PassKey support' },
	USERLOGGING    => { type => 'enum',     values => ['Enabled','Disabled'],              def => 'Disabled', desc => 'Account-specific server logging' },
	SENREVS        => { type => 'int',      min => 0,                                      def => '5',      desc => 'Sensor revision history (0 disables)' },
	PKGREVS        => { type => 'int',      min => 0,                                      def => '5',      desc => 'Package revision history (0 disables)' },
	REPOHTTP       => { type => 'enum',     values => ['Enabled','Disabled'],              def => 'Enabled',  desc => 'File repository: HTTP chunked upload vector' },
	REPONFS        => { type => 'enum',     values => ['Enabled','Disabled'],              def => 'Disabled', desc => 'File repository: NFS staging drop vector' },
	REPOSMB        => { type => 'enum',     values => ['Enabled','Disabled'],              def => 'Disabled', desc => 'File repository: SMB staging drop vector' },
	P2PENABLED     => { type => 'enum',     values => ['Enabled','Disabled'],              def => 'Enabled',  desc => 'P2P file distribution (Disabled: server grants only)' },
	PNETCHECK      => { type => 'host',                                                   def => '',       desc => 'Primary internet connectivity check host' },
	SNETCHECK      => { type => 'host',                                                   def => '',       desc => 'Secondary internet connectivity check host' },
);

# --- usage -------------------------------------------------------------------
sub usage {
	print <<'USAGE';
Luminum Server Configuration Settings

Sets, reads, and lists the tunable server configuration settings stored in
SYSTEM.CONFIG (the same values the web console's Server Options page manages).

Usage:
  perl luminum-config.pl set KEY=VALUE [KEY=VALUE ...]
  perl luminum-config.pl get [KEY ...]
  perl luminum-config.pl list
  perl luminum-config.pl --help

Commands:
  set    Set one or more settings. Every value is validated first; if any is
         invalid nothing is written. Values are matched case-insensitively for
         the choice settings and stored in their canonical form.
  get    Print the current value of the given settings (all of them when no
         keys are named).
  list   Show every supported setting with its current value, the valid values
         (or range), the default, and a short description.

Options:
  --conf PATH   Read the database credentials from PATH instead of
                <install root>/config/broker.conf.
  -h, --help    Show this help.

Examples:
  perl luminum-config.pl set CHECKININT=10 MISSINGAFTER=60
  perl luminum-config.pl set 2FA=Required MINPASS=12
  perl luminum-config.pl set UTIMEOUT=30M COMPLEXPASS=Enabled
  perl luminum-config.pl get CHECKININT MISSINGAFTER
  perl luminum-config.pl list

The install-time identity rows (SID, SKEY, SHOST, the certificate paths, the
signing keypair, ...) are not settable here; they define the server's identity.
USAGE
}

# --- database ----------------------------------------------------------------
# Database credentials from an install's config/broker.conf (same format and
# parsing as mkprovision.pl / luminum-backup.pl).
sub read_broker_conf {
	my ($path) = @_;
	open(my $bc, "<", $path) or die "FATAL: cannot read broker configuration: $path ($!)\n";
	my ($dbuser, $dbpass, $dbhost, $dbsock);
	while (my $line = <$bc>) {
		next if $line =~ /^#/;
		if ($line =~ /^DBUSER[\s|\t]?+\=[\s|\t]?+(\S+)$/) { $dbuser = $1; }
		elsif ($line =~ /^DBPASS[\s|\t]?+\=[\s|\t]?+(.*)$/) { $dbpass = $1; $dbpass =~ s/\s+$//; }
		elsif ($line =~ /^DBHOST[\s|\t]?+\=[\s|\t]?+(\S+)$/) { $dbhost = $1; }
		elsif ($line =~ /^DBSOCKET[\s|\t]?+\=[\s|\t]?+(\S+)$/) { $dbsock = $1; }
	}
	close($bc);
	die "FATAL: $path is missing DBUSER/DBPASS\n" unless defined $dbuser && defined $dbpass;
	return ($dbuser, $dbpass, $dbhost, $dbsock);
}

# Connect to the SYSTEM database (which holds CONFIG).
sub connect_system {
	my ($conf) = @_;
	my $path = defined $conf ? $conf : "$root/config/broker.conf";
	my ($dbuser, $dbpass, $dbhost, $dbsock) = read_broker_conf($path);
	my %attr = ( PrintError => 0, RaiseError => 1 );
	$attr{mysql_socket} = $dbsock if defined $dbsock && $dbsock ne "" && -e $dbsock;
	$attr{mysql_host}   = $dbhost if defined $dbhost && $dbhost ne "";
	my $dbh = eval { DBI->connect("DBI:mysql:SYSTEM", $dbuser, $dbpass, \%attr) };
	die "FATAL: cannot connect to the SYSTEM database: $@\n" unless $dbh;
	return $dbh;
}

# Read every SYSTEM.CONFIG row into a hash.
sub read_config {
	my ($dbh) = @_;
	my %cfg;
	my $sth = $dbh->prepare("select CKEY, CVAL from CONFIG");
	$sth->execute();
	while (my @row = $sth->fetchrow_array()) { $cfg{$row[0]} = $row[1]; }
	$sth->finish();
	return %cfg;
}

# Insert-or-update a CONFIG row. CONFIG has no unique key on CKEY, so this is
# an explicit read-then-write rather than INSERT ... ON DUPLICATE KEY UPDATE.
sub upsert_config {
	my ($dbh, $key, $val) = @_;
	my ($existing) = $dbh->selectrow_array("select CVAL from CONFIG where CKEY = ?", undef, $key);
	if (defined $existing) {
		$dbh->do("update CONFIG set CVAL = ? where CKEY = ?", undef, $val, $key);
	} else {
		$dbh->do("insert into CONFIG (CKEY, CVAL) values (?, ?)", undef, $key, $val);
	}
}

# --- validation ----------------------------------------------------------------
# Returns (1, normalized_value) on success or (0, error_message) on failure.
sub validate {
	my ($key, $val) = @_;
	my $spec = $SPEC{$key};
	return (0, "unknown setting '$key' (see: list)") unless $spec;

	if ($spec->{type} eq 'enum') {
		my %map;
		for my $v (@{ $spec->{values} }) { $map{lc $v} = $v; }
		return (0, "invalid value '$val' for $key (valid: " . join(", ", @{ $spec->{values} }) . ")")
			unless exists $map{lc $val};
		return (1, $map{lc $val});
	}
	if ($spec->{type} eq 'int') {
		return (0, "invalid value '$val' for $key (must be a whole number of " . $spec->{min} . " or more)")
			unless $val =~ /^\d+$/;
		return (0, "invalid value '$val' for $key (must be " . $spec->{min} . " or more)") if $val + 0 < $spec->{min};
		return (1, $val + 0);
	}
	if ($spec->{type} eq 'duration') {
		my $units = join('', @{ $spec->{units} });
		return (0, "invalid value '$val' for $key (form: a whole number followed by one of " . $units . ", e.g. 15M)")
			unless $val =~ /^([1-9]\d*)([$units])$/;
		return (1, $val);
	}
	if ($spec->{type} eq 'host') {
		my $okhost = $val eq ''
			|| $val =~ /^[a-zA-Z0-9]([a-zA-Z0-9.\-]*[a-zA-Z0-9])?$/
			|| $val =~ /^\d{1,3}(\.\d{1,3}){3}$/;
		return (0, "invalid value '$val' for $key (a hostname or IPv4 address, or empty to clear)") unless $okhost;
		return (1, $val);
	}
	return (0, "internal error: no validator for $key");
}

# --- commands ------------------------------------------------------------------
sub cmd_set {
	my ($conf, @pairs) = @_;
	die "ERROR: set requires at least one KEY=VALUE (see --help)\n" unless @pairs;

	my @todo;
	my @errors;
	for my $pair (@pairs) {
		my ($key, $val) = split(/=/, $pair, 2);
		if (!defined $val || $key !~ /^[A-Za-z0-9]+$/) {
			push @errors, "malformed '$pair' (expected KEY=VALUE)";
			next;
		}
		my ($ok, $res) = validate($key, $val);
		if ($ok) { push @todo, [$key, $res]; }
		else { push @errors, $res; }
	}
	if (@errors) {
		print STDERR "ERROR: invalid settings, nothing written:\n";
		print STDERR "  - $_\n" for @errors;
		exit 1;
	}

	my $dbh = connect_system($conf);
	$dbh->{AutoCommit} = 0;
	eval {
		for my $t (@todo) { upsert_config($dbh, $t->[0], $t->[1]); }
		$dbh->commit();
		1;
	} or do {
		eval { $dbh->rollback(); };
		die "FATAL: database update failed: $@\n";
	};
	for my $t (@todo) { print "set $t->[0] = $t->[1]\n"; }
	$dbh->disconnect();
	exit 0;
}

sub cmd_get {
	my ($conf, @keys) = @_;
	my $dbh = connect_system($conf);
	my %cur = read_config($dbh);
	$dbh->disconnect();

	@keys = @ORDER unless @keys;
	for my $k (@keys) {
		warn "WARNING: unknown setting '$k'\n" unless exists $SPEC{$k};
		my $v = $cur{$k};
		print "$k = " . (defined $v ? $v : '(not set)') . "\n";
	}
	exit 0;
}

sub cmd_list {
	my ($conf, @keys) = @_;
	my $dbh = connect_system($conf);
	my %cur = read_config($dbh);
	$dbh->disconnect();

	my @order = @keys ? @keys : @ORDER;
	printf "%-16s  %-12s  %-26s  %-9s  %s\n", "KEY", "CURRENT", "VALID", "DEFAULT", "DESCRIPTION";
	printf "%s\n", "-" x 92;
	for my $k (@order) {
		my $spec = $SPEC{$k};
		unless ($spec) { warn "WARNING: unknown setting '$k'\n"; next; }
		my $valid =
			$spec->{type} eq 'enum'     ? join("|", @{ $spec->{values} }) :
			$spec->{type} eq 'int'      ? "int >= " . $spec->{min} :
			$spec->{type} eq 'duration' ? "N(" . join("", @{ $spec->{units} }) . ")" :
			'host / empty';
		my $cur = defined $cur{$k} ? $cur{$k} : '(not set)';
		printf "%-16s  %-12s  %-26s  %-9s  %s\n", $k, $cur, $valid, $spec->{def}, $spec->{desc};
	}
	exit 0;
}

# --- dispatch ------------------------------------------------------------------
if (!@ARGV) { usage(); exit 1; }

my $conf;
my @args;
while (@ARGV) {
	my $a = shift @ARGV;
	if ($a eq '--conf') { $conf = shift @ARGV; die "ERROR: --conf requires a path\n" unless defined $conf; }
	elsif ($a =~ /^--conf=(.+)$/) { $conf = $1; }
	elsif ($a eq '--help' || $a eq '-h' || $a eq 'help') { usage(); exit 0; }
	else { push @args, $a; }
}
my $cmd = shift @args;
die "ERROR: missing command (set|get|list; see --help)\n" unless defined $cmd;

if ($cmd eq 'set') { cmd_set($conf, @args); }
elsif ($cmd eq 'get') { cmd_get($conf, @args); }
elsif ($cmd eq 'list') { cmd_list($conf, @args); }
else { die "ERROR: unknown command '$cmd' (see --help)\n"; }
