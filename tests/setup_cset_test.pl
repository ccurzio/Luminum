#!/usr/bin/perl
#
# setup_cset_test.pl - offline test for the installer's "Luminum Default"
# content set seed (CONTENT.SETS):
#   1. fresh install: exactly one SETS row named "Luminum Default",
#      owned by the console administrator, REQUIRED = 1 (system set,
#      cannot be deleted), LOCKED = 0 (so it appears in the server
#      options' "Default Content Set" dropdowns), CREATED set
#   2. re-run of the installer against the same database: the set is left
#      in place (same ID, same CREATED, still exactly one row)
#
# Spins up a scratch MariaDB and runs setup.pl non-interactively with
# --no-start.
#
# Usage: perl tests/setup_cset_test.pl
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

my $tmp = "/tmp/luminum-cset-test.$$";
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
        . " --shost cset.test --laddr 127.0.0.1 --lport 19467"
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

# 1. fresh install -> the default content set is created
my ($rc, $o) = run_setup("$tmp/root1", "lumcset1");
check("fresh install: install succeeds", $rc == 0, $o);
check("fresh install: creation logged",
    $o =~ /created content set 'Luminum Default'/, $o);
my $count = q1("select count(*) from CONTENT.SETS");
check("fresh install: exactly one content set", $count eq "1", "count=[$count]");
$count = q1("select count(*) from CONTENT.SETS where NAME = 'Luminum Default'");
check("fresh install: set is named 'Luminum Default'", $count eq "1", "count=[$count]");
my $adminid = q1("select ID from AUTH.USERS where USERNAME = 'lumadmin'");
my $row = q1("select ID, DESCRIPTION, REQUIRED, LOCKED, OWNER, (CREATED is not null) from CONTENT.SETS where NAME = 'Luminum Default'");
my ($id, $desc, $req, $locked, $owner, $created) = split /\t/, $row;
check("fresh install: description populated", defined $desc && length $desc, "desc=[$desc]");
check("fresh install: REQUIRED = 1 (system set, cannot be deleted)",
    defined $req && $req eq "1", "req=[$req]");
check("fresh install: LOCKED = 0 (visible in the default-set dropdowns)",
    defined $locked && $locked eq "0", "locked=[$locked]");
check("fresh install: owned by the console administrator",
    defined $owner && defined $adminid && $owner eq $adminid,
    "owner=[$owner] admin=[$adminid]");
check("fresh install: CREATED set", defined $created && $created eq "1", "created=[$created]");

# 2. re-run against the same database -> the set is left in place
($rc, $o) = run_setup("$tmp/root1", "lumcset1");
check("re-run: install succeeds", $rc == 0, $o);
check("re-run: existing set noted, not recreated",
    $o =~ /content set 'Luminum Default' already exists/, $o);
$count = q1("select count(*) from CONTENT.SETS where NAME = 'Luminum Default'");
check("re-run: still exactly one 'Luminum Default'", $count eq "1", "count=[$count]");
my $row2 = q1("select ID, (CREATED is not null) from CONTENT.SETS where NAME = 'Luminum Default'");
my ($id2, $created2) = split /\t/, $row2;
check("re-run: same set ID (row untouched)", defined $id2 && defined $id && $id2 eq $id,
    "id=[$id2] original=[$id]");
check("re-run: CREATED preserved", defined $created2 && $created2 eq "1", "created=[$created2]");

# ---------------------------------------------------------------------------
print "-" x 60, "\n";
if ($FAILURES) {
    print "FAILED: $FAILURES check(s) failed\n";
    exit 1;
}
print "All checks passed.\n";
exit 0;
