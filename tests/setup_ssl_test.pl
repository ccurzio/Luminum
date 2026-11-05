#!/usr/bin/perl
#
# setup_ssl_test.pl - offline test harness for Luminum::Setup::prepare_ssl.
#
# Covers all three modes (generate/new, generate/existing, import) against
# real OpenSSL fixtures: fresh key generation, encrypted key import with
# passphrase, key/cert mismatch, expired certificate, missing files, and
# the hostname-coverage warning.
#
# Usage: perl tests/setup_ssl_test.pl
# Exit code: 0 if all checks pass, 1 otherwise.

use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin/../server/lib";
use File::Path qw(make_path remove_tree);
use File::Basename qw(basename);

use Luminum::Setup;

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

my $tmp = "/tmp/luminum-setup-ssl-test.$$";
END { remove_tree($tmp) if defined $tmp && -d $tmp; }
make_path("$tmp/plain", "$tmp/enc", "$tmp/exp", "$tmp/other",
          "$tmp/d1", "$tmp/d2", "$tmp/d3", "$tmp/d4", "$tmp/d5", "$tmp/d6");

sub run_openssl {
    my (@cmd) = @_;
    my $out = `@cmd 2>&1`;
    return ($?, $out);
}

# --- fixtures ---------------------------------------------------------------
my ($rc, $out);

# Plain (unencrypted) key + self-signed cert for ssl.test
($rc, $out) = run_openssl("openssl req -x509 -newkey rsa:2048 -nodes -days 30 " .
    "-keyout $tmp/plain/key.pem -out $tmp/plain/cert.pem " .
    "-subj /CN=ssl.test -addext subjectAltName=DNS:ssl.test");
die "fixture plain failed: $out" unless $rc == 0;

# Encrypted key + cert
($rc, $out) = run_openssl("openssl req -x509 -newkey rsa:2048 -days 30 " .
    "-keyout $tmp/enc/key.pem -passout pass:testpass -out $tmp/enc/cert.pem " .
    "-subj /CN=ssl.test -addext subjectAltName=DNS:ssl.test");
die "fixture enc failed: $out" unless $rc == 0;

# Expired cert (fixed 2020 dates)
($rc, $out) = run_openssl("openssl genpkey -algorithm RSA -out $tmp/exp/key.pem");
die "fixture exp key failed: $out" unless $rc == 0;
($rc, $out) = run_openssl("openssl req -new -key $tmp/exp/key.pem -out $tmp/exp/csr.pem -subj /CN=ssl.test");
die "fixture exp csr failed: $out" unless $rc == 0;
($rc, $out) = run_openssl("openssl x509 -req -in $tmp/exp/csr.pem -signkey $tmp/exp/key.pem " .
    "-out $tmp/exp/cert.pem -days 1 -not_before 20200101000000Z -not_after 20210101000000Z");
die "fixture exp cert failed: $out" unless $rc == 0;

# Key + cert for a different host
($rc, $out) = run_openssl("openssl req -x509 -newkey rsa:2048 -nodes -days 30 " .
    "-keyout $tmp/other/key.pem -out $tmp/other/cert.pem " .
    "-subj /CN=other.test -addext subjectAltName=DNS:other.test");
die "fixture other failed: $out" unless $rc == 0;

my $log = "";
sub do_ssl {
    my ($shost, $ssldir, $spec) = @_;
    $log = "";
    return Luminum::Setup::prepare_ssl($shost, $ssldir, $spec, sub { $log .= $_[0] . "\n" });
}

# --- generate / new ---------------------------------------------------------
my ($ok, $cert, $key, $pub, $err) = do_ssl("ssl.test", "$tmp/d1",
    { mode => "generate", keymode => "new" });
check("generate/new: succeeds", $ok == 1, $err);
check("generate/new: returns cert/key/pub paths",
    defined $cert && defined $key && defined $pub);
