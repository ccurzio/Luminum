#!/usr/bin/perl
#
# setup_stop_web_test.pl - offline test for the installer's nginx cleanup
# (Luminum::Setup::stop_running_nginx) and the generated stop-web script's
# command-line fallback (Luminum::Setup::install_service).
#
# "nginx -c <this install's conf> -s quit" only reaches a nginx whose pid
# file our config names. A nginx started from a different config (another
# install root, or the distro's) is invisible to it yet still holds the
# web port, so the installer and the stop script must fall back to a
# command-line match (comm "nginx", command line starting with the nginx
# process title or an nginx path). No database needed: a copied sleep
# binary named "nginx" stands in (its comm is "nginx").
#
# Usage: perl tests/setup_stop_web_test.pl
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
# install_service would otherwise write systemd units under /etc, and
# stop_running_nginx would otherwise consult systemctl.
{
    no warnings 'once', 'redefine';
    *Luminum::Setup::systemd_available = sub { 0 };
    }

my $tmp = ($ENV{HOME} || "/tmp") . "/.lum-stop-web-test.$$";
make_path("$tmp/run", "$tmp/bin", "$tmp/log", "$tmp/fakebin")
    or skip_all("cannot create $tmp");
# The fake nginx (a copied sleep) has no SIGQUIT handler, so the kernel
# core-dumps it when the stop scripts QUIT it; the core lands in the
# process's cwd, so stay inside the scratch dir and it is removed with it.
chdir($tmp) or die "chdir $tmp: $!";
my @sleepbins = grep { -x $_ } ("/bin/sleep", "/usr/bin/sleep");
my $sleepbin = $sleepbins[0];
skip_all("no /bin/sleep or /usr/bin/sleep to stand in for nginx") unless $sleepbin;
system("cp", $sleepbin, "$tmp/fakebin/nginx") == 0
    or skip_all("cannot copy $sleepbin");
chmod(0755, "$tmp/fakebin/nginx");
# install_service compile-checks the broker before writing the scripts.
open(my $bfh, ">", "$tmp/broker.pl") or die "open broker.pl: $!";
print $bfh "select(undef, undef, undef, 300);\n";
close($bfh);

unless (Luminum::Setup::install_service({
    root => $tmp, bin => "$tmp/bin", run => "$tmp/run", logdir => "$tmp/log",
    nginxconf => "$tmp/luminum.conf", fpmconf => "$tmp/luminum-fpm.conf",
    fpmbin => "/usr/sbin/php-fpm", perl5lib => "",
    mosqconf => "$tmp/mosquitto.conf", mosqpid => "$tmp/mosquitto.pid",
    mosqlog => "$tmp/mosquitto.log", mosqrundir => "$tmp/mosqrundir",
    mosqlogdir => "$tmp/mosqlogdir", sysmosq => 0,
    })) { die "install_service failed\n"; }
check("stop-web script was generated", -x "$tmp/bin/stop-web");

# --- 1. nginx_pids finds the foreign nginx, rejects the lookalike ----------
my $fp = fork();
defined($fp) or die "fork: $!";
if ($fp == 0) {
    # exec PROGRAM LIST passes argv (PROGRAM, LIST), so the command line
    # is "<path>/nginx 300".
    exec("$tmp/fakebin/nginx", "300");
    exit 1;
    }
push @CHILDREN, $fp;
# comm is "nginx" (the binary's name) but the command line does not look
# like nginx: the match must reject it. "exec -a" sets argv[0] without
# changing the binary, hence the comm.
my $lp = fork();
defined($lp) or die "fork: $!";
if ($lp == 0) {
    exec("/bin/sh", "-c", "exec -a weirdname $tmp/fakebin/nginx 300");
    exit 1;
    }
push @CHILDREN, $lp;
# Wait until the lookalike has exec'd (comm "nginx"): before that the
# rejection checks below would pass trivially.
for (1 .. 40) {
    my $comm = "";
    if (open(my $cfh, "<", "/proc/$lp/comm")) { $comm = <$cfh>; close($cfh); }
    last if defined $comm && $comm =~ /^nginx/;
    select(undef, undef, undef, 0.25);
    }
my $seen = "";
for (1 .. 20) {
    $seen = join(",", Luminum::Setup::nginx_pids());
    last if index(",$seen,", ",$fp,") >= 0;
    select(undef, undef, undef, 0.25);
    }
check("nginx_pids finds the foreign nginx", index(",$seen,", ",$fp,") >= 0, "got: '$seen'");
check("nginx_pids rejects a non-nginx command line", index(",$seen,", ",$lp,") < 0, "got: '$seen'");

# --- 2. stop_running_nginx kills the foreign nginx, spares the lookalike ---
Luminum::Setup::stop_running_nginx("/nonexistent-root", sub { });
# The foreign nginx is our child, so it lingers as a zombie (kill(0) still
# succeeds) until we reap it: poll with a non-blocking waitpid.
my $gone = 0;
for (1 .. 40) {
    if (waitpid($fp, 1) == $fp) { $gone = 1; last; }    # 1 = WNOHANG
    select(undef, undef, undef, 0.25);
    }
check("stop_running_nginx terminated the foreign nginx", $gone, "PID $fp still alive");
check("the lookalike process survived", kill(0, $lp) == 1, "PID $lp was killed");

# --- 3. the generated stop-web stops a foreign nginx by command line -------
my $sp = fork();
defined($sp) or die "fork: $!";
if ($sp == 0) {
    exec("$tmp/fakebin/nginx", "300");
    exit 1;
    }
push @CHILDREN, $sp;
for (1 .. 20) { last if kill(0, $sp); select(undef, undef, undef, 0.25); }
my $out = `"$tmp/bin/stop-web" 2>&1`;
my $rc = $?;
check("stop-web exits 0", $rc == 0, "rc=" . int($rc / 256) . " out: $out");
$gone = 0;
for (1 .. 40) {
    if (waitpid($sp, 1) == $sp) { $gone = 1; last; }
    select(undef, undef, undef, 0.25);
    }
check("stop-web terminated the foreign nginx", $gone, "PID $sp still alive");
check("stop-web named the stopped nginx",
    index($out, "nginx stopped (PID $sp)") >= 0, "got: $out");
check("stop-web reported completion",
    index($out, "Luminum web console stopped") >= 0, "got: $out");
check("the lookalike survived stop-web", kill(0, $lp) == 1, "PID $lp was killed");

# --- 4. stop-web with nothing matching is a clean no-op ---------------------
$out = `"$tmp/bin/stop-web" 2>&1`;
$rc = $?;
check("stop-web exits 0 with nothing running", $rc == 0,
    "rc=" . int($rc / 256) . " out: $out");

# --- 5. a stale php-fpm pid file is removed ---------------------------------
my $dp = fork();
defined($dp) or die "fork: $!";
if ($dp == 0) { exit 0; }
waitpid($dp, 0);
open(my $fh, ">", "$tmp/run/php-fpm.pid") or die "open pid file: $!";
print $fh "$dp\n";
close($fh);
system("$tmp/bin/stop-web");
check("stale php-fpm pid file removed", ! -e "$tmp/run/php-fpm.pid");

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
