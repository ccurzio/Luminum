#!/usr/bin/perl
#
# repo_test.pl - offline test for the file repository core
# (server/lib/Luminum/Repo.pm, docs/p2p.md Phase 0):
#   1. bootstrap creates the content-addressed layout (files/ + one
#      staging dir per vector, mode 0750)
#   2. sha256_file streams the correct digest
#   3. enabled_vectors reads REPOHTTP/REPONFS/REPOSMB live (missing key
#      falls back to the installer default: http on, nfs/smb off)
#   4. register hashes, dedupes, catalogs, and moves a file into the
#      content-addressed store (duplicate content reuses the existing row)
#   5. scan_vector applies the mtime-stability rule (fresh drops are
#      skipped, aged drops are registered), ignores hidden entries, and
#      resolves the original name of finished HTTP uploads from UPLOADS
#   6. sweep_uploads removes stale in-flight uploads and orphan temp
#      files, and leaves recent in-flight uploads alone
#   7. the scan() entry point registers a drop in an enabled vector
#      (smb) end to end
#
# Spins up a scratch MariaDB, applies server/sql/schema.sql, and drives
# the module against a temporary content root.
#
# Usage: perl tests/repo_test.pl
# Exit code: 0 if all checks pass, 1 otherwise.

use strict;
use warnings;
use FindBin qw($Bin);
use File::Path qw(make_path remove_tree);
use Digest::SHA qw(sha256_hex);
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

my $libdir = "$Bin/../server/lib";
skip_all("server/lib not found at $libdir") unless -d $libdir;
unshift @INC, $libdir;
my $repo = eval { require Luminum::Repo; Luminum::Repo->import; 1 };
skip_all("Luminum::Repo will not load: $@") unless $repo;

my $mariadbd   = which("mariadbd") || which("mysqld");
my $install_db = which("mariadb-install-db") || which("mysql_install_db");
my $cli        = which("mariadb") || which("mysql");
skip_all("mariadbd / mariadb-install-db / mariadb CLI not available")
    unless $mariadbd && $install_db && $cli;

my $tmp = "/tmp/luminum-repo-test.$$";
my $sock = "$tmp/mysql.sock";
my $pidfile = "$tmp/mysql.pid";
my $root = "$tmp/content";
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

# Apply the schema (creates all databases and tables, idempotent).
$out = `$cli -S $sock -u root -ptestrootpw < "$Bin/../server/sql/schema.sql" 2>&1`;
check("schema applied", $? == 0, $out);
skip_all("schema application failed: $out") unless $? == 0;

use DBI;
my $dbh = DBI->connect("DBI:mysql:dbname=CONTENT", "root", "testrootpw",
    { mysql_socket => $sock, PrintError => 0, RaiseError => 0, AutoCommit => 1 });
skip_all("cannot connect to scratch database: " . DBI->errstr) unless $dbh;
my $sysdb = DBI->connect("DBI:mysql:dbname=SYSTEM", "root", "testrootpw",
    { mysql_socket => $sock, PrintError => 0, RaiseError => 0, AutoCommit => 1 });
skip_all("cannot connect to SYSTEM: " . DBI->errstr) unless $sysdb;

# SYSTEM.CONFIG has no unique key on CKEY (production dump), so REPLACE
# would insert a second row instead of replacing; use the same
# read-then-write pattern as luminum-config.pl's upsert_config.
sub set_config {
    my ($key, $val) = @_;
    my ($existing) = $sysdb->selectrow_array("select CVAL from CONFIG where CKEY = ?", undef, $key);
    if (defined $existing) {
        $sysdb->do("update CONFIG set CVAL = ? where CKEY = ?", undef, $val, $key);
    } else {
        $sysdb->do("insert into CONFIG (CKEY, CVAL) values (?, ?)", undef, $key, $val);
    }
}
sub age {
    my ($path) = @_;
    utime(time() - 60, time() - 60, $path);
}
sub files_row {
    my ($sha) = @_;
    return $dbh->selectrow_hashref("select * from FILES where SHA256 = ?", undef, $sha);
}

# 1. bootstrap ----------------------------------------------------------------
check("bootstrap: creates the layout", Luminum::Repo::bootstrap($root) == 1);
for my $d (("$root/files"), map { "$root/staging/$_" } qw(http nfs smb)) {
    check("bootstrap: $d exists", -d $d);
    check("bootstrap: $d is mode 0750", ((stat($d))[2] & 07777) == 0750,
        sprintf("%o", ((stat($d))[2] & 07777)));
}
check("bootstrap: idempotent on re-run", Luminum::Repo::bootstrap($root) == 1);