check("generate/new: files exist", -f $cert && -f $key && -f $pub);
my $mode = ((stat($key))[2]) & 07777;
check("generate/new: key is 0600", defined $mode && $mode == 0600, sprintf "%04o", $mode // 0);
($rc, $out) = run_openssl("openssl x509 -in $cert -noout -subject -ext subjectAltName");
check("generate/new: cert covers host (CN + SAN)",
    $rc == 0 && $out =~ /ssl\.test/ && $out =~ /ssl\.test/, $out);
($rc, $out) = run_openssl("openssl pkey -in $key -noout");
check("generate/new: key is unencrypted", $rc == 0, $out);
($rc, $out) = run_openssl("openssl x509 -in $cert -noout -checkend 0");
check("generate/new: cert is not expired", $rc == 0, $out);

# --- generate / new with IP host -> IP SAN ----------------------------------
($ok, $cert, $key, $pub, $err) = do_ssl("192.168.1.5", "$tmp/d2",
    { mode => "generate", keymode => "new" });
check("generate/new (IP host): succeeds", $ok == 1, $err);
($rc, $out) = run_openssl("openssl x509 -in $cert -noout -ext subjectAltName");
check("generate/new (IP host): SAN is IP form",
    $rc == 0 && $out =~ /IP Address:192\.168\.1\.5|IP:192\.168\.1\.5/, $out);

# --- generate / existing ----------------------------------------------------
($ok, $cert, $key, $pub, $err) = do_ssl("ssl.test", "$tmp/d3",
    { mode => "generate", keymode => "existing",
      cert => "$tmp/plain/cert.pem", key => "$tmp/plain/key.pem" });
check("generate/existing: succeeds", $ok == 1, $err);
check("generate/existing: files installed", -f $cert && -f $key && -f $pub);
my ($rc1, $p1) = run_openssl("openssl pkey -in $key -pubout");
my ($rc2, $p2) = run_openssl("openssl pkey -in $tmp/plain/key.pem -pubout");
check("generate/existing: provided key installed",
    $rc1 == 0 && $rc2 == 0 && $p1 eq $p2);

($ok, undef, undef, undef, $err) = do_ssl("ssl.test", "$tmp/d4",
    { mode => "generate", keymode => "existing",
      cert => "$tmp/enc/cert.pem", key => "$tmp/enc/key.pem" });
check("generate/existing: encrypted key without passphrase rejected",
    $ok == 0 && $err eq "key passphrase is required (encrypted key)", $err);

($ok, undef, undef, undef, $err) = do_ssl("ssl.test", "$tmp/d4",
    { mode => "generate", keymode => "existing",
      cert => "$tmp/enc/cert.pem", key => "$tmp/enc/key.pem", keypass => "wrong" });
check("generate/existing: wrong passphrase rejected",
    $ok == 0 && $err eq "key passphrase is incorrect", $err);

($ok, $cert, $key, $pub, $err) = do_ssl("ssl.test", "$tmp/d4",
    { mode => "generate", keymode => "existing",
      cert => "$tmp/enc/cert.pem", key => "$tmp/enc/key.pem", keypass => "testpass" });
check("generate/existing: encrypted key with passphrase succeeds", $ok == 1, $err);
($rc, $out) = run_openssl("openssl pkey -in $key -noout");
check("generate/existing: installed key is unencrypted", $rc == 0, $out);

# --- import -----------------------------------------------------------------
($ok, $cert, $key, $pub, $err) = do_ssl("ssl.test", "$tmp/d5",
    { mode => "import",
      cert => "$tmp/plain/cert.pem", key => "$tmp/plain/key.pem" });
check("import: matching cert/key succeeds", $ok == 1, $err);
check("import: files installed", -f $cert && -f $key && -f $pub);
my $mode2 = ((stat($key))[2]) & 07777;
check("import: key is 0600", defined $mode2 && $mode2 == 0600, sprintf "%04o", $mode2 // 0);
($rc1, $p1) = run_openssl("openssl x509 -in $cert -pubkey -noout 2>/dev/null");
($rc2, $p2) = run_openssl("openssl pkey -in $key -pubout 2>/dev/null");
(my $c1 = $p1) =~ s/\s+//g;
(my $c2 = $p2) =~ s/\s+//g;
check("import: pub matches cert", $c1 ne "" && $c1 eq $c2);

($ok, $cert, $key, $pub, $err) = do_ssl("ssl.test", "$tmp/d6",
    { mode => "import",
      cert => "$tmp/enc/cert.pem", key => "$tmp/enc/key.pem", keypass => "testpass" });
check("import: encrypted key with passphrase succeeds", $ok == 1, $err);
($rc, $out) = run_openssl("openssl pkey -in $key -noout");
check("import: installed key is unencrypted", $rc == 0, $out);

($ok, undef, undef, undef, $err) = do_ssl("ssl.test", "$tmp/d5",
    { mode => "import",
      cert => "$tmp/plain/cert.pem", key => "$tmp/other/key.pem" });
check("import: mismatched key rejected",
    $ok == 0 && $err eq "private key does not match the certificate", $err);

($ok, undef, undef, undef, $err) = do_ssl("ssl.test", "$tmp/d5",
    { mode => "import",
      cert => "$tmp/exp/cert.pem", key => "$tmp/exp/key.pem" });
check("import: expired certificate rejected",
    $ok == 0 && $err eq "certificate is expired", $err);

($ok, undef, undef, undef, $err) = do_ssl("ssl.test", "$tmp/d5",
    { mode => "import",
      cert => "$tmp/nope.pem", key => "$tmp/plain/key.pem" });
check("import: missing cert reported",
    $ok == 0 && $err eq "certificate not found: $tmp/nope.pem", $err);

($ok, undef, undef, undef, $err) = do_ssl("ssl.test", "$tmp/d5",
    { mode => "import",
      cert => "$tmp/plain/cert.pem", key => "$tmp/nope.pem" });
check("import: missing key reported",
    $ok == 0 && $err eq "private key not found: $tmp/nope.pem", $err);

($ok, undef, undef, undef, $err) = do_ssl("ssl.test", "$tmp/d5",
    { mode => "import" });
check("import: missing cert path reported",
    $ok == 0 && $err eq "certificate path is required for import", $err);

# --- hostname coverage warning ----------------------------------------------
($ok, $cert, $key, $pub, $err) = do_ssl("ssl.test", "$tmp/d6",
    { mode => "import",
      cert => "$tmp/other/cert.pem", key => "$tmp/other/key.pem" });
check("import: uncovered host still succeeds", $ok == 1, $err);
check("import: coverage warning logged",
    $log =~ /does not list ssl\.test/, $log);

# ---------------------------------------------------------------------------
print "-" x 60, "\n";
if ($FAILURES) {
    print "FAILED: $FAILURES check(s) failed\n";
    exit 1;
}
print "All checks passed.\n";
exit 0;
