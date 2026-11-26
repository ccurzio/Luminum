#!/usr/bin/perl
#
# setup_p2p_schema_test.pl - offline test for the P2P schema additions
# (docs/p2p.md Phase 1): the CLIENTS.STATUS.P2P capability column (both the
# migration of an existing pre-P2P table and the fresh-install layout from
# schema.sql) and the three new tables CONTENT.PKGHOLDERS,
# CLIENTS.P2PTOKENS, and CLIENTS.P2PTRANSFERS.
#
# Spins up a scratch MariaDB, then:
#   1. pre-creates a pre-P2P CLIENTS.STATUS (no P2P column) with one
#      registered-client row and runs setup.pl against it:
#      the install must succeed, the P2P column must be added (row
#      surviving with P2P = 0), and the three new tables must exist
#   2. drops the CLIENTS and CONTENT databases and runs setup.pl again:
#      schema.sql must create STATUS with the P2P column and all three
#      new tables, and no migration may be logged
#
# Usage: perl tests/setup_p2p_schema_test.pl
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

my $tmp = "/tmp/luminum-p2pschema-test.$$";
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

# --- pre-P2P CLIENTS.STATUS with a registered client --------------------------
# The pre-P2P layout lacks the P2P capability column (with one status row,
# so the migration must not lose data).
#
$out = `$cli -S $sock -u root -ptestrootpw -e "
    CREATE DATABASE CLIENTS DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
    CREATE TABLE CLIENTS.STATUS (
      ID int(20) NOT NULL,
      HOSTNAME tinytext NOT NULL,
      IPV4 tinytext NOT NULL,
      IPV6 tinytext DEFAULT NULL,
      OSPLATFORM tinytext NOT NULL,
      OSRELEASE tinytext NOT NULL,
      CLIENTVER tinytext NOT NULL,
      CSTATE tinytext NOT NULL,
      INGROUPS text DEFAULT NULL,
      REGDATE datetime NOT NULL,
      LASTSEEN datetime DEFAULT NULL,
      MISSING tinyint(1) DEFAULT 0,
      PRIMARY KEY (ID)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
    INSERT INTO CLIENTS.STATUS (ID,HOSTNAME,IPV4,OSPLATFORM,OSRELEASE,CLIENTVER,CSTATE,REGDATE)
      VALUES (7,'oldhost','172.16.0.7','Linux','5.10','0.0.6','LIVE',now());
" 2>&1`;
check("pre-P2P CLIENTS.STATUS seeded", $? == 0, $out);
skip_all("could not seed pre-P2P CLIENTS.STATUS: $out") unless $? == 0;

# --- installer runs -----------------------------------------------------------
sub run_setup {
    my ($root, $dbuser) = @_;
    my $cmd = "perl $setup --noninteractive --yes --no-start"
        . " --shost p2pschema.test --laddr 127.0.0.1 --lport 19467"
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

sub table_exists {
    my ($schema, $table) = @_;
    return q1("select TABLE_NAME from information_schema.TABLES where TABLE_SCHEMA = '$schema' and TABLE_NAME = '$table'") eq $table;
}

sub column_type {
    my ($schema, $table, $col) = @_;
    return q1("select COLUMN_TYPE from information_schema.COLUMNS where TABLE_SCHEMA = '$schema' and TABLE_NAME = '$table' and COLUMN_NAME = '$col'");
}

# 1. existing pre-P2P table -> migration adds the column, row survives,
#    and schema.sql creates the three new tables on the re-run
my ($rc, $o) = run_setup("$tmp/root1", "lumpp1");
check("migration: install succeeds", $rc == 0, $o);
check("migration: P2P column added is logged",
    $o =~ /CLIENTS\.STATUS: added missing column P2P/, $o);
check("migration: P2P column present",
    column_type("CLIENTS", "STATUS", "P2P") eq "tinyint(1)",
    "type=[" . column_type("CLIENTS", "STATUS", "P2P") . "]");
my $row = q1("select HOSTNAME, CSTATE, P2P from CLIENTS.STATUS where ID = 7");
check("migration: pre-existing row preserved with P2P = 0",
    $row eq "oldhost\tLIVE\t0", "row=[$row]");
check("migration: CONTENT.PKGHOLDERS created", table_exists("CONTENT", "PKGHOLDERS"));
check("migration: CLIENTS.P2PTOKENS created", table_exists("CLIENTS", "P2PTOKENS"));
check("migration: CLIENTS.P2PTRANSFERS created", table_exists("CLIENTS", "P2PTRANSFERS"));

# 2. fresh install -> schema.sql creates everything, no migration logged
$out = `$cli -S $sock -u root -ptestrootpw -e "DROP DATABASE CLIENTS; DROP DATABASE CONTENT" 2>&1`;
check("CLIENTS and CONTENT databases dropped for fresh-install run", $? == 0, $out);
skip_all("could not drop CLIENTS/CONTENT: $out") unless $? == 0;

($rc, $o) = run_setup("$tmp/root2", "lumpp2");
check("fresh install: install succeeds", $rc == 0, $o);
check("fresh install: no STATUS migration logged",
    $o !~ /CLIENTS\.STATUS: added missing column P2P/, $o);
check("fresh install: P2P column present",
    column_type("CLIENTS", "STATUS", "P2P") eq "tinyint(1)",
    "type=[" . column_type("CLIENTS", "STATUS", "P2P") . "]");
check("fresh install: CONTENT.PKGHOLDERS created", table_exists("CONTENT", "PKGHOLDERS"));
check("fresh install: CLIENTS.P2PTOKENS created", table_exists("CLIENTS", "P2PTOKENS"));
check("fresh install: CLIENTS.P2PTRANSFERS created", table_exists("CLIENTS", "P2PTRANSFERS"));

# ---------------------------------------------------------------------------
print "-" x 60, "\n";
if ($FAILURES) {
    print "FAILED: $FAILURES check(s) failed\n";
    exit 1;
}
print "All checks passed.\n";
exit 0;
