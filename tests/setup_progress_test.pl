#!/usr/bin/perl
#
# setup_progress_test.pl - test for the installer's progress callback
# (the option the curses wizard uses for its progress bar / step text).
#
#   1. full in-process run with a progress callback: the callback must
#      fire exactly once per install step (11 steps), in order, with
#      $total == 11 and the step text the wizard displays
#   2. early-failure run (bad db socket): the callback fires for step 1
#      ("Checking dependencies") and the run fails
#   3. run without a progress option: unaffected (no callback, no crash)
#
# Usage: perl tests/setup_progress_test.pl
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
use lib "$Bin/../server/lib";
require Luminum::Setup;

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

my $tmp = "/tmp/luminum-progress-test.$$";
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

# The step texts the wizard displays, in install order.
my @expected = (
    "Checking dependencies",
    "Synchronizing server files",
    "Setting up database",
    "Generating server certificate",
    "Provisioning MQTT broker",
    "Generating server identity",
    "Writing configuration files",
    "Seeding database configuration",
    "Writing web console configuration",
    "Installing service management",
    "Starting and verifying services",
    );

sub stepdump {
    my (@steps) = @_;
    return join("; ", map { "$_->[0]/$_->[1]:$_->[2]" } @steps);
    }

# The installer's child processes (openssl, cp, ...) write to the
# inherited STDOUT/STDERR even when quiet is set; redirect both for the
# duration of each in-process run so the test output stays readable.
#
sub run_quiet {
    my ($log, @args) = @_;
    my $saveout;
    my $saveerr;
    open($saveout, ">&", \*STDOUT) or die "dup STDOUT: $!";
    open($saveerr, ">&", \*STDERR) or die "dup STDERR: $!";
    open(STDOUT, ">", $log) or die "open $log: $!";
    open(STDERR, ">>", $log) or die "open $log: $!";
    my @r = eval { Luminum::Setup::run(@args) };
    my $err = $@;
    close(STDOUT);
    close(STDERR);
    open(STDOUT, ">&", $saveout) or die "restore STDOUT: $!";
    open(STDERR, ">&", $saveerr) or die "restore STDERR: $!";
    close($saveout);
    close($saveerr);
    die $err if $err;
    # run() returns (summary, rc) on success and (rc) on failure; in
    # scalar context the caller wants rc (the last element) - "return
    # @r" would yield the element count instead.
    return wantarray ? @r : $r[-1];
    }

# --- 1. full run with a progress callback ------------------------------------
my @steps;
my ($summary, $rc) = run_quiet("$tmp/run1.out",
    install_root => "$tmp/root1",
    shost        => "progress.test", laddr => "127.0.0.1", lport => 19475,
    waddr        => "127.0.0.1", wport => 19476,
    dbsocket     => $sock, dbadmin => "root",
    srcdir       => $srcdir,
    start        => 0,
    quiet        => 1,
    perl5lib     => $perl5lib,
    progress     => sub { push @steps, [ @_ ]; },
    );
check("full run: install succeeds", $rc == 0, "rc=$rc");
check("full run: 11 progress calls", scalar(@steps) == 11,
    "got " . scalar(@steps) . ": " . stepdump(@steps));
my $seqok = 1;
my $textok = 1;
for my $i (0 .. $#steps) {
    my ($n, $total, $text) = @{$steps[$i]};
    $seqok  = 0 unless $n == $i + 1 && $total == 11;
    $textok = 0 unless defined $text && $text eq $expected[$i];
    }
check("full run: step numbers sequential 1..11, total 11", $seqok,
    stepdump(@steps));
check("full run: step texts match the wizard's step list", $textok,
    stepdump(@steps));

# --- 2. early failure (bad db socket) ----------------------------------------
my @steps2;
my $rc2 = run_quiet("$tmp/run2.out",
    install_root => "$tmp/root2",
    shost        => "progress.test", laddr => "127.0.0.1", lport => 19477,
    dbsocket     => "/tmp/luminum-progress-no-such.sock", dbadmin => "root",
    srcdir       => $srcdir,
    quiet        => 1,
    progress     => sub { push @steps2, [ @_ ]; },
    );
check("early failure: run fails", $rc2 != 0, "rc=$rc2");
check("early failure: exactly one progress call", scalar(@steps2) == 1,
    "got " . scalar(@steps2) . ": " . stepdump(@steps2));
check("early failure: step 1 is Checking dependencies",
    @steps2 == 1 && $steps2[0][0] == 1 && $steps2[0][1] == 11
        && $steps2[0][2] eq "Checking dependencies",
    stepdump(@steps2));
check("early failure: install tree not created", !-d "$tmp/root2");

# --- 3. run without a progress option ----------------------------------------
my $rc3 = run_quiet("$tmp/run3.out",
    install_root => "$tmp/root3",
    shost        => "progress.test", laddr => "127.0.0.1", lport => 19478,
    waddr        => "127.0.0.1", wport => 19479,
    dbsocket     => $sock, dbadmin => "root",
    srcdir       => $srcdir,
    start        => 0,
    quiet        => 1,
    perl5lib     => $perl5lib,
    );
check("no progress option: install succeeds", $rc3 == 0, "rc=$rc3");

# ---------------------------------------------------------------------------
print "-" x 60, "\n";
if ($FAILURES) {
    print "FAILED: $FAILURES check(s) failed\n";
    exit 1;
}
print "All checks passed.\n";
exit 0;
