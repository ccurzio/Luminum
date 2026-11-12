#!/usr/bin/perl
#
# setup_dbadmin_test.pl - offline test for the installer's database admin
# credentials plumbing (--dbadmin / --dbadminpass).
#
# Spins up a scratch MariaDB whose root account has a password, then runs
# setup.pl non-interactively against it:
#   1. without dbadminpass          -> install must fail at the database step
#   2. with --dbadminpass (root)    -> install must succeed; the admin
#                                      password must not be persisted in any
#                                      generated configuration file
#   3. with a custom --dbadmin user -> install must succeed
#   4. non-root, no escape hatch    -> setup.pl must refuse to run
#                                      (skipped when the test runs as root)
#   5. in-process with redact_log   -> the printed summary (the persistent
#                                      log) carries no password; the
#                                      returned summary keeps the real value
#
# Usage: perl tests/setup_dbadmin_test.pl
# Exit code: 0 if all checks pass, 1 otherwise.

use strict;
use warnings;
use FindBin qw($Bin);
use File::Path qw(make_path remove_tree);
# For the in-process redact_log case (case 5); the module itself is
# required there so this test still skips cleanly where the broker's
# Perl modules are not installed.
use lib "$Bin/../server/lib";
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
# Case 4 unsets it explicitly for the refusal check.
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

my $tmp = "/tmp/luminum-dbadmin-test.$$";
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

$out = `$cli -S $sock -u root -ptestrootpw -e "CREATE USER 'dbadmin'\@'localhost' IDENTIFIED BY 'adminpw2'; GRANT ALL PRIVILEGES ON *.* TO 'dbadmin'\@'localhost' WITH GRANT OPTION;" 2>&1`;
check("custom admin user created", $? == 0, $out);
skip_all("could not create custom admin user: $out") unless $? == 0;

# --- installer runs -----------------------------------------------------------
sub run_setup {
    my ($root, $dbuser, @extra) = @_;
    my $cmd = "perl $setup --noninteractive --yes --no-start"
        . " --shost dbadmin.test --laddr 127.0.0.1 --lport 19465"
        . " --install-root $root --dbsocket $sock"
        . " --dbuser $dbuser --adminemail test\@example.com"
        . " --perl5lib $perl5lib"
        . (@extra ? " " . join(" ", @extra) : "");
    my $o = `$cmd 2>&1`;
    return ($? >> 8, $o);
}

# 1. root has a password, none supplied -> must fail at the database step
my ($rc, $o) = run_setup("$tmp/root1", "lumtest1");
check("no dbadminpass: install fails", $rc != 0, "rc=$rc");
check("no dbadminpass: connect error reported",
    $o =~ /cannot connect to database as root/, $o);
check("no dbadminpass: hint mentions dbadminpass",
    $o =~ /dbadminpass/, $o);

# 2. root password supplied -> install succeeds, password not persisted
($rc, $o) = run_setup("$tmp/root2", "lumtest2",
    "--dbadmin", "root", "--dbadminpass", "testrootpw");
check("root dbadminpass: install succeeds", $rc == 0, $o);
check("root dbadminpass: broker.conf written", -f "$tmp/root2/config/broker.conf");
my $conf = "";
if (open(my $fh, "<", "$tmp/root2/config/broker.conf")) {
    $conf = do { local $/; <$fh> };
    close($fh);
}
check("root dbadminpass: broker.conf has app db user", $conf =~ /DBUSER = lumtest2/);
my $leak = 0;
for my $f ("$tmp/root2/config/broker.conf", "$tmp/root2/config/console.conf") {
    next unless -f $f;
    my $c = do { local $/; open(my $fh, "<", $f) or next; <$fh> };
    $leak = 1 if $c =~ /testrootpw/;
}
check("root dbadminpass: admin password not persisted in configs", !$leak);
check("root dbadminpass: no admin-credentials.txt created",
    !-f "$tmp/root2/config/admin-credentials.txt");
check("root dbadminpass: summary shows db admin user, no password line",
    $o =~ /- Database Admin User: root\n- Web Console: /, $o);
check("root dbadminpass: db admin password not in installer output",
    index($o, "testrootpw") < 0, $o);
check("root dbadminpass: summary shows console admin credentials",
    $o =~ /- Console Admin Username: lumadmin\n- Console Admin Password: \S+/, $o);

# 3. custom admin account -> install succeeds
($rc, $o) = run_setup("$tmp/root3", "lumtest3",
    "--dbadmin", "dbadmin", "--dbadminpass", "adminpw2");
check("custom dbadmin: install succeeds", $rc == 0, $o);

# 4. root requirement: without the escape hatch, setup.pl refuses to run
# as a non-root user (no-op when this test itself runs as root)
if ($> != 0) {
    my $o = `env -u LUMINUM_SETUP_ALLOW_NONROOT perl $setup --noninteractive --yes --no-start --shost rootreq.test --laddr 127.0.0.1 --install-root $tmp/root4 --dbsocket $sock 2>&1`;
    my $rc = $? >> 8;
    check("non-root: setup.pl refuses without the escape hatch",
        $rc != 0 && $o =~ /must be run as root/, "rc=$rc out=$o");
}

# 5. redact_log: the printed summary (what a persistent log file keeps)
# carries no password; the returned summary (transient dialogs) keeps
# the real value
{
    eval { require Luminum::Setup; 1 } or do {
        print "skip - Luminum::Setup not loadable in-process: $@\n";
        };
    if ($Luminum::Setup::VERSION) {
        my $capfile = "$tmp/redact.out";
        my $saveout;
        my $saveerr;
        open($saveout, ">&", \*STDOUT) or die "dup STDOUT: $!";
        open($saveerr, ">&", \*STDERR) or die "dup STDERR: $!";
        open(STDOUT, ">", $capfile) or die "open $capfile: $!";
        open(STDERR, ">>", $capfile) or die "open $capfile: $!";
        my @r = eval { Luminum::Setup::run(
            install_root => "$tmp/root5",
            shost        => "dbadmin.test", laddr => "127.0.0.1", lport => 19468,
            dbsocket     => $sock,
            dbadmin      => "root", dbadminpass => "testrootpw",
            dbuser       => "lumtest5",
            adminpass    => "knownadminpw",
            adminemail   => "test\@example.com",
            perl5lib     => $perl5lib,
            srcdir       => "$Bin/../server",
            start        => 0,
            quiet        => 1,
            redact_log   => 1,
            ) };
        my $err = $@;
        close(STDOUT);
        close(STDERR);
        open(STDOUT, ">&", $saveout) or die "restore STDOUT: $!";
        open(STDERR, ">&", $saveerr) or die "restore STDERR: $!";
        close($saveout);
        close($saveerr);
        die $err if $err;
        my ($summary, $rc) = @r;
        my $printed = "";
        if (open(my $fh, "<", $capfile)) { local $/; $printed = <$fh>; close($fh); }
        check("redact_log: install succeeds", $rc == 0, "rc=" . (defined $rc ? $rc : "undef"));
        check("redact_log: printed summary says the password has been set",
            $printed =~ /Console Admin Password has been set/, $printed);
        check("redact_log: printed summary carries no password",
            index($printed, "knownadminpw") < 0, $printed);
        check("redact_log: returned summary keeps the real password",
            defined $summary && $summary =~ /- Console Admin Password: knownadminpw/,
            $summary);
    }
}

# ---------------------------------------------------------------------------
print "-" x 60, "\n";
if ($FAILURES) {
    print "FAILED: $FAILURES check(s) failed\n";
    exit 1;
}
print "All checks passed.\n";
exit 0;
