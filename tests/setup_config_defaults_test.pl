#!/usr/bin/perl
#
# setup_config_defaults_test.pl - offline test for the installer's
# default-only SYSTEM.CONFIG rows (ENDPOINTCOMM, MISSINGAFTER,
# CMDTIMEOUT, DEPLTIMEOUT, CHECKININT, TARGETCONF, TCONFTHRESHOLD, 2FA,
# MINPASS, COMPLEXPASS, UTIMEOUT, UTIMEOUTWARN, SENREVS, PKGREVS,
# INVESTIGATE):
#   1. fresh install: ENDPOINTCOMM is seeded to "mqtt", MISSINGAFTER to
#      "90" (days), CMDTIMEOUT to "120" (s), DEPLTIMEOUT to "3600" (s),
#      CHECKININT to "5" (min), TARGETCONF to "Enabled", TCONFTHRESHOLD
#      to "250" (endpoints), 2FA to "Optional", MINPASS to "8",
#      COMPLEXPASS to "Disabled", UTIMEOUT to "15M" (minutes),
#      UTIMEOUTWARN to "Enabled", SENREVS to "5", PKGREVS to "5",
#      INVESTIGATE to "Enabled"
#   2. values later changed "in the console" (simulated with direct
#      UPDATEs) survive a re-run of the installer - the defaults must
#      not clobber them
#
# Spins up a scratch MariaDB and runs setup.pl non-interactively with
# --no-start.
#
# Usage: perl tests/setup_config_defaults_test.pl
# Exit code: 0 if all checks pass, 1 otherwise.

use strict;
use warnings;
use FindBin qw($Bin);
use File::Path qw(make_path remove_tree);
# Time::HiRes::sleep, not core sleep: core sleep truncates fractional
# arguments to whole seconds, so "sleep 0.5" would be a no-op and the
# readiness loop below would busy-spin through all its iterations
# before the scratch server had started.
#
use Time::HiRes qw(sleep);

my $FAILURES = 0;
sub check {
    my ($name, $ok, $detail) = @_;
    if ($ok) {
        print "ok   - $name\n";
    } else {
        $FAILURES++;
        print "FAIL - $name" . (defined $detail ? " ($detail)" : "") . "\n";
    }
}
sub skip_all {
    my ($why) = @_;
    print "SKIP - $why\n";
    print "All checks passed.\n";
    exit 0;
}

sub which {
    my ($bin) = @_;
    for my $dir (split /:/, ($ENV{PATH} || "")) {
        my $p = "$dir/$bin";
        return $p if -x $p;
    }
    return undef;
}

my $setup = "$Bin/../server/setup.pl";
skip_all("setup.pl not found at $setup") unless -f $setup;
# The installer requires root; this test drives it against a scratch
# database as an unprivileged user, so use the test escape hatch.
$ENV{LUMINUM_SETUP_ALLOW_NONROOT} = 1;
my $mariadbd   = which("mariadbd") || which("mysqld");
my $install_db = which("mariadb-install-db") || which("mysql_install_db");
my $cli        = which("mariadb") || which("mysql");
skip_all("mariadbd / mariadb-install-db / mariadb CLI not available")
    unless $mariadbd && $install_db && $cli;

# The installer's service step compile-checks the broker under the
# PERL5LIB it writes into the start script. Detect the module dirs from
# this process's @INC (seeded by the ambient PERL5LIB) and pass them
# explicitly so the test does not depend on setup.pl's own detection.
#
my @need = ("IO/Socket/SSL.pm", "Crypt/Perl/Ed25519/PrivateKey.pm");
my %found;
for my $dir (@INC) {
    next unless defined $dir && length $dir;
    for my $mod (@need) {
        next if $found{$mod};
        $found{$mod} = $dir if -f "$dir/$mod";
    }
}
my @missing = grep { !$found{$_} } @need;
skip_all("broker modules not in \@INC (" . join(", ", @missing)
    . "); set PERL5LIB and re-run") if @missing;
my $perl5lib = join(":", sort values %found);

