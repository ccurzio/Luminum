#!/usr/bin/perl
#
# setup_orphan_broker_test.pl - offline test for the installer's
# orphan-broker cleanup (Luminum::Setup::stop_running_broker) and the
# port-holder diagnostic (Luminum::Setup::port_holder).
#
# A broker left over from a different install root is invisible to this
# install's stop script (its pid file and command-line fallback both cover
# only this install's broker.pl) yet still holds the listener port, so
# every re-run died at the pre-start probe with "port already in use".
# These tests stand in for such an orphan (no database needed):
#   1. a "perl <tmp>/broker.pl" process with no pid file anywhere is found
#      by broker_pids() and killed by stop_running_broker()
#   2. a perl process that merely mentions broker.pl as an argument is NOT
#      matched and survives
#   3. port_holder() names the PID of a process listening on a port
#
# Usage: perl tests/setup_orphan_broker_test.pl
# Exit code: 0 if all checks pass, 1 otherwise.

use strict;
use warnings;
use FindBin qw($Bin);
use File::Path qw(make_path remove_tree);
use IO::Socket::INET;

my $FAILURES = 0;
my @CHILDREN;
my $STATUS;
# wait() in an END block clobbers the exit status with its return value
# (-1 -> 255) on perl 5.40, so re-set it explicitly after reaping.
sub done {
    my ($rc) = @_;
    $STATUS = $rc;
    exit $rc;
    }
END {
    if (@CHILDREN) {
        kill("TERM", @CHILDREN);
        wait while wait() != -1;
        exit $STATUS if defined $STATUS;
    }
    }
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

skip_all("pgrep not available") unless which("pgrep");
skip_all("/proc not available (Linux only)") unless -d "/proc";

my $lib = "$Bin/../server/lib";
eval { require "$lib/Luminum/Setup.pm"; Luminum::Setup->import; 1 }
    or skip_all("cannot load Luminum::Setup ($@)");

# --- a listener on a free port, for port_holder ------------------------------
sub free_port {
    for (1 .. 50) {
        my $port = 20000 + int(rand(40000));
        my $s = IO::Socket::INET->new(LocalAddr => "127.0.0.1:$port", Listen => 1);
        if ($s) { close($s); return $port; }
    }
    return undef;
    }
my $lport = free_port();
skip_all("could not find a free port") unless $lport;
my $lp = fork();
defined($lp) or die "fork: $!";
if ($lp == 0) {
    # Perl sets close-on-exec on its filehandles, so the child must stay
    # in Perl to keep the listening socket open.
    my $s = IO::Socket::INET->new(LocalAddr => "127.0.0.1:$lport",
        Listen => 5, Reuse => 1) or exit 1;
    select(undef, undef, undef, 300);
    exit 1;
    }
push @CHILDREN, $lp;
my $holder = "";
for (1 .. 20) {
    $holder = Luminum::Setup::port_holder($lport);
    last if $holder ne "";
    select(undef, undef, undef, 0.25);
    }
check("port_holder names the listener's PID", $holder eq "$lp", "got: '$holder'");

# --- the orphan broker: "perl <tmp>/broker.pl", no pid file anywhere --------
my $tmp = "/tmp/luminum-orphan-test.$$";
make_path($tmp) or skip_all("cannot create $tmp");
for my $f (["broker.pl", "select(undef, undef, undef, 300);\n"],
        ["helper.pl", "select(undef, undef, undef, 300);\n"]) {
    open(my $fh, ">", "$tmp/$f->[0]") or die "open $f->[0]: $!";
    print $fh $f->[1];
    close($fh);
    }
my $bp = fork();
defined($bp) or die "fork: $!";
if ($bp == 0) {
    exec($^X, "$tmp/broker.pl");
    exit 1;
    }
push @CHILDREN, $bp;
# A perl process that merely mentions broker.pl as an argument: the
# command-line match must reject it (interpreter + exactly one argument,
# the script).
my $np = fork();
defined($np) or die "fork: $!";
if ($np == 0) {
    exec($^X, "$tmp/helper.pl", "broker.pl");
    exit 1;
    }
push @CHILDREN, $np;

my $seen = "";
for (1 .. 20) {
    $seen = join(",", Luminum::Setup::broker_pids());
    last if index(",$seen,", ",$bp,") >= 0;
    select(undef, undef, undef, 0.25);
    }
check("broker_pids finds the orphan (no pid file)", index(",$seen,", ",$bp,") >= 0, "got: '$seen'");
check("broker_pids rejects a process that only mentions broker.pl",
    index(",$seen,", ",$np,") < 0, "got: '$seen'");
check("proc_cmdline reports the orphan's command line",
    Luminum::Setup::proc_cmdline($bp) eq "$^X $tmp/broker.pl",
    "got: '" . Luminum::Setup::proc_cmdline($bp) . "'");

# --- stop_running_broker kills the orphan, spares the lookalike -------------
Luminum::Setup::stop_running_broker("/nonexistent-root", sub { });
# The orphan is our child, so it lingers as a zombie (invisible to
# kill(0, ...)) until we reap it: poll with a non-blocking waitpid.
my $gone = 0;
for (1 .. 40) {
    if (waitpid($bp, 1) == $bp) { $gone = 1; last; }    # 1 = WNOHANG
    select(undef, undef, undef, 0.25);
    }
check("stop_running_broker terminated the orphan", $gone, "PID $bp still alive");
check("the lookalike process survived", kill(0, $np) == 1, "PID $np was killed");

# --- cleanup ------------------------------------------------------------------
kill("TERM", @CHILDREN) if @CHILDREN;
wait while wait() != -1;
remove_tree($tmp);

print "------------------------------------------------------------\n";
if ($FAILURES > 0) {
    print "FAILED: $FAILURES check(s) failed\n";
    done(1);
    }
print "All checks passed.\n";
done(0);
