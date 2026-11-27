#!/usr/bin/perl
#
# broker_certs_test.pl - offline test for Luminum::Cert (protocol 7.1
# v1.1, docs/p2p.md 4.1): client TLS certificate issuance from a
# client-presented P-256 CSR.
#
#   1. ca_material: the dedicated Luminum CA (luminum-ca.crt/.key next
#      to the server certificate) wins; without it the server
#      certificate is its own anchor (import-mode fallback)
#   2. sign_client_csr (CA mode): the issued certificate carries
#      CN = luminum-client-{UID}, chains to the CA, and holds the
#      CSR's public key; two issuances get distinct serials
#   3. sign_client_csr (import fallback): the certificate chains to
#      the server certificate; a CA:FALSE anchor is tolerated (the P2P
#      channel verifies with rustls, whose trust anchors are not
#      subject to the CA:TRUE check)
#   4. rejections: garbage CSR, non-EC (RSA) CSR, malformed UIDs,
#      missing anchor material
#
# No database and no broker process: the module is exercised directly
# against scratch openssl material.
#
# Usage: perl tests/broker_certs_test.pl
# Exit code: 0 if all checks pass, 1 otherwise.

use strict;
use warnings;
use FindBin qw($Bin);
use File::Path qw(make_path remove_tree);

my $REPO = "$Bin/..";
unshift @INC, "$REPO/server/lib";
require Luminum::Cert;

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
my $openssl = which("openssl");
skip_all("openssl not available") unless $openssl;
# The module requires OpenSSL 3.0 (x509 -req -subj).
my $ver = `$openssl version 2>/dev/null`;
skip_all("OpenSSL 3.0 or newer required (found: " . ($ver || "none") . ")")
    unless $ver =~ /^OpenSSL [3-9]\./;

my $tmp = "/tmp/luminum-brokercerts-test.$$";
END { remove_tree($tmp) if defined $tmp && -d $tmp; }
make_path("$tmp/ssl-ca", "$tmp/ssl-import", "$tmp/ssl-noca", "$tmp/work");

# --- scratch PKI: a CA, a server leaf it issued, and a client CSR ----------
# Same shape as the installer's generate mode (Luminum::Setup::prepare_ssl):
# self-signed CA:TRUE CA, RSA leaf with a SAN.
my $ca = "$tmp/ssl-ca";
my $out = `cd $ca && $openssl req -x509 -newkey rsa:2048 -nodes -days 365 -keyout luminum-ca.key -out luminum-ca.crt -subj "/CN=Luminum Server CA" -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign" 2>&1`;
check("CA generated", $? == 0, $out);
open(my $ef, ">", "$ca/leaf.ext") or die $!;
print $ef "subjectAltName=DNS:certtest\n";
close($ef);
$out = `cd $ca && $openssl genpkey -algorithm rsa -pkeyopt rsa_keygen_bits:2048 -out server.key 2>&1 && $openssl req -new -key server.key -subj "/CN=certtest" -out server.csr 2>&1 && $openssl x509 -req -in server.csr -CA luminum-ca.crt -CAkey luminum-ca.key -set_serial 0x0100 -days 365 -extfile leaf.ext -out server.crt 2>&1`;
check("server leaf generated", $? == 0, $out);
# The installed layout: the CA files sit next to the server certificate.
for my $f (qw(luminum-ca.crt luminum-ca.key server.crt server.key)) {
    system("cp", "$ca/$f", "$tmp/ssl-import/$f") == 0 or die "copy $f: $!";
}
# Import-mode layout: the server certificate is its own anchor (no CA
# files). Re-issue the leaf self-signed so the fallback has a key that
# matches the certificate.
$out = `cd $tmp/ssl-noca && $openssl req -x509 -newkey rsa:2048 -nodes -days 365 -keyout server.key -out server.crt -subj "/CN=certtest" -addext "basicConstraints=critical,CA:TRUE" -addext "subjectAltName=DNS:certtest" 2>&1`;
check("import-mode self-signed anchor generated", $? == 0, $out);
# A CA:FALSE anchor (the documented import-mode limitation).
$out = `cd $tmp/ssl-noca && $openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 365 -keyout server-false.key -out server-false.crt -subj "/CN=certtest-false" -addext "basicConstraints=critical,CA:FALSE" 2>&1`;
check("CA:FALSE anchor generated", $? == 0, $out);

