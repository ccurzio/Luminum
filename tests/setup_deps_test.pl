#!/usr/bin/perl
#
# setup_deps_test.pl - offline test for the installer's dependency gate:
#   1. non-interactive run with a PATH lacking the required binaries:
#      must fail with "missing dependencies" and must NOT write the
#      install tree (the gate runs before any file is written)
#   2. in-process run with a deps_offer callback that declines (cancel):
#      the callback is invoked, the install fails, nothing is written
#   3. in-process run with a deps_offer callback that accepts (install):
#      the package-manager path is attempted; when the packages cannot
#      actually be installed (offline host) the install fails cleanly
#      and nothing is written
#
# No database is needed: the dependency gate runs before the database
# connection.
#
# Usage: perl tests/setup_deps_test.pl
# Exit code: 0 if all checks pass, 1 otherwise.

use strict;
use warnings;
use FindBin qw($Bin);
use File::Path qw(remove_tree);
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

my $setup  = "$Bin/../server/setup.pl";
my $srcdir = "$Bin/../server";
die "setup.pl not found at $setup\n" unless -f $setup;

my $tmp = "/tmp/luminum-deps-test.$$";
remove_tree($tmp) if -d $tmp;
mkdir($tmp) or die "mkdir $tmp: $!\n";
END {
    remove_tree($tmp) if defined $tmp && -d $tmp;
}

# The offer is only made when setup runs as root (only root can install
# packages); on a non-root run the gate fails directly.
my $isroot = ($> == 0);

# --- 1. non-interactive, stripped PATH --------------------------------------
my $root1 = "$tmp/root1";
my $cmd = $^X . " $setup --noninteractive --yes --no-start"
    . " --shost deps.test --laddr 127.0.0.1 --lport 19470"
    . " --install-root $root1 --dbsocket /tmp/luminum-deps-no-such.sock"
    . " --dbadmin root --srcdir $srcdir";
my $out = `env PATH=/nonexistent $cmd 2>&1`;
my $rc = $? >> 8;
check("stripped PATH: install fails", $rc != 0, "rc=$rc");
check("stripped PATH: failure names missing dependencies",
    $out =~ /missing dependencies:/, $out);
check("stripped PATH: failure states no files were written",
    $out =~ /no files were written/, $out);
check("stripped PATH: install tree not created", !-d $root1);

# --- 2. in-process, offer declined (cancel) ----------------------------------
my $offered2 = 0;
my $root2 = "$tmp/root2";
my $rc2;
{
    local $ENV{PATH} = "/nonexistent";
    $rc2 = Luminum::Setup::run(
        install_root => $root2,
        shost        => "deps.test", laddr => "127.0.0.1", lport => 19471,
        dbsocket     => "/tmp/luminum-deps-no-such.sock", dbadmin => "root",
        srcdir       => $srcdir,
        deps_offer   => sub { $offered2 = 1; return 0; },
        );
}
check("offer declined: callback invoked (root only)",
    $isroot ? $offered2 == 1 : $offered2 == 0,
    "offered=$offered2 isroot=$isroot");
check("offer declined: install fails", $rc2 != 0, "rc=$rc2");
check("offer declined: install tree not created", !-d $root2);

# --- 3. in-process, offer accepted (install) ---------------------------------
my $offered3 = 0;
my $root3 = "$tmp/root3";
my $rc3;
my $log3 = "";
{
    local $ENV{PATH} = "/usr/bin";
    my $saveout;
    open($saveout, ">&", \*STDOUT) or die "dup STDOUT: $!";
    open(STDOUT, ">", "$tmp/deps3.log") or die "open deps3.log: $!";
    $rc3 = Luminum::Setup::run(
        install_root => $root3,
        shost        => "deps.test", laddr => "127.0.0.1", lport => 19472,
        dbsocket     => "/tmp/luminum-deps-no-such.sock", dbadmin => "root",
        srcdir       => $srcdir,
        deps_offer   => sub { $offered3 = 1; return 1; },
        );
    close(STDOUT);
    open(STDOUT, ">&", $saveout) or die "restore STDOUT: $!";
    close($saveout);
    if (open(my $lfh, "<", "$tmp/deps3.log")) {
        $log3 = do { local $/; <$lfh> };
        close($lfh);
    }
}
check("offer accepted: callback invoked (root only)",
    $isroot ? $offered3 == 1 : $offered3 == 0,
    "offered=$offered3 isroot=$isroot");
check("offer accepted: package installation was attempted (root only)",
    $isroot
        ? ($log3 =~ /installing via |no supported package manager|no system package/)
        : 1,
    $log3);
# Offline host: the install cannot succeed, so the run must fail cleanly.
# (On a networked host the packages would install and the run would then
# fail at the database connection - still a clean failure, still no tree.)
check("offer accepted: run fails cleanly when packages cannot be installed",
    $rc3 != 0, "rc=$rc3");
check("offer accepted: install tree not created", !-d $root3);

# ---------------------------------------------------------------------------
print "-" x 60, "\n";
if ($FAILURES) {
    print "FAILED: $FAILURES check(s) failed\n";
    exit 1;
}
print "All checks passed.\n";
exit 0;