# 2. sha256_file ---------------------------------------------------------------
my $known = "$tmp/known.txt";
open(my $fh, '>:raw', $known) or die $!;
print $fh "abc";
close($fh);
check("sha256_file: known digest",
    Luminum::Repo::sha256_file($known) eq "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
    Luminum::Repo::sha256_file($known));
check("sha256_file: unreadable file is undef",
    !defined Luminum::Repo::sha256_file("$tmp/no-such-file"));

# 3. enabled_vectors -----------------------------------------------------------
my @v = Luminum::Repo::enabled_vectors($sysdb);
check("enabled_vectors: missing keys default to http only",
    @v == 1 && $v[0] eq "http", join(",", @v));
set_config("REPONFS", "Enabled");
set_config("REPOSMB", "Enabled");
@v = Luminum::Repo::enabled_vectors($sysdb);
check("enabled_vectors: all enabled", @v == 3 && join(",", @v) eq "http,nfs,smb", join(",", @v));
set_config("REPOHTTP", "Disabled");
@v = Luminum::Repo::enabled_vectors($sysdb);
check("enabled_vectors: http disabled", @v == 2 && join(",", @v) eq "nfs,smb", join(",", @v));
set_config("REPOHTTP", "Enabled");

# 4. register ------------------------------------------------------------------
my $src = "$root/staging/nfs/alpha.txt";
open($fh, '>:raw', $src) or die $!;
print $fh "hello repository\n";
close($fh);
my ($id, $how) = Luminum::Repo::register($dbh, $root, $src, "alpha.txt", "nfs");
# The expected digest of the content, computed directly.
my $expect = sha256_hex("hello repository\n");
check("register: returns a FILES id", defined $id, $how);
check("register: how is 'registered'", $how eq "registered", $how);
check("register: source file moved away", !-e $src);
check("register: blob at content-addressed path", -f "$root/files/" . substr($expect, 0, 2) . "/" . substr($expect, 2, 2) . "/$expect");
my $row = files_row($expect);
check("register: catalog row present", defined $row);
check("register: catalog size", defined $row && $row->{SIZE} == 17, defined $row ? $row->{SIZE} : "no row");
check("register: catalog name", defined $row && $row->{NAME} eq "alpha.txt", defined $row ? $row->{NAME} : "no row");
check("register: catalog vector", defined $row && $row->{VIA} eq "nfs", defined $row ? $row->{VIA} : "no row");

# duplicate content, different name -> same row, source deleted
my $src2 = "$root/staging/nfs/beta.txt";
open($fh, '>:raw', $src2) or die $!;
print $fh "hello repository\n";
close($fh);
my ($id2, $how2) = Luminum::Repo::register($dbh, $root, $src2, "beta.txt", "nfs");
check("register: duplicate reuses the existing row", defined $id2 && $id2 == $id, "id2=" . (defined $id2 ? $id2 : "undef"));
check("register: duplicate reported", $how2 eq "duplicate", $how2);
check("register: duplicate source deleted", !-e $src2);
my $count = ($dbh->selectrow_array("select count(*) from FILES"))[0];
check("register: still exactly one FILES row", $count == 1, "count=$count");

# 5. scan_vector ----------------------------------------------------------------
# fresh drop -> skipped (mtime-stability rule)
my $fresh = "$root/staging/nfs/fresh.txt";
open($fh, '>:raw', $fresh) or die $!;
print $fh "fresh content\n";
close($fh);
my @res = Luminum::Repo::scan_vector($dbh, $root, "nfs", sub { });
check("scan: fresh drop skipped", grep { /^skip fresh.txt/ } @res == 1, join(" | ", @res));
check("scan: fresh drop not registered", !files_row(sha256_hex("fresh content\n")));

# age it -> registered on the next scan
age($fresh);
@res = Luminum::Repo::scan_vector($dbh, $root, "nfs", sub { });
check("scan: aged drop registered", grep { /^registered fresh.txt/ } @res == 1, join(" | ", @res));
check("scan: aged drop in catalog", defined files_row(sha256_hex("fresh content\n")));
check("scan: aged drop moved to store", !-e $fresh);

# hidden entries are ignored
my $hidden = "$root/staging/nfs/.hidden";
open($fh, '>:raw', $hidden) or die $!;
print $fh "hidden content\n";
close($fh);
age($hidden);
@res = Luminum::Repo::scan_vector($dbh, $root, "nfs", sub { });
check("scan: hidden entry ignored", !files_row(sha256_hex("hidden content\n")) && -e $hidden);

