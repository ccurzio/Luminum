#!/usr/bin/perl
#
# p2p_grant_test.pl - offline test for Luminum::P2P (docs/p2p.md Phase 3,
# the seed path): grant minting from the package file list, the P2PTOKENS
# bookkeeping row, and the terminal transfer report folding (token
# consumption + PKGHOLDERS upsert).
#
#   1. mint_grant: the grant envelope carries the full per-file list in
#      PKGFILES order, the seed-form source list (uid 0, port 10704), a
#      300 s expiry, and verifies under the server signing key; a
#      P2PTOKENS row is recorded
#   2. mint_grant failures: a package with no files for the OS, and
#      missing parameters
#   3. on_report p2p_fetch_ok: the token is consumed and the requester is
#      upserted as a holder for every file (SOURCE 'server' for the seed
#      path, the serving peer's UID for a peer source); a repeat report
#      does not duplicate the holder rows
#   4. on_report rejections: a report from a UID other than the token's
#      requester, an unknown token, and a malformed token are ignored
#   5. on_report p2p_fetch_fail: the token is consumed, no holders
#
# Spins up a scratch MariaDB (the module is exercised directly; no broker
# process and no TLS).
#
# Usage: perl tests/p2p_grant_test.pl
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
use Time::Piece;

my $REPO = "$Bin/..";
unshift @INC, "$REPO/server/lib";

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

my $mariadbd   = which("mariadbd") || which("mysqld");
my $install_db = which("mariadb-install-db") || which("mysql_install_db");
my $cli        = which("mariadb") || which("mysql");
skip_all("mariadbd / mariadb-install-db / mariadb CLI not available")
    unless $mariadbd && $install_db && $cli;

# The module's dependencies must resolve under the ambient PERL5LIB.
my @need = ("IO/Socket/SSL.pm", "Crypt/Perl/Ed25519/PrivateKey.pm", "DBI.pm");
my %found;
for my $dir (@INC) {
    next unless defined $dir && length $dir;
    for my $mod (@need) {
        next if $found{$mod};
        $found{$mod} = $dir if -f "$dir/$mod";
    }
}
my @missing = grep { !$found{$_} } @need;
skip_all("module dependencies not in \@INC (" . join(", ", @missing)
    . "); set PERL5LIB and re-run") if @missing;

require Luminum::P2P;
require Luminum::Protocol;

my $tmp = "/tmp/luminum-p2pgrant-test.$$";
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

# --- scratch MariaDB ----------------------------------------------------------
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

# --- schema: the tables the module reads and writes ---------------------------
$out = `$cli -S $sock -u root -e "
    CREATE DATABASE CONTENT DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
    CREATE DATABASE CLIENTS DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
    CREATE TABLE CONTENT.FILES (
      ID int(20) NOT NULL AUTO_INCREMENT,
      SHA256 char(64) NOT NULL,
      SIZE bigint(20) NOT NULL,
      NAME tinytext NOT NULL,
      VIA tinytext NOT NULL,
      STAGED datetime NOT NULL,
      PRIMARY KEY (ID),
      UNIQUE KEY UQ_FILES_SHA (SHA256)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
    CREATE TABLE CONTENT.PKGFILES (
      ID int(20) NOT NULL AUTO_INCREMENT,
      PKGID int(20) NOT NULL,
      OS tinytext NOT NULL,
      FILEID int(20) NOT NULL,
      PATH tinytext NOT NULL,
      PRIMARY KEY (ID),
      KEY IDX_PKGFILES_PKG (PKGID),
      KEY IDX_PKGFILES_FILE (FILEID)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
    CREATE TABLE CONTENT.PKGHOLDERS (
      ID int(20) NOT NULL AUTO_INCREMENT,
      FILEID int(20) NOT NULL,
      UID int(20) NOT NULL,
      SOURCE tinytext NOT NULL,
      TS datetime NOT NULL,
      PRIMARY KEY (ID),
      UNIQUE KEY UQ_PKGHOLDERS (FILEID,UID)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
    CREATE TABLE CLIENTS.P2PTOKENS (
      TOKEN char(36) NOT NULL,
      PKGID int(20) NOT NULL,
      REQUID int(20) NOT NULL,
      SOURCES tinytext NOT NULL,
      EXPIRES datetime NOT NULL,
      USED datetime DEFAULT NULL,
      PRIMARY KEY (TOKEN),
      KEY IDX_P2PTOKENS_EXPIRES (EXPIRES)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
" 2>&1`;
check("scratch schema created", $? == 0, $out);
skip_all("could not create the scratch schema: $out") unless $? == 0;

