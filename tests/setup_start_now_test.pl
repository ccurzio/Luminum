#!/usr/bin/perl
#
# setup_start_now_test.pl - offline test for start_now's web-port guard.
#
# stop-web only signals the nginx started from this install's config, so a
# web port held by another service (or an nginx from a different install
# root) survives it and nginx dies with five "Address already in use"
# bind failures. start_now must name the holder up front instead. No
# database needed: fake service scripts stand in for the real ones.
#
# Usage: perl tests/setup_start_now_test.pl
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

skip_all("/proc not available (Linux only)") unless -d "/proc";

my $lib = "$Bin/../server/lib";
eval { require "$lib/Luminum/Setup.pm"; Luminum::Setup->import; 1 }
    or skip_all("cannot load Luminum::Setup ($@)");

sub free_port {
    for (1 .. 50) {
        my $port = 20000 + int(rand(40000));
        my $s = IO::Socket::INET->new(LocalAddr => "127.0.0.1:$port", Listen => 1);
        if ($s) { close($s); return $port; }
    }
    return undef;
    }
my ($lport, $mport, $wport) = (free_port(), free_port(), free_port());
skip_all("could not find free ports") unless $lport && $mport && $wport;

# A holder on the web port: what stop-web cannot reach. The child must
# stay in Perl because perl sets close-on-exec on its filehandles.
my $hp = fork();
defined($hp) or die "fork: $!";
if ($hp == 0) {
    my $s = IO::Socket::INET->new(LocalAddr => "127.0.0.1:$wport",
        Listen => 5, Reuse => 1) or exit 1;
    select(undef, undef, undef, 300);
    exit 1;
    }
push @CHILDREN, $hp;
# A fake MQTT listener so start_now's mosquitto probe passes.
my $mp = fork();
defined($mp) or die "fork: $!";
if ($mp == 0) {
    my $s = IO::Socket::INET->new(LocalAddr => "127.0.0.1:$mport",
        Listen => 5, Reuse => 1) or exit 1;
    select(undef, undef, undef, 300);
    exit 1;
    }
push @CHILDREN, $mp;
for (1 .. 20) {
    my $s = IO::Socket::INET->new(PeerAddr => "127.0.0.1:$wport", Timeout => 1);
    last if $s;
    select(undef, undef, undef, 0.25);
    }

# Fake service scripts: start-web records that it ran.
my $tmp = ($ENV{HOME} || "/tmp") . "/.lum-start-now-test.$$";
make_path("$tmp/bin", "$tmp/run", "$tmp/log") or skip_all("cannot create $tmp");
for my $s (["start-mosquitto", "#!/bin/sh\nexit 0\n"],
        ["start-broker", "#!/bin/sh\nsleep 30 &\necho \$! > \"$tmp/run/broker.pid\"\nexit 0\n"],
        ["start-web", "#!/bin/sh\ntouch \"$tmp/web-started\"\nexit 0\n"]) {
    open(my $fh, ">", "$tmp/bin/$s->[0]") or die "open $s->[0]: $!";
    print $fh $s->[1];
    close($fh);
    chmod(0700, "$tmp/bin/$s->[0]");
    }

sub run_start_now {
    my $warned = "";
    {
        local $SIG{__WARN__} = sub { $warned .= $_[0]; };
        my $rc = Luminum::Setup::start_now({
            bin => "$tmp/bin", run => "$tmp/run", logdir => "$tmp/log",
            laddr => "127.0.0.1", lport => $lport,
            maddr => "127.0.0.1", mport => $mport, wport => $wport,
            });
        return ($rc, $warned);
        }
    }
# The fake broker's "sleep 30" is a child of the fake start script, not of
# us: kill it through the pid file the fake start script wrote.
sub kill_fake_broker {
    my $bp = "";
    if (open(my $fh, "<", "$tmp/run/broker.pid")) { $bp = <$fh>; close($fh); }
    chomp($bp) if defined $bp;
    kill("TERM", $bp) if $bp =~ /^\d+$/;
    }

# --- 1. the web port is held: start_now aborts and names the holder --------
my ($rc, $warned) = run_start_now();
check("start_now aborts when the web port is held", $rc == 1, "rc=$rc");
check("warning names the web port",
    index($warned, "port $wport is already in use") >= 0, "got: $warned");
check("warning names the holder's PID",
    index($warned, "held by PID $hp") >= 0, "got: $warned");
check("start-web was not run", ! -e "$tmp/web-started");
kill_fake_broker();

# --- 2. the port is free: start_now completes and start-web runs -----------
kill("TERM", $hp);
waitpid($hp, 0);
($rc, $warned) = run_start_now();
check("start_now completes once the web port is free", $rc == 0,
    "rc=$rc warned: $warned");
check("start-web ran", -e "$tmp/web-started");
kill_fake_broker();

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
