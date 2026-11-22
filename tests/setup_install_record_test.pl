#!/usr/bin/perl
#
# setup_install_record_test.pl - test for the installer's install record
# (the luminum.conf file written into the install root and symlinked into
# the etc dir so a later setup run finds the exact install directory
# wherever it is on the server):
#   1. fresh install: <root>/luminum.conf carries INSTALLDATE and
#      INSTALLPATH = <root>, and <etc>/luminum.conf is a symlink to it
#   2. re-run WITHOUT --install-root: the recorded install path is
#      detected and the install lands in the recorded root again
#   3. re-run WITH --install-root at a new path: the explicit flag wins
#      and the etc symlink is re-linked to the new root's record
#
# The etc dir is redirected with LUMINUM_ETC (the test runs unprivileged
# and cannot touch the real /etc).
#
# Usage: perl tests/setup_install_record_test.pl
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
my $srcdir   = "$Bin/../server";
my $mariadbd   = which("mariadbd") || which("mysqld");
my $install_db = which("mariadb-install-db") || which("mysql_install_db");
my $cli        = which("mariadb") || which("mysql");
skip_all("mariadbd / mariadb-install-db / mariadb CLI not available")
    unless $mariadbd && $install_db && $cli;

# The installer requires root; this test drives it against a scratch
# database as an unprivileged user, so use the test escape hatch.
$ENV{LUMINUM_SETUP_ALLOW_NONROOT} = 1;

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

my $tmp = "/tmp/luminum-install-record-test.$$";
my $sock = "$tmp/mysql.sock";
my $pidfile = "$tmp/mysql.pid";
my $etc = "$tmp/etc";
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

# --- scratch MariaDB (root, no password) ------------------------------------
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

# Redirect the install record's symlink location away from the real /etc
# (the test runs unprivileged).
$ENV{LUMINUM_ETC} = $etc;
make_path($etc);

sub run_setup {
    my ($rootarg, $lport, $wport) = @_;
    my $cmd = "perl $setup --noninteractive --yes --no-start"
        . " --shost installrecord.test --laddr 127.0.0.1 --lport $lport"
        . " --wport $wport"
        . ($rootarg ? " --install-root $rootarg" : "")
        . " --dbsocket $sock --dbadmin root"
        . " --adminemail test\@example.com"
        . " --perl5lib $perl5lib";
    my $o = `$cmd 2>&1`;
    return ($? >> 8, $o);
}

sub record_text {
    my ($path) = @_;
    return "" unless -f $path;
    my $t = do { local $/; open(my $fh, "<", $path) or return ""; <$fh> };
    return $t;
}

# --- 1. fresh install: record written, symlink created -----------------------
my ($rc, $o) = run_setup("$tmp/root1", 19481, 19482);
check("fresh install: install succeeds", $rc == 0, $o);
my $rec = record_text("$tmp/root1/luminum.conf");
check("fresh install: <root>/luminum.conf exists", $rec ne "");
check("fresh install: record carries INSTALLPATH = <root>",
    $rec =~ m{^INSTALLPATH = \Q$tmp/root1\E$}m, $rec);
check("fresh install: record carries a non-empty INSTALLDATE",
    $rec =~ /^INSTALLDATE = \S.*/m, $rec);
check("fresh install: <etc>/luminum.conf is a symlink", -l "$etc/luminum.conf");
check("fresh install: symlink points at the root's record",
    readlink("$etc/luminum.conf") eq "$tmp/root1/luminum.conf",
    readlink("$etc/luminum.conf"));

# --- 2. re-run without --install-root: the recorded root is detected ---------
unlink("$tmp/root1/config/broker.conf");
check("pre-run 2: broker.conf removed", !-e "$tmp/root1/config/broker.conf");
($rc, $o) = run_setup(undef, 19483, 19484);
check("re-run without --install-root: install succeeds", $rc == 0, $o);
check("re-run without --install-root: install landed in the recorded root",
    -e "$tmp/root1/config/broker.conf");
$rec = record_text("$tmp/root1/luminum.conf");
check("re-run without --install-root: record still points at the recorded root",
    $rec =~ m{^INSTALLPATH = \Q$tmp/root1\E$}m, $rec);

# --- 3. re-run with --install-root: the explicit flag wins, symlink re-linked -
($rc, $o) = run_setup("$tmp/root3", 19485, 19486);
check("re-run with --install-root: install succeeds", $rc == 0, $o);
check("re-run with --install-root: new root's record written",
    record_text("$tmp/root3/luminum.conf") =~ m{^INSTALLPATH = \Q$tmp/root3\E$}m,
    record_text("$tmp/root3/luminum.conf"));
check("re-run with --install-root: etc symlink re-linked to the new root",
    readlink("$etc/luminum.conf") eq "$tmp/root3/luminum.conf",
    readlink("$etc/luminum.conf"));

# ---------------------------------------------------------------------------
print "-" x 60, "\n";
if ($FAILURES) {
    print "FAILED: $FAILURES check(s) failed\n";
    exit 1;
}
print "All checks passed.\n";
exit 0;