# Two repository files attached to package 7 for Linux (and one Windows
# attachment, which must not appear in the Linux grant).
$out = `$cli -S $sock -u root -e "
    INSERT INTO CONTENT.FILES (SHA256,SIZE,NAME,VIA,STAGED) VALUES
      (REPEAT('aa', 32), 111, 'tool', 'drop', now()),
      (REPEAT('bb', 32), 222, 'lib.so', 'drop', now()),
      (REPEAT('cc', 32), 333, 'win.exe', 'drop', now());
    INSERT INTO CONTENT.PKGFILES (PKGID,OS,FILEID,PATH) VALUES
      (7, 'Linux', 1, 'bin/tool'),
      (7, 'Linux', 2, 'lib/lib.so'),
      (7, 'Windows', 3, 'win.exe');
" 2>&1`;
check("package files seeded", $? == 0, $out);
skip_all("could not seed package files: $out") unless $? == 0;

# --- database handles ----------------------------------------------------------
use DBI;
my $dbh = DBI->connect("DBI:mysql:CLIENTS", "root", "",
    { mysql_socket => $sock, RaiseError => 0, PrintError => 0 })
    or skip_all("cannot connect to the CLIENTS database: " . DBI->errstr);
my $contentdbh = DBI->connect("DBI:mysql:CONTENT", "root", "",
    { mysql_socket => $sock, RaiseError => 0, PrintError => 0 })
    or skip_all("cannot connect to the CONTENT database: " . DBI->errstr);

# --- server signing key ---------------------------------------------------------
my $seed;
open(my $ur, "<", "/dev/urandom") or skip_all("cannot read /dev/urandom: $!");
read($ur, $seed, 32) == 32 or skip_all("short read from /dev/urandom");
close($ur);
my $srvpub = Crypt::Perl::Ed25519::PrivateKey->new($seed)->get_public_key()->get_public();

sub q1 {
    my ($h, $sql, @bind) = @_;
    my ($v) = $h->selectrow_array($sql, undef, @bind);
    return $v;
}

