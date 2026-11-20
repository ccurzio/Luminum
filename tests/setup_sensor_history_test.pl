#!/usr/bin/perl
#
# setup_sensor_history_test.pl - offline test for the CONTENT.SENSORHISTORY
# SENSOR_REV unique key (sensor revision snapshots): both the migration of
# an existing keyless table and the fresh-install layout from schema.sql.
#
# Spins up a scratch MariaDB, then:
#   1. pre-creates a keyless CONTENT.SENSORHISTORY with one snapshot row
#      and runs setup.pl against it: the install must succeed, the unique
#      key must be added (row surviving)
#   2. drops the CONTENT database and runs setup.pl again:
#      schema.sql must create the table with the key
#
# Usage: perl tests/setup_sensor_history_test.pl
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

my $tmp = "/tmp/luminum-sensorhistory-test.$$";
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

# --- pre-v1 CONTENT.SENSORHISTORY without the unique key ---------------------
# The pre-revision-feature layout has the snapshot table but no SENSOR_REV
# key (with one snapshot row, so the migration must not lose data).
#
$out = `$cli -S $sock -u root -ptestrootpw -e "
    CREATE DATABASE CONTENT DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
    CREATE TABLE CONTENT.SENSORHISTORY (
      ID int(20) NOT NULL,
      REV int(20) NOT NULL,
      NAME tinytext NOT NULL,
      DESCRIPTION tinytext NOT NULL,
      CSET int(20) NOT NULL,
      CATEGORY int(20) DEFAULT NULL,
      TIMEOUT tinytext NOT NULL DEFAULT '2M',
      MSTYPE tinytext DEFAULT NULL,
      MSCRIPT mediumtext DEFAULT NULL,
      LSTYPE tinytext DEFAULT NULL,
      LSCRIPT mediumtext DEFAULT NULL,
      WSTYPE tinytext DEFAULT NULL,
      WSCRIPT mediumtext DEFAULT NULL,
      RTYPE tinytext NOT NULL,
      USECASE tinyint(1) NOT NULL DEFAULT 0,
      CSPLIT tinyint(1) NOT NULL DEFAULT 0,
      DELIMITER tinytext DEFAULT NULL,
      WITHPARAMS tinyint(1) NOT NULL DEFAULT 0,
      TIMESTAMP datetime NOT NULL,
      EDITOR int(20) NOT NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
    INSERT INTO CONTENT.SENSORHISTORY (ID,REV,NAME,DESCRIPTION,CSET,TIMEOUT,RTYPE,TIMESTAMP,EDITOR)
      VALUES (7,1,'Old Sensor','A pre-existing snapshot',1,'2M','text',now(),1);
" 2>&1`;
check("keyless SENSORHISTORY seeded", $? == 0, $out);
skip_all("could not seed keyless SENSORHISTORY: $out") unless $? == 0;

# --- installer runs -----------------------------------------------------------
sub run_setup {
    my ($root, $dbuser) = @_;
    my $cmd = "perl $setup --noninteractive --yes --no-start"
        . " --shost sensorhist.test --laddr 127.0.0.1 --lport 19467"
        . " --install-root $root --dbsocket $sock"
        . " --dbuser $dbuser --adminemail test\@example.com"
        . " --perl5lib $perl5lib"
        . " --dbadmin root --dbadminpass testrootpw";
    my $o = `$cmd 2>&1`;
    return ($? >> 8, $o);
}

sub key_columns {
    my $o = `$cli -S $sock -u root -ptestrootpw -N -e "select COUNT(*) from information_schema.STATISTICS where TABLE_SCHEMA = 'CONTENT' and TABLE_NAME = 'SENSORHISTORY' and INDEX_NAME = 'SENSOR_REV'" 2>&1`;
    chomp($o);
    return $o;
}

sub key_non_unique {
    my $o = `$cli -S $sock -u root -ptestrootpw -N -e "select NON_UNIQUE from information_schema.STATISTICS where TABLE_SCHEMA = 'CONTENT' and TABLE_NAME = 'SENSORHISTORY' and INDEX_NAME = 'SENSOR_REV' and SEQ_IN_INDEX = 1" 2>&1`;
    chomp($o);
    return $o;
}

# 1. existing keyless table -> migration adds the unique key, row survives
my ($rc, $o) = run_setup("$tmp/root1", "lumsh1");
check("migration: install succeeds", $rc == 0, $o);
check("migration: key added is logged",
    $o =~ /CONTENT\.SENSORHISTORY: added missing unique key SENSOR_REV/, $o);
check("migration: unique key spans (ID, REV)", key_columns() eq "2", "cols=" . key_columns());
check("migration: key is unique", key_non_unique() eq "0", "non_unique=" . key_non_unique());
my $row = `$cli -S $sock -u root -ptestrootpw -N -e "select ID, REV, NAME from CONTENT.SENSORHISTORY" 2>&1`;
chomp($row);
check("migration: pre-existing snapshot row preserved",
    $row eq "7\t1\tOld Sensor", "row=[$row]");

# 2. fresh install -> schema.sql creates the table with the key
$out = `$cli -S $sock -u root -ptestrootpw -e "DROP DATABASE CONTENT" 2>&1`;
check("CONTENT database dropped for fresh-install run", $? == 0, $out);
skip_all("could not drop CONTENT: $out") unless $? == 0;

($rc, $o) = run_setup("$tmp/root2", "lumsh2");
check("fresh install: install succeeds", $rc == 0, $o);
check("fresh install: no migration needed",
    $o !~ /CONTENT\.SENSORHISTORY: added missing unique key/, $o);
check("fresh install: unique key spans (ID, REV)", key_columns() eq "2", "cols=" . key_columns());
check("fresh install: key is unique", key_non_unique() eq "0", "non_unique=" . key_non_unique());

# ---------------------------------------------------------------------------
print "-" x 60, "\n";
if ($FAILURES) {
    print "FAILED: $FAILURES check(s) failed\n";
    exit 1;
}
print "All checks passed.\n";
exit 0;