my $tmp = "/tmp/luminum-config-defaults-test.$$";
my $sock = "$tmp/mysql.sock";
my $pidfile = "$tmp/mysql.pid";
END {
    if (defined $tmp) {
        if (-f $pidfile) {
            my $pid = do { local $/; open(my $fh, "<", $pidfile) or return; <$fh> };
            chomp($pid) if defined $pid;
            if (defined $pid && $pid =~ /^\d+$/) {
                kill 15, $pid;
                for (1 .. 40) { last unless kill(0, $pid); sleep(0.25); }
                kill 9, $pid if kill(0, $pid);
            }
        }
        remove_tree($tmp);
    }
}

# --- scratch MariaDB with a root password -----------------------------------
make_path("$tmp/tmp");
my $out = `$install_db --datadir=$tmp/data --auth-root-authentication-method=normal --skip-test-db 2>&1`;
skip_all("mariadb-install-db failed: $out") unless $? == 0;

my $errlog = "$tmp/mariadbd.err";
system("$mariadbd --datadir=$tmp/data --socket=$sock --pid-file=$pidfile "
    . "--tmpdir=$tmp/tmp --skip-networking > $errlog 2>&1 &");
# Readiness probe as root: the CLI's default user is the OS account,
# which does not exist in the scratch server and would deny forever.
#
my $ready = 0;
for (1 .. 60) {
    if (`$cli -S $sock -u root -e 'SELECT 1' 2>/dev/null` ne "") { $ready = 1; last; }
    sleep(0.5);
}
check("scratch MariaDB starts", $ready, `cat $errlog 2>/dev/null`);
skip_all("scratch MariaDB did not start") unless $ready;

$out = `$cli -S $sock -u root -e "ALTER USER 'root'\@'localhost' IDENTIFIED BY 'testrootpw'; FLUSH PRIVILEGES;" 2>&1`;
check("root password set", $? == 0, $out);
skip_all("could not set root password: $out") unless $? == 0;

# --- installer runs -----------------------------------------------------------
sub run_setup {
    my ($root, $dbuser) = @_;
    my $cmd = "perl $setup --noninteractive --yes --no-start"
        . " --shost configdefaults.test --laddr 127.0.0.1 --lport 19469"
        . " --install-root $root --dbsocket $sock"
        . " --dbuser $dbuser --adminemail test\@example.com"
        . " --perl5lib $perl5lib"
        . " --dbadmin root --dbadminpass testrootpw";
    my $o = `$cmd 2>&1`;
    return ($? >> 8, $o);
}

sub q1 {
    my ($sql) = @_;
    my $o = `$cli -S $sock -u root -ptestrootpw -N -e "$sql" 2>&1`;
    chomp($o);
    return $o;
}