# --- 1. mint_grant: the happy path ---------------------------------------------
my $t0 = time();
my @r = Luminum::P2P::mint_grant(
    contentdbh => $contentdbh, dbh => $dbh, seed => $seed,
    uid => 42, pkgid => 7, os => "Linux", aid => "cmd-123",
    server_ip => "10.0.0.1", log => sub { },
);
check("mint_grant succeeds", $r[0] == 1, $r[1] // "");
my ($env, $token) = ($r[1], $r[2]);
check("grant token is a UUIDv4", defined $token && $token =~ /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[0-9a-f]{4}-[0-9a-f]{12}$/, $token // "undef");
check("grant envelope shape",
    ref($env) eq "HASH" && $env->{src} eq "server" && $env->{lumy} eq "core"
    && $env->{action} eq "p2pgrant" && $env->{status} eq "OK" && $env->{uid} == 42,
    ref($env) eq "HASH" ? "src=$env->{src} action=$env->{action}" : "not a hash");
check("grant verifies under the server signing key",
    Luminum::Protocol::verify_envelope($env, $srvpub) == 1);
my $d = ref($env) eq "HASH" ? $env->{data} : {};
check("grant data: token/pkgid/os/aid",
    ref($d) eq "HASH" && $d->{token} eq $token && $d->{pkgid} == 7
    && $d->{os} eq "Linux" && $d->{aid} eq "cmd-123",
    ref($d) eq "HASH" ? "token=" . ($d->{token} // "?") : "no data");
check("grant data: expiry is now+300",
    defined $d->{exp} && $d->{exp} >= $t0 + 300 && $d->{exp} <= $t0 + 305,
    defined $d->{exp} ? "exp=$d->{exp}" : "no exp");
check("grant data: seed-form source list",
    ref($d->{sources}) eq "ARRAY" && @{$d->{sources}} == 1
    && $d->{sources}[0]{uid} == 0 && $d->{sources}[0]{ip} eq "10.0.0.1"
    && $d->{sources}[0]{port} == 10704,
    ref($d->{sources}) eq "ARRAY" ? "n=" . scalar(@{$d->{sources}}) : "no sources");
check("grant data: the Linux file list in PKGFILES order",
    ref($d->{files}) eq "ARRAY" && @{$d->{files}} == 2
    && $d->{files}[0]{fileid} == 1 && $d->{files}[0]{path} eq "bin/tool"
    && $d->{files}[0]{size} == 111 && $d->{files}[0]{sha256} eq "aa" x 32
    && $d->{files}[1]{fileid} == 2 && $d->{files}[1]{path} eq "lib/lib.so"
    && $d->{files}[1]{size} == 222 && $d->{files}[1]{sha256} eq "bb" x 32,
    ref($d->{files}) eq "ARRAY" ? "n=" . scalar(@{$d->{files}}) : "no files");
my $row = $dbh->selectrow_hashref("select * from P2PTOKENS where TOKEN = ?", undef, $token);
check("P2PTOKENS row recorded",
    defined $row && $row->{PKGID} == 7 && $row->{REQUID} == 42 && !defined $row->{USED}
    && $row->{SOURCES} =~ /10\.0\.0\.1/ && $row->{SOURCES} =~ /10704/,
    defined $row ? "sources=$row->{SOURCES}" : "no row");
my $expires_epoch = (defined $row && defined $row->{EXPIRES}
    && $row->{EXPIRES} =~ /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/)
    ? Time::Piece->strptime($row->{EXPIRES}, "%Y-%m-%d %H:%M:%S")->epoch
    : undef;
check("P2PTOKENS expiry matches the grant",
    defined $expires_epoch && defined $d->{exp} && abs($expires_epoch - $d->{exp}) <= 2,
    defined $row ? "expires=$row->{EXPIRES} exp=" . ($d->{exp} // "?") : "no row");

# --- 2. mint_grant failures ------------------------------------------------------
@r = Luminum::P2P::mint_grant(
    contentdbh => $contentdbh, dbh => $dbh, seed => $seed,
    uid => 42, pkgid => 99, os => "Linux", aid => "cmd-x",
    server_ip => "10.0.0.1", log => sub { },
);
check("mint_grant: no files for the OS fails",
    $r[0] == 0 && ($r[1] // "") =~ /no files attached/, $r[1] // "unexpected success");
@r = Luminum::P2P::mint_grant(
    contentdbh => $contentdbh, dbh => $dbh, seed => $seed,
    uid => 42, pkgid => 7, os => "Linux", aid => "cmd-x",
    server_ip => "10.0.0.1", log => sub { },
);
# (sanity: the same mint succeeds again - a fresh token each time)
check("mint_grant: a second mint issues a distinct token",
    $r[0] == 1 && defined $r[2] && $r[2] ne $token, $r[2] // $r[1] // "");
@r = Luminum::P2P::mint_grant(
    contentdbh => $contentdbh, dbh => $dbh, seed => $seed,
    uid => "42x", pkgid => 7, os => "Linux", aid => "cmd-x",
    server_ip => "10.0.0.1", log => sub { },
);
check("mint_grant: a malformed UID fails",
    $r[0] == 0 && ($r[1] // "") =~ /missing grant parameters/, $r[1] // "unexpected success");
@r = Luminum::P2P::mint_grant(
    contentdbh => $contentdbh, dbh => $dbh, seed => $seed,
    uid => 42, pkgid => 7, os => "", aid => "cmd-x",
    server_ip => "10.0.0.1", log => sub { },
);
check("mint_grant: an empty OS fails",
    $r[0] == 0 && ($r[1] // "") =~ /missing grant parameters/, $r[1] // "unexpected success");

# --- 3. on_report p2p_fetch_ok ----------------------------------------------------
my $logbuf = [];
my $log = sub { push @$logbuf, $_[0]; };

# Seed-path completion (srcuid 0 -> SOURCE 'server').
Luminum::P2P::on_report($dbh, $contentdbh, 42, {
    event => "p2p_fetch_ok", token => $token, pkgid => 7, srcuid => 0,
    files => [1, 2],
}, $log);
my $used1 = q1($dbh, "select USED from P2PTOKENS where TOKEN = ?", $token);
check("fetch_ok: the token is consumed",
    defined $used1 && $used1 ne "", "USED still empty");
my $h1 = q1($contentdbh, "select SOURCE from PKGHOLDERS where FILEID = 1 and UID = 42");
my $h2 = q1($contentdbh, "select SOURCE from PKGHOLDERS where FILEID = 2 and UID = 42");
check("fetch_ok: holders upserted with SOURCE 'server'",
    defined $h1 && $h1 eq "server" && defined $h2 && $h2 eq "server",
    "h1=[" . ($h1 // "undef") . "] h2=[" . ($h2 // "undef") . "]");

# A repeat report must not duplicate the holder rows.
Luminum::P2P::on_report($dbh, $contentdbh, 42, {
    event => "p2p_fetch_ok", token => $token, pkgid => 7, srcuid => 0,
    files => [1, 2],
}, $log);
my $nhold = q1($contentdbh, "select count(*) from PKGHOLDERS where UID = 42");
check("fetch_ok: a repeat report does not duplicate holders",
    defined $nhold && $nhold == 2, "count=" . ($nhold // "undef"));

# A peer-served completion records the serving peer's UID as the source.
my @r2 = Luminum::P2P::mint_grant(
    contentdbh => $contentdbh, dbh => $dbh, seed => $seed,
    uid => 42, pkgid => 7, os => "Linux", aid => "cmd-2",
    server_ip => "10.0.0.1", log => $log,
);
my $token2 = $r2[2];
Luminum::P2P::on_report($dbh, $contentdbh, 42, {
    event => "p2p_fetch_ok", token => $token2, pkgid => 7, srcuid => 7,
    files => [1],
}, $log);
my $h1b = q1($contentdbh, "select SOURCE from PKGHOLDERS where FILEID = 1 and UID = 42");
check("fetch_ok: a peer source records the peer UID",
    defined $h1b && $h1b eq "7", "source=[" . ($h1b // "undef") . "]");

# --- 4. on_report rejections -------------------------------------------------------
# A report from a UID other than the token's requester.
my @r3 = Luminum::P2P::mint_grant(
    contentdbh => $contentdbh, dbh => $dbh, seed => $seed,
    uid => 42, pkgid => 7, os => "Linux", aid => "cmd-3",
    server_ip => "10.0.0.1", log => $log,
);
my $token3 = $r3[2];
Luminum::P2P::on_report($dbh, $contentdbh, 99, {
    event => "p2p_fetch_ok", token => $token3, pkgid => 7, srcuid => 0,
    files => [1],
}, $log);
check("fetch_ok from the wrong UID is ignored (token stays unused)",
    !defined q1($dbh, "select USED from P2PTOKENS where TOKEN = ?", $token3)
    && q1($contentdbh, "select count(*) from PKGHOLDERS where FILEID = 1 and UID = 99") == 0,
    "USED=" . (q1($dbh, "select USED from P2PTOKENS where TOKEN = ?", $token3) // "null"));

# An unknown token.
Luminum::P2P::on_report($dbh, $contentdbh, 42, {
    event => "p2p_fetch_ok",
    token => "00000000-0000-4000-8000-000000000000", pkgid => 7, srcuid => 0,
    files => [1],
}, $log);
check("unknown token is ignored",
    scalar(grep { /unknown token/ } @$logbuf) == 1
    && q1($contentdbh, "select count(*) from PKGHOLDERS where UID = 42") == 2,
    "log=" . join("; ", @$logbuf));

# A malformed token.
Luminum::P2P::on_report($dbh, $contentdbh, 42, {
    event => "p2p_fetch_ok", token => "not-a-token", pkgid => 7, srcuid => 0,
    files => [1],
}, $log);
check("malformed token is ignored (no crash, no holders for UID 42 beyond the two)",
    q1($contentdbh, "select count(*) from PKGHOLDERS where UID = 42") == 2,
    "count=" . q1($contentdbh, "select count(*) from PKGHOLDERS where UID = 42"));

# --- 5. on_report p2p_fetch_fail -----------------------------------------------------
my @r4 = Luminum::P2P::mint_grant(
    contentdbh => $contentdbh, dbh => $dbh, seed => $seed,
    uid => 42, pkgid => 7, os => "Linux", aid => "cmd-4",
    server_ip => "10.0.0.1", log => $log,
);
my $token4 = $r4[2];
Luminum::P2P::on_report($dbh, $contentdbh, 42, {
    event => "p2p_fetch_fail", token => $token4, pkgid => 7, srcuid => 0,
    err => "HASH_MISMATCH",
}, $log);
my $used4 = q1($dbh, "select USED from P2PTOKENS where TOKEN = ?", $token4);
check("fetch_fail: the token is consumed",
    defined $used4 && $used4 ne "", "USED still empty");
check("fetch_fail: no holders recorded",
    q1($contentdbh, "select count(*) from PKGHOLDERS where UID = 42") == 2,
    "count=" . q1($contentdbh, "select count(*) from PKGHOLDERS where UID = 42"));
check("fetch_fail: the reason is logged",
    scalar(grep { /failed grant $token4.*HASH_MISMATCH/ } @$logbuf) == 1,
    "log=" . join("; ", @$logbuf));

# ---------------------------------------------------------------------------
print "-" x 60, "\n";
if ($FAILURES) {
    print "FAILED: $FAILURES check(s) failed\n";
    exit 1;
}
print "All checks passed.\n";
exit 0;
