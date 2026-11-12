#!/usr/bin/perl
#
# setup_rootpw_test.pl - offline test for the installer's database admin
# no-password check.
#
# The admin account may authenticate without a stored password (MariaDB's
# unix_socket root: socket logins succeed for the OS account regardless
# of any supplied password), so a successful admin connection does not
# prove the account has a password. When the operator supplied a DB
# Admin Password, the installer must note that the account has no
# password and offer to set it to the supplied value.
#
# Spins up a scratch MariaDB and creates an admin account authenticated
# via unix_socket (named after the OS user this test runs as), so the
# installer connects successfully with a supplied password even though
# the account stores none:
#   1. helper unit checks: account_has_no_password / set_account_password
#   2. in-process run, offer accepted: install succeeds and the
#      account's password is set to the supplied value (the old
#      passwordless socket login no longer works)
#   3. in-process run, offer declined: install succeeds and the
#      account is left without a password
#   4. non-interactive setup.pl run (no one to ask): install succeeds,
#      the note is printed, and the account is left unchanged
#
# Usage: perl tests/setup_rootpw_test.pl
# Exit code: 0 if all checks pass, 1 otherwise.

use strict;
use warnings;
use FindBin qw($Bin);
use File::Path qw(make_path remove_tree);
use lib "$Bin/../server/lib";
require Luminum::Setup;
use DBI;
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
my $srcdir = "$Bin/../server";
skip_all("setup.pl not found at $setup") unless -f $setup;
# The installer requires root; this test drives it against a scratch
# database as an unprivileged user, so use the test escape hatch.
$ENV{LUMINUM_SETUP_ALLOW_NONROOT} = 1;
my $mariadbd   = which("mariadbd") || which("mysqld");
my $install_db = which("mariadb-install-db") || which("mysql_install_db");
my $cli        = which("mariadb") || which("mysql");
skip_all("mariadbd / mariadb-install-db / mariadb CLI not available")
    unless $mariadbd && $install_db && $cli;

# The full-install cases run the real installer, whose service step
# compile-checks the broker under the PERL5LIB it writes into the start
# script. Detect the module dirs from this process's @INC (seeded by the
# ambient PERL5LIB) and pass them explicitly. The helper unit checks
# (case 1) do not need them.
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
my $perl5lib = join(":", sort values %found);

my $tmp = "/tmp/luminum-rootpw-test.$$";
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

# --- scratch MariaDB ---------------------------------------------------------
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

# The admin account the installer connects as: unix_socket
# authentication named after this process's OS user, so socket logins
# succeed regardless of any supplied password while the account stores
# no password - the exact condition the check targets (MariaDB's
# unix_socket root on a fresh host).
#
my $osuser = (getpwuid($>))[0];
sub make_unix_socket_admin {
    my $o = `$cli -S $sock -u root -e "DROP USER IF EXISTS '$osuser'\@'localhost'; CREATE USER '$osuser'\@'localhost' IDENTIFIED VIA unix_socket; GRANT ALL PRIVILEGES ON *.* TO '$osuser'\@'localhost' WITH GRANT OPTION;" 2>&1`;
    return ($? == 0, $o);
}
my ($mkok, $mkout) = make_unix_socket_admin();
check("unix_socket admin account created", $mkok, $mkout);
skip_all("could not create unix_socket admin account: $mkout") unless $mkok;

# DBI connect helper for the post-run login checks.
sub try_connect {
    my ($user, $pass) = @_;
    my $dbh = eval { DBI->connect("DBI:mysql:", $user, $pass, { mysql_socket => $sock, RaiseError => 1, PrintError => 0 }) };
    $dbh->disconnect() if $dbh;
    return $dbh ? 1 : 0;
}

# --- 1. helper unit checks ----------------------------------------------------
{
    my $dbh = eval { DBI->connect("DBI:mysql:", $osuser, "", { mysql_socket => $sock, RaiseError => 1, PrintError => 0 }) };
    skip_all("cannot connect as $osuser via unix_socket: $@") unless $dbh;
    check("account_has_no_password: unix_socket account reports no password",
        Luminum::Setup::account_has_no_password($dbh, $osuser) == 1);
    check("account_has_no_password: passwordless root reports no password",
        Luminum::Setup::account_has_no_password($dbh, "root") == 1);
    $dbh->do("CREATE USER 'pwuser'\@'localhost' IDENTIFIED BY 'oldpw456'");
    check("account_has_no_password: account with a password reports one",
        Luminum::Setup::account_has_no_password($dbh, "pwuser") == 0);
    check("account_has_no_password: unknown account is undeterminable",
        !defined Luminum::Setup::account_has_no_password($dbh, "nosuchuser"));
    check("set_account_password: returns success",
        Luminum::Setup::set_account_password($dbh, "pwuser", "newpw789") == 1);
    check("set_account_password: new password works", try_connect("pwuser", "newpw789"));
    check("set_account_password: old password no longer works", !try_connect("pwuser", "oldpw456"));
    $dbh->do("DROP USER 'pwuser'\@'localhost'");
    $dbh->disconnect();
}

