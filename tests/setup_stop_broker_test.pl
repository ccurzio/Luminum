#!/usr/bin/perl
#
# setup_stop_broker_test.pl - offline test for the generated broker
# start/stop scripts (Luminum::Setup::install_service).
#
# The stop script must reach a broker whether or not its pid file exists:
# a broker started without the start script (manually, or by the systemd
# unit) has no pid file, so the stop script falls back to a command-line
# match (interpreter perl, exactly one argument, this install's
# broker.pl). The start script must write the pid file, refuse to start a
# second broker over a running one, and fail loudly when the pid file
# cannot be written. No database needed: a dummy broker.pl stands in.
#
# Usage: perl tests/setup_stop_broker_test.pl
# Exit code: 0 if all checks pass, 1 otherwise.

use strict;
use warnings;
use FindBin qw($Bin);
use File::Path qw(make_path remove_tree);

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
# install_service would otherwise write systemd units under /etc.
{
    no warnings 'once', 'redefine';
    *Luminum::Setup::systemd_available = sub { 0 };
    }

# A process is gone when /proc/<pid> is gone or its cmdline is empty
# (an unreaped zombie). Brokers started through the scripts are not our
# children, so waitpid cannot be used on them.
sub proc_gone {
    my ($pid) = @_;
    return 1 unless -d "/proc/$pid";
    open(my $fh, "<", "/proc/$pid/cmdline") or return 1;
    my $raw;
    { local $/; $raw = <$fh>; }
    close($fh);
    return (defined $raw && length $raw) ? 0 : 1;
    }
sub wait_gone {
    my ($pid, $tries) = @_;
    for (1 .. ($tries || 40)) {
        return 1 if proc_gone($pid);
        select(undef, undef, undef, 0.25);
    }
    return proc_gone($pid);
    }
sub read_pidfile {
    my ($path) = @_;
    return "" unless open(my $fh, "<", $path);
    my $pid = <$fh>;
    close($fh);
    chomp($pid) if defined $pid;
    return $pid || "";
    }

# $HOME, not /tmp: /tmp is noexec in some containers and the generated
# start/stop scripts must be executable.
my $tmp = ($ENV{HOME} || "/tmp") . "/.lum-stop-broker-test.$$";
make_path("$tmp/run", "$tmp/bin", "$tmp/log") or skip_all("cannot create $tmp");
for my $f (["broker.pl", "select(undef, undef, undef, 300);\n"],
        ["helper.pl", "select(undef, undef, undef, 300);\n"]) {
    open(my $fh, ">", "$tmp/$f->[0]") or die "open $f->[0]: $!";
    print $fh $f->[1];
    close($fh);
    }

unless (Luminum::Setup::install_service({
    root => $tmp, bin => "$tmp/bin", run => "$tmp/run", logdir => "$tmp/log",
    nginxconf => "$tmp/luminum.conf", fpmconf => "$tmp/luminum-fpm.conf",
    fpmbin => "/usr/sbin/php-fpm", perl5lib => "",
    mosqconf => "$tmp/mosquitto.conf", mosqpid => "$tmp/mosquitto.pid",
    mosqlog => "$tmp/mosquitto.log", mosqrundir => "$tmp/mosqrundir",
    mosqlogdir => "$tmp/mosqlogdir", sysmosq => 0,
    })) { die "install_service failed\n"; }
check("start/stop scripts were generated",
    -x "$tmp/bin/start-broker" && -x "$tmp/bin/stop-broker");

# --- 1. start-broker writes the pid file -------------------------------------
my $rc = system("$tmp/bin/start-broker");
check("start-broker exits 0", $rc == 0, "rc=" . int($rc / 256));
my $pid = read_pidfile("$tmp/run/broker.pid");
check("pid file written with a live PID",
    $pid =~ /^\d+$/ && kill(0, $pid) == 1, "pid: '$pid'");

# --- 2. a second start is refused, the first broker is untouched -------------
$rc = system("$tmp/bin/start-broker");
check("second start-broker exits 0 (already running)", $rc == 0,
    "rc=" . int($rc / 256));