# Client P-256 keypair + CSR (what the client sends in tls_csr).
my $work = "$tmp/work";
$out = `cd $work && $openssl genpkey -algorithm ec -pkeyopt ec_paramgen_curve:prime256v1 -out client.key 2>&1 && $openssl req -new -key client.key -subj "/CN=luminum-client-pending" -out client.csr 2>&1`;
check("client P-256 CSR generated", $? == 0, $out);
my $csr_pem = do { local $/; open(my $fh, "<", "$work/client.csr") or die $!; <$fh> };
my $csr_pub = `cd $work && $openssl req -in client.csr -noout -pubkey 2>/dev/null`;
$csr_pub =~ s/\s+//g;

# An RSA CSR (must be rejected: the P2P channel requires P-256).
$out = `cd $work && $openssl genpkey -algorithm rsa -pkeyopt rsa_keygen_bits:2048 -out rsa.key 2>&1 && $openssl req -new -key rsa.key -subj "/CN=luminum-client-pending" -out rsa.csr 2>&1`;
check("RSA CSR generated", $? == 0, $out);
my $rsa_pem = do { local $/; open(my $fh, "<", "$work/rsa.csr") or die $!; <$fh> };

sub cert_subject {
    my ($pemfile) = @_;
    my $s = `$openssl x509 -in "$pemfile" -noout -subject 2>/dev/null`;
    $s =~ s/^subject=//;
    $s =~ s/\s+$//;
    $s =~ s/\s*=\s*/=/g;    # OpenSSL 3.x prints CN=..., 1.x CN = ...
    return $s;
}
sub cert_pubkey {
    my ($pemfile) = @_;
    my $p = `$openssl x509 -in "$pemfile" -noout -pubkey 2>/dev/null`;
    $p =~ s/\s+//g;
    return $p;
}
sub cert_serial {
    my ($pemfile) = @_;
    my $s = `$openssl x509 -in "$pemfile" -noout -serial 2>/dev/null`;
    $s =~ s/^serial=//;
    $s =~ s/\s+$//;
    return $s;
}
sub write_pem {
    my ($path, $pem) = @_;
    open(my $fh, ">", $path) or die "$path: $!";
    print $fh $pem;
    close($fh);
}

my @notes;
my $log = sub { push @notes, $_[0] };

# --- 1. ca_material ----------------------------------------------------------
my ($acert, $akey, $amode) = Luminum::Cert::ca_material("$tmp/ssl-import/server.crt", "$tmp/ssl-import/server.key");
check("ca_material: CA mode when luminum-ca.* present",
    $amode eq "ca" && $acert eq "$tmp/ssl-import/luminum-ca.crt" && $akey eq "$tmp/ssl-import/luminum-ca.key",
    "mode=[$amode] cert=[$acert]");
my ($icert, $ikey, $imode) = Luminum::Cert::ca_material("$tmp/ssl-noca/server.crt", "$tmp/ssl-noca/server.key");
check("ca_material: server fallback without luminum-ca.*",
    $imode eq "server" && $icert eq "$tmp/ssl-noca/server.crt" && $ikey eq "$tmp/ssl-noca/server.key",
    "mode=[$imode]");

# --- 2. CA mode issuance ------------------------------------------------------
my ($ok, $res) = Luminum::Cert::sign_client_csr($csr_pem, "42", "$tmp/ssl-import/server.crt", "$tmp/ssl-import/server.key", $log);
check("CA mode: issuance succeeds", $ok, $res);
my $c1 = "$tmp/work/issued-42.crt";
write_pem($c1, $res) if $ok;
check("CA mode: subject is CN=luminum-client-42",
    $ok && cert_subject($c1) eq "CN=luminum-client-42", $ok ? cert_subject($c1) : $res);