if (@missing) {
    print "skip - full-install cases: broker modules not in \@INC (" . join(", ", @missing) . ")\n";
    print "-" x 60, "\n";
    if ($FAILURES) { print "FAILED: $FAILURES check(s) failed\n"; exit 1; }
    print "All checks passed.\n";
    exit 0;
}

# In-process full-install run with stdout/stderr captured (the log
# lines are checked below).
sub run_inprocess {
    my (%kw) = @_;
    my $log = "";
    my $rc;
    my $summary;
    {
        my $saveout;
        my $saveerr;
        open($saveout, ">&", \*STDOUT) or die "dup STDOUT: $!";
        open($saveerr, ">&", \*STDERR) or die "dup STDERR: $!";
        open(STDOUT, ">", "$tmp/$kw{logfile}") or die "open log: $!";
        open(STDERR, ">>", "$tmp/$kw{logfile}") or die "open log: $!";
        my @r = eval { Luminum::Setup::run(
            install_root => $kw{root},
            shost        => "rootpw.test", laddr => "127.0.0.1", lport => $kw{lport},
            dbsocket     => $sock,
            dbadmin      => $osuser, dbadminpass => "newrootpw",
            dbuser       => $kw{dbuser},
            adminpass    => "knownadminpw",
            adminemail   => "test\@example.com",
            perl5lib     => $perl5lib,
            srcdir       => $srcdir,
            start        => 0,
            adminpw_offer => $kw{offer},
            ) };
        my $err = $@;
        close(STDOUT);
        close(STDERR);
        open(STDOUT, ">&", $saveout) or die "restore STDOUT: $!";
        open(STDERR, ">&", $saveerr) or die "restore STDERR: $!";
        close($saveout);
        close($saveerr);
        die $err if $err;
        ($summary, $rc) = @r;
    }
    if (open(my $fh, "<", "$tmp/$kw{logfile}")) { $log = do { local $/; <$fh> }; close($fh); }
    return ($rc, $log, $summary);
}

# --- 2. in-process, offer accepted --------------------------------------------
my $offered2 = 0;
my ($rc2, $log2) = run_inprocess(
    root => "$tmp/root2", lport => 19480, dbuser => "lumrp2", logfile => "run2.log",
    offer => sub { my ($u) = @_; $offered2 = ($u eq $osuser) ? 1 : 0; return 1; },
    );
check("offer accepted: install succeeds", $rc2 == 0, "rc=" . (defined $rc2 ? $rc2 : "undef"));
check("offer accepted: callback invoked with the admin account", $offered2 == 1);
check("offer accepted: log says the password was set",
    $log2 =~ /Database $osuser password set to the supplied DB Admin Password/, $log2);
check("offer accepted: account now accepts the supplied password",
    try_connect($osuser, "newrootpw"));
check("offer accepted: passwordless socket login no longer works",
    !try_connect($osuser, ""));

# --- 3. in-process, offer declined --------------------------------------------
check("unix_socket admin account recreated", make_unix_socket_admin());
my $offered3 = 0;
my ($rc3, $log3) = run_inprocess(
    root => "$tmp/root3", lport => 19481, dbuser => "lumrp3", logfile => "run3.log",
    offer => sub { $offered3 = 1; return 0; },
    );
check("offer declined: install succeeds", $rc3 == 0, "rc=" . (defined $rc3 ? $rc3 : "undef"));
check("offer declined: callback invoked", $offered3 == 1);
check("offer declined: log says the account was left unchanged",
    $log3 =~ /Database $osuser account has no password; left unchanged/, $log3);
check("offer declined: passwordless socket login still works",
    try_connect($osuser, ""));

# --- 4. non-interactive setup.pl (no one to ask) --------------------------------
check("unix_socket admin account recreated", make_unix_socket_admin());
my $cmd = "perl $setup --noninteractive --yes --no-start"
    . " --shost rootpw.test --laddr 127.0.0.1 --lport 19482"
    . " --install-root $tmp/root4 --dbsocket $sock"
    . " --dbadmin $osuser --dbadminpass newrootpw"
    . " --dbuser lumrp4 --adminemail test\@example.com"
    . " --perl5lib $perl5lib";
my $o4 = `$cmd 2>&1`;
my $rc4 = $? >> 8;
check("non-interactive: install succeeds", $rc4 == 0, $o4);
check("non-interactive: note about the missing password is printed",
    $o4 =~ /the database $osuser account has no password set/, $o4);
check("non-interactive: account left unchanged (passwordless login works)",
    try_connect($osuser, ""));

# ---------------------------------------------------------------------------
print "-" x 60, "\n";
if ($FAILURES) {
    print "FAILED: $FAILURES check(s) failed\n";
    exit 1;
}
print "All checks passed.\n";
exit 0;
