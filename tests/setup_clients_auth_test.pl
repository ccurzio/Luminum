#!/usr/bin/perl
#
# setup_clients_auth_test.pl - offline test for the CLIENTS.AUTH
# MQTTSECRET column (protocol 3.1): both the migration of an existing
# pre-v1 table and the fresh-install layout from schema.sql.
#
# Spins up a scratch MariaDB, then:
#   1. pre-creates a pre-v1 CLIENTS.AUTH (no MQTTSECRET) with one
#      registered-client row and runs setup.pl against it:
#      the install must succeed, the column must be added, and the
#      existing row must survive with an empty hash
#   2. drops the CLIENTS database and runs setup.pl again:
#      schema.sql must create the table with the column already present
#
# Usage: perl tests/setup_clients_auth_test.pl
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

my $tmp = "/tmp/luminum-clientsauth-test.$$";
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

# --- pre-v1 CLIENTS.AUTH with a registered client ----------------------------
# The pre-1.0 layout lacks MQTTSECRET; one row simulates an installation
# that already registered a client before the column existed.
#
my $fpnt = "cfd346d21ef5690deb109beef00000000000000000000000000000000000000ab";
$out = `$cli -S $sock -u root -ptestrootpw -e "
    CREATE DATABASE CLIENTS DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
    CREATE TABLE CLIENTS.AUTH (
      ID int(20) NOT NULL AUTO_INCREMENT,
      NAME tinytext NOT NULL,
      FINGERPRINT tinytext NOT NULL,
      PUBKEY text NOT NULL,
      PRIMARY KEY (ID)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
    INSERT INTO CLIENTS.AUTH (NAME,FINGERPRINT,PUBKEY) VALUES ('oldhost','$fpnt','cHViay==');
" 2>&1`;
check("pre-v1 CLIENTS.AUTH seeded", $? == 0, $out);
skip_all("could not seed pre-v1 CLIENTS.AUTH: $out") unless $? == 0;

# --- installer runs -----------------------------------------------------------
sub run_setup {
    my ($root, $dbuser) = @_;
    my $cmd = "perl $setup --noninteractive --yes --no-start"
        . " --shost clientsauth.test --laddr 127.0.0.1 --lport 19466"
        . " --install-root $root --dbsocket $sock"
        . " --dbuser $dbuser --adminemail test\@example.com"
        . " --perl5lib $perl5lib"
        . " --dbadmin root --dbadminpass testrootpw";
    my $o = `$cmd 2>&1`;
    return ($? >> 8, $o);
}

sub auth_columns {
    my $o = `$cli -S $sock -u root -ptestrootpw -N -e "select COLUMN_NAME from information_schema.COLUMNS where TABLE_SCHEMA = 'CLIENTS' and TABLE_NAME = 'AUTH'" 2>&1`;
    return split /\n/, $o;
}

# 1. existing pre-v1 table -> migration adds the column, row survives
my ($rc, $o) = run_setup("$tmp/root1", "lumca1");
check("migration: install succeeds", $rc == 0, $o);
check("migration: column added is logged",
    $o =~ /CLIENTS\.AUTH: added missing column MQTTSECRET/, $o);
my %cols = map { $_ => 1 } auth_columns();
check("migration: MQTTSECRET column present", $cols{MQTTSECRET});
my $row = `$cli -S $sock -u root -ptestrootpw -N -e "select NAME, MQTTSECRET from CLIENTS.AUTH where FINGERPRINT = '$fpnt'" 2>&1`;
chomp($row);
check("migration: pre-existing row preserved with empty hash",
    $row eq "oldhost\t", "row=[$row]");

# 2. fresh install -> schema.sql creates the table with the column
$out = `$cli -S $sock -u root -ptestrootpw -e "DROP DATABASE CLIENTS" 2>&1`;
check("CLIENTS database dropped for fresh-install run", $? == 0, $out);
skip_all("could not drop CLIENTS: $out") unless $? == 0;

($rc, $o) = run_setup("$tmp/root2", "lumca2");
check("fresh install: install succeeds", $rc == 0, $o);
check("fresh install: no migration needed",
    $o !~ /CLIENTS\.AUTH: added missing column MQTTSECRET/, $o);
%cols = map { $_ => 1 } auth_columns();
check("fresh install: MQTTSECRET column present", $cols{MQTTSECRET});

# ---------------------------------------------------------------------------
print "-" x 60, "\n";
if ($FAILURES) {
    print "FAILED: $FAILURES check(s) failed\n";
    exit 1;
}
print "All checks passed.\n";
exit 0;