check("pid file still points at the first broker",
    read_pidfile("$tmp/run/broker.pid") eq $pid,
    "got: '" . read_pidfile("$tmp/run/broker.pid") . "'");
# List form: a string form would run through "sh -c", whose command line
# contains the pattern and so matches pgrep -f itself.
my @brokers = `pgrep -f "$tmp/broker\.pl"`;
chomp(@brokers);
check("only one broker process is running", scalar(@brokers) == 1,
    "got: " . join(",", @brokers));

# --- 3. stop-broker stops it via the pid file ---------------------------------
$rc = system("$tmp/bin/stop-broker");
check("stop-broker exits 0", $rc == 0, "rc=" . int($rc / 256));
check("broker stopped", wait_gone($pid), "PID $pid still alive");
check("pid file removed", ! -e "$tmp/run/broker.pid");

# --- 4. an orphan (no pid file) is stopped by the command-line fallback ------
my $op = fork();
defined($op) or die "fork: $!";
if ($op == 0) {
    exec($^X, "$tmp/broker.pl");
    exit 1;
    }
push @CHILDREN, $op;
for (1 .. 20) { last if kill(0, $op); select(undef, undef, undef, 0.25); }
check("orphan is running with no pid file",
    kill(0, $op) == 1 && ! -e "$tmp/run/broker.pid");
$rc = system("$tmp/bin/stop-broker");
check("stop-broker exits 0 (orphan)", $rc == 0, "rc=" . int($rc / 256));
# The orphan is our child, so it lingers as a zombie (kill(0) still
# succeeds) until we reap it: poll with a non-blocking waitpid.
my $gone = 0;
for (1 .. 40) {
    if (waitpid($op, 1) == $op) { $gone = 1; last; }    # 1 = WNOHANG
    select(undef, undef, undef, 0.25);
    }
check("orphan stopped by the command-line fallback", $gone, "PID $op still alive");

# --- 5. a perl process that only mentions broker.pl survives ------------------
my $np = fork();
defined($np) or die "fork: $!";
if ($np == 0) {
    exec($^X, "$tmp/helper.pl", "broker.pl");
    exit 1;
    }
push @CHILDREN, $np;
for (1 .. 20) { last if kill(0, $np); select(undef, undef, undef, 0.25); }
$rc = system("$tmp/bin/stop-broker");
check("lookalike process survived", kill(0, $np) == 1, "PID $np was killed");

# --- 6. a stale pid file is reported and removed ------------------------------
my $sp = fork();
defined($sp) or die "fork: $!";
if ($sp == 0) { exit 0; }
waitpid($sp, 0);
open(my $fh, ">", "$tmp/run/broker.pid") or die "open pid file: $!";
print $fh "$sp\n";
close($fh);
$rc = system("$tmp/bin/stop-broker");
check("stop-broker exits 0 (stale pid file)", $rc == 0, "rc=" . int($rc / 256));
check("stale pid file removed", ! -e "$tmp/run/broker.pid");

# --- 7. start-broker fails loudly when the pid file cannot be written --------
if ($> != 0) {
    chmod(0555, "$tmp/run");
    my $err = `"$tmp/bin/start-broker" 2>&1`;
    my $sstart = $?;
    chmod(0755, "$tmp/run");
    check("start-broker fails when the pid file cannot be written",
        int($sstart / 256) != 0, "rc=" . int($sstart / 256));
    check("failure names the pid file", index($err, "broker.pid") >= 0,
        "got: $err");
    # The nohup'd broker is still up with no pid file; the fallback stops it.
    $rc = system("$tmp/bin/stop-broker");
    check("stray broker from the failed start was stopped", $rc == 0,
        "rc=" . int($rc / 256));
    select(undef, undef, undef, 1);
    my @left = `pgrep -f "$tmp/broker\.pl"`;
    chomp(@left);
    check("no broker process left", scalar(@left) == 0,
        "got: " . join(",", @left));
    }
else {
    print "skip - the pid-write failure case needs a non-root user\n";
    }

# --- cleanup -------------------------------------------------------------------
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