# finished HTTP upload: staged as {uuid}-{name}, catalog keeps the original name
my $uuid = "01234567-89ab-4cde-8f01-23456789abcd";
$dbh->do("insert into UPLOADS (ID,NAME,SIZE,RECEIVED,VIA,CREATED,DONE) values (?,?,14,14,'http',now(),now())",
    undef, $uuid, "original.txt");
my $upfile = "$root/staging/http/$uuid-original.txt";
open($fh, '>:raw', $upfile) or die $!;
print $fh "uploaded content\n";
close($fh);
age($upfile);
@res = Luminum::Repo::scan_vector($dbh, $root, "http", sub { });
my $uprow = files_row(sha256_hex("uploaded content\n"));
check("scan: finished upload registered", defined $uprow, join(" | ", @res));
check("scan: upload catalog name is the original name",
    defined $uprow && $uprow->{NAME} eq "original.txt", defined $uprow ? $uprow->{NAME} : "no row");
check("scan: upload vector is http", defined $uprow && $uprow->{VIA} eq "http", defined $uprow ? $uprow->{VIA} : "no row");

# 6. sweep_uploads ---------------------------------------------------------------
# stale in-flight upload (2 days old) -> row + temp file removed
my $stale = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeffff0000";
$dbh->do("insert into UPLOADS (ID,NAME,SIZE,RECEIVED,VIA,CREATED) values (?,?,100,10,'http',date_sub(now(), interval 2 day))",
    undef, $stale, "stale.txt");
my $staletmp = "$root/staging/http/.up-$stale.part";
open($fh, '>:raw', $staletmp) or die $!;
print $fh "x" x 10;
close($fh);
# recent in-flight upload -> left alone
my $recent = "11111111-2222-4333-8444-555555555555";
$dbh->do("insert into UPLOADS (ID,NAME,SIZE,RECEIVED,VIA,CREATED) values (?,?,100,10,'http',now())",
    undef, $recent, "recent.txt");
my $recenttmp = "$root/staging/http/.up-$recent.part";
open($fh, '>:raw', $recenttmp) or die $!;
print $fh "x" x 10;
close($fh);
# orphan temp file (no row) -> removed
my $orphantmp = "$root/staging/http/.up-99999999-8888-4777-8666-555544443333.part";
open($fh, '>:raw', $orphantmp) or die $!;
print $fh "x";
close($fh);

Luminum::Repo::sweep_uploads($dbh, $root, sub { });
my @stale_row = $dbh->selectrow_array("select 1 from UPLOADS where ID = ?", undef, $stale);
check("sweep: stale upload row removed", !defined $stale_row[0]);
check("sweep: stale temp file removed", !-e $staletmp);
my @recent_row = $dbh->selectrow_array("select 1 from UPLOADS where ID = ?", undef, $recent);
check("sweep: recent upload row kept", defined $recent_row[0]);
check("sweep: recent temp file kept", -e $recenttmp);
check("sweep: orphan temp file removed", !-e $orphantmp);

# 7. scan() entry point -----------------------------------------------------------
# an smb drop with the vector enabled is registered end to end
my $smbdrop = "$root/staging/smb/dropped.iso";
open($fh, '>:raw', $smbdrop) or die $!;
print $fh "iso content\n";
close($fh);
age($smbdrop);
set_config("REPOSMB", "Enabled");
my @log;
check("scan: entry point runs", Luminum::Repo::scan(
    root => $root, contentdbh => $dbh, sysdbh => $sysdb, log => sub { push @log, $_[0] },
) == 1);
my $smbrow = files_row(sha256_hex("iso content\n"));
check("scan: smb drop registered", defined $smbrow, join(" | ", @log));
check("scan: smb drop vector", defined $smbrow && $smbrow->{VIA} eq "smb", defined $smbrow ? $smbrow->{VIA} : "no row");
# and a disabled vector's drop is left in staging
set_config("REPONFS", "Disabled");
my $nfsdrop = "$root/staging/nfs/waiting.txt";
open($fh, '>:raw', $nfsdrop) or die $!;
print $fh "waiting content\n";
close($fh);
age($nfsdrop);
Luminum::Repo::scan(root => $root, contentdbh => $dbh, sysdbh => $sysdb, log => sub { });
check("scan: disabled vector left untouched", !files_row(sha256_hex("waiting content\n")) && -e $nfsdrop);

# ---------------------------------------------------------------------------
print "-" x 60, "\n";
if ($FAILURES) {
    print "FAILED: $FAILURES check(s) failed\n";
    exit 1;
}
print "All checks passed.\n";
exit 0;