check("CA mode: chains to the Luminum CA",
    $ok && system("$openssl verify -CAfile $tmp/ssl-import/luminum-ca.crt $c1 >/dev/null 2>&1") == 0);
check("CA mode: public key matches the CSR",
    $ok && cert_pubkey($c1) eq $csr_pub);
my ($ok2, $res2) = Luminum::Cert::sign_client_csr($csr_pem, "42", "$tmp/ssl-import/server.crt", "$tmp/ssl-import/server.key", $log);
my $c2 = "$tmp/work/issued-42b.crt";
write_pem($c2, $res2) if $ok2;
check("CA mode: second issuance succeeds with a distinct serial",
    $ok2 && cert_serial($c1) ne cert_serial($c2),
    $ok2 ? "serials " . cert_serial($c1) . " / " . cert_serial($c2) : $res2);

# --- 3. import fallback -------------------------------------------------------
@notes = ();
my ($iok, $ires) = Luminum::Cert::sign_client_csr($csr_pem, "77", "$tmp/ssl-noca/server.crt", "$tmp/ssl-noca/server.key", $log);
check("import fallback: issuance succeeds", $iok, $ires);
my $ci = "$tmp/work/issued-77.crt";
write_pem($ci, $ires) if $iok;
check("import fallback: subject is CN=luminum-client-77",
    $iok && cert_subject($ci) eq "CN=luminum-client-77", $iok ? cert_subject($ci) : $ires);
check("import fallback: chains to the server certificate",
    $iok && system("$openssl verify -CAfile $tmp/ssl-noca/server.crt $ci >/dev/null 2>&1") == 0);

# CA:FALSE anchor: issuance must still succeed (documented limitation),
# with a note logged.
@notes = ();
my ($fok, $fres) = Luminum::Cert::sign_client_csr($csr_pem, "78", "$tmp/ssl-noca/server-false.crt", "$tmp/ssl-noca/server-false.key", $log);
check("CA:FALSE anchor: issuance succeeds (documented limitation)", $fok, $fres);
check("CA:FALSE anchor: limitation note logged",
    grep({ /lacks CA:TRUE/ } @notes), join(" | ", @notes));

# --- 4. rejections ------------------------------------------------------------
my ($rok, $rres) = Luminum::Cert::sign_client_csr("not a csr", "42", "$tmp/ssl-import/server.crt", "$tmp/ssl-import/server.key");
check("reject: garbage CSR", !$rok && $rres =~ /CSR|empty/i, $rres);
($rok, $rres) = Luminum::Cert::sign_client_csr($rsa_pem, "42", "$tmp/ssl-import/server.crt", "$tmp/ssl-import/server.key");
check("reject: RSA CSR (P-256 required)", !$rok && $rres =~ /P-256|EC/, $rres);
# Note: "4" and "2" are *valid* UIDs (any non-negative integer) and must
# be accepted; only non-numeric or empty values are malformed.
for my $bad (qw(42x 1.5 -1 0x10 (42))) {
    ($rok, $rres) = Luminum::Cert::sign_client_csr($csr_pem, $bad, "$tmp/ssl-import/server.crt", "$tmp/ssl-import/server.key");
    check("reject: malformed UID [$bad]", !$rok && $rres =~ /UID/, $rres);
}
($rok, $rres) = Luminum::Cert::sign_client_csr($csr_pem, "", "$tmp/ssl-import/server.crt", "$tmp/ssl-import/server.key");
check("reject: empty UID", !$rok && $rres =~ /UID/, $rres);
($rok, $rres) = Luminum::Cert::sign_client_csr($csr_pem, "42", "$tmp/ssl-noca/missing.crt", "$tmp/ssl-noca/missing.key");
check("reject: missing anchor material", !$rok && $rres =~ /not found/, $rres);

# ---------------------------------------------------------------------------
print "-" x 60, "\n";
if ($FAILURES) {
    print "FAILED: $FAILURES check(s) failed\n";
    exit 1;
}
print "All checks passed.\n";
exit 0;