# 1. fresh install -> the defaults are seeded
my ($rc, $o) = run_setup("$tmp/root1", "lumdef1");
check("fresh install: install succeeds", $rc == 0, $o);
my $val = q1("select CVAL from SYSTEM.CONFIG where CKEY = 'ENDPOINTCOMM'");
check("fresh install: ENDPOINTCOMM seeded to 'mqtt'", $val eq "mqtt", "val=[$val]");
$val = q1("select CVAL from SYSTEM.CONFIG where CKEY = 'MISSINGAFTER'");
check("fresh install: MISSINGAFTER seeded to '90' (days)", $val eq "90", "val=[$val]");
$val = q1("select CVAL from SYSTEM.CONFIG where CKEY = 'CMDTIMEOUT'");
check("fresh install: CMDTIMEOUT seeded to '120' (s)", $val eq "120", "val=[$val]");
$val = q1("select CVAL from SYSTEM.CONFIG where CKEY = 'DEPLTIMEOUT'");
check("fresh install: DEPLTIMEOUT seeded to '3600' (s)", $val eq "3600", "val=[$val]");
$val = q1("select CVAL from SYSTEM.CONFIG where CKEY = 'CHECKININT'");
check("fresh install: CHECKININT seeded to '5' (min)", $val eq "5", "val=[$val]");
$val = q1("select CVAL from SYSTEM.CONFIG where CKEY = 'TARGETCONF'");
check("fresh install: TARGETCONF seeded to 'Enabled'", $val eq "Enabled", "val=[$val]");
$val = q1("select CVAL from SYSTEM.CONFIG where CKEY = 'TCONFTHRESHOLD'");
check("fresh install: TCONFTHRESHOLD seeded to '250' (endpoints)", $val eq "250", "val=[$val]");
$val = q1("select CVAL from SYSTEM.CONFIG where CKEY = '2FA'");
check("fresh install: 2FA seeded to 'Optional'", $val eq "Optional", "val=[$val]");
$val = q1("select CVAL from SYSTEM.CONFIG where CKEY = 'MINPASS'");
check("fresh install: MINPASS seeded to '8' (characters)", $val eq "8", "val=[$val]");
$val = q1("select CVAL from SYSTEM.CONFIG where CKEY = 'COMPLEXPASS'");
check("fresh install: COMPLEXPASS seeded to 'Disabled'", $val eq "Disabled", "val=[$val]");
$val = q1("select CVAL from SYSTEM.CONFIG where CKEY = 'UTIMEOUT'");
check("fresh install: UTIMEOUT seeded to '15M' (minutes)", $val eq "15M", "val=[$val]");
$val = q1("select CVAL from SYSTEM.CONFIG where CKEY = 'UTIMEOUTWARN'");
check("fresh install: UTIMEOUTWARN seeded to 'Enabled'", $val eq "Enabled", "val=[$val]");
$val = q1("select CVAL from SYSTEM.CONFIG where CKEY = 'SENREVS'");
check("fresh install: SENREVS seeded to '5' (revisions, > 0 = enabled)", $val eq "5", "val=[$val]");
$val = q1("select CVAL from SYSTEM.CONFIG where CKEY = 'PKGREVS'");
check("fresh install: PKGREVS seeded to '5' (revisions, > 0 = enabled)", $val eq "5", "val=[$val]");
$val = q1("select CVAL from SYSTEM.CONFIG where CKEY = 'INVESTIGATE'");
check("fresh install: INVESTIGATE seeded to 'Enabled'", $val eq "Enabled", "val=[$val]");

# 2. console changes -> survive a re-run
my %changed = (
	ENDPOINTCOMM   => "hybrid",
	MISSINGAFTER   => "45",
	CMDTIMEOUT     => "60",
	DEPLTIMEOUT    => "1800",
	CHECKININT     => "10",
	TARGETCONF     => "Disabled",
	TCONFTHRESHOLD => "100",
	"2FA"          => "Required",
	MINPASS        => "12",
	COMPLEXPASS    => "Enabled",
	UTIMEOUT       => "30M",
	UTIMEOUTWARN   => "Disabled",
	SENREVS        => "10",
	PKGREVS        => "0",
	INVESTIGATE    => "Disabled",
	);
for my $ckey (sort keys %changed) {
	$out = `$cli -S $sock -u root -ptestrootpw -e "update SYSTEM.CONFIG set CVAL = '$changed{$ckey}' where CKEY = '$ckey';" 2>&1`;
	check("console change simulated ($ckey = $changed{$ckey})", $? == 0, $out);
	}
($rc, $o) = run_setup("$tmp/root1", "lumdef1");
check("re-run: install succeeds", $rc == 0, $o);
for my $ckey (sort keys %changed) {
	$val = q1("select CVAL from SYSTEM.CONFIG where CKEY = '$ckey'");
	check("re-run: $ckey console value preserved (not reset to the default)",
	    $val eq $changed{$ckey}, "val=[$val]");
	}

# 3. a hand-removed row is restored on the next run (the schema's
# NOT NULL covers column values, not row existence)
$out = `$cli -S $sock -u root -ptestrootpw -e "delete from SYSTEM.CONFIG where CKEY = 'UTIMEOUT';" 2>&1`;
check("row hand-removed (UTIMEOUT deleted)", $? == 0, $out);
($rc, $o) = run_setup("$tmp/root1", "lumdef1");
check("re-run after row removal: install succeeds", $rc == 0, $o);
$val = q1("select CVAL from SYSTEM.CONFIG where CKEY = 'UTIMEOUT'");
check("re-run after row removal: UTIMEOUT restored to the default",
    $val eq "15M", "val=[$val]");

# ---------------------------------------------------------------------------
print "-" x 60, "\n";
if ($FAILURES) {
    print "FAILED: $FAILURES check(s) failed\n";
    exit 1;
}
print "All checks passed.\n";
exit 0;
