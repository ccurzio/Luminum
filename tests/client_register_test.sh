#!/usr/bin/env bash
# Client registration test: runs the client against a one-shot fake
# bootstrap server (TLS + length-prefixed frames + Ed25519-signed
# response, reusing Luminum::Protocol so the wire format is exactly
# the real broker's) and verifies the client stores UID, SRVPUB,
# MQTTSECRET, MQTTHOST, and MQTTPORT from the signed registration
# response (protocol 7.1).
#
# The fake server signs with the key of an Ed25519 signing
# certificate issued by the test TLS certificate (which carries
# CA:TRUE), and the client is given that certificate as its
# bootstrap trust anchor (config/server-signing.crt). Negative
# scenarios: a serverpubkey that does not match the anchor, and a
# missing anchor - in both cases the client must store nothing.
#
# Usage: bash tests/client_register_test.sh
set -u
REPO=$(cd "$(dirname "$0")/.." && pwd)
CLIENT_BIN="$REPO/client/linux/target/debug/LuminumClient"
[ -x "$CLIENT_BIN" ] || { echo "SKIP - client binary not built at $CLIENT_BIN"; exit 0; }
[ -x "$(command -v openssl)" ] || { echo "SKIP - openssl not available"; exit 0; }
# Luminum::Protocol lives in the repo; the broker's non-core modules
# (IO::Socket::SSL, Crypt::Perl::Ed25519) come from the ambient PERL5LIB.
PERL_LIBS="$REPO/server/lib${PERL5LIB:+:$PERL5LIB}"
PERL5LIB="$PERL_LIBS" perl -e \
    'use IO::Socket::SSL; use Crypt::Perl::Ed25519::PrivateKey; use Luminum::Protocol;' 2>/dev/null \
    || { echo "SKIP - Perl dependencies for the fake bootstrap server are missing"; exit 0; }

PORT=14665
UID_EXPECTED=42
MQTTHOST_EXPECTED="mqtt.regtest"
MQTTPORT_EXPECTED="18883"

SCRATCH="$HOME/.lumclient-reg-test"
CERTDIR="$SCRATCH/certs"
FAKE="$SCRATCH/fakeserver.pl"
FAILURES=0
CLIENT_PID=""
FAKE_PID=""
check() {
    local name="$1" ok="$2" detail="${3:-}"
    if [ "$ok" -eq 0 ]; then
        echo "ok   - $name"
    else
        FAILURES=$((FAILURES + 1))
        echo "FAIL - $name${detail:+ ($detail)}"
    fi
}

cleanup() {
    [ -n "$CLIENT_PID" ] && kill "$CLIENT_PID" 2>/dev/null
    [ -n "$FAKE_PID" ] && kill "$FAKE_PID" 2>/dev/null
    rm -rf "$SCRATCH"
}
trap cleanup EXIT

cfgval() {
    python3 - "$1" "$2" <<'EOF'
import sqlite3, sys
try:
    conn = sqlite3.connect(sys.argv[2] + "/config/client.conf.db")
    row = conn.execute("select VALUE from CONFIG where KEY=?", (sys.argv[1],)).fetchone()
    print(row[0] if row else "")
except Exception:
    print("")
EOF
}

issued_val() {
    # $1 = key, $2 = issued file
    grep "^$1=" "$2" 2>/dev/null | head -n 1 | cut -d= -f2-
}

# --- TLS certificate valid for 127.0.0.1 (the client verifies the hostname) ---
# CA:TRUE so it can issue the Ed25519 signing certificate, which the
# client chains against it as the bootstrap trust anchor (protocol 7.1).
mkdir -p "$CERTDIR" || exit 1
openssl req -x509 -newkey rsa:2048 -nodes -days 30 \
    -keyout "$CERTDIR/key.pem" -out "$CERTDIR/cert.pem" \
    -subj "/CN=127.0.0.1" \
    -addext "subjectAltName=IP:127.0.0.1" \
    -addext "basicConstraints=critical,CA:TRUE" 2>/dev/null

# --- Ed25519 signing key + certificate issued by the TLS certificate ---------
openssl genpkey -algorithm ed25519 -out "$CERTDIR/signing.key" 2>/dev/null
openssl req -new -key "$CERTDIR/signing.key" -subj "/CN=127.0.0.1" \
    -out "$CERTDIR/signing.csr" 2>/dev/null
openssl x509 -req -in "$CERTDIR/signing.csr" -CA "$CERTDIR/cert.pem" \
    -CAkey "$CERTDIR/key.pem" -set_serial 0x01 -days 30 \
    -out "$CERTDIR/signing.crt" 2>/dev/null
# PKCS#8 Ed25519 DER is a fixed 48-byte prefix + the 32-byte seed.
openssl pkey -in "$CERTDIR/signing.key" -outform DER 2>/dev/null | tail -c 32 > "$CERTDIR/signing.seed"
[ "$(stat -c %s "$CERTDIR/signing.seed")" = "32" ] || { echo "SKIP - could not derive the signing seed"; exit 0; }

# --- one-shot fake bootstrap server ------------------------------------------
# Listens, signals readiness, accepts exactly one connection, reads the
# registration frame, and answers with a signed OK response carrying the
# MQTT credentials. Signs with the seed from the signing key. In
# "mismatch" mode the in-band serverpubkey field carries a *different*
# key, which the client must reject. The issued values are written to
# $ISSUED for the test to compare against the client's config DB.
cat > "$FAKE" <<'PERL'
use strict;
use warnings;
use IO::Socket::SSL;
use File::Temp qw(tempfile);
use MIME::Base64;
use Crypt::Perl::Ed25519::PrivateKey;
use Luminum::Protocol;

my ($port, $cert, $key, $uid, $mqtthost, $mqttport, $issued, $ready,
    $seedfile, $mode) = @ARGV;

open(my $sf, "<", $seedfile) or die "fake server: cannot read seed: $!\n";
binmode($sf);
read($sf, my $seed, 32);
close($sf);
my $priv = Crypt::Perl::Ed25519::PrivateKey->new($seed);
my $pubraw = $priv->get_public_key()->get_public();
my $spki_b64 = encode_base64(Luminum::Protocol::raw_to_spki($pubraw), "");
if ($mode eq "mismatch") {
    # A different key in the convenience field: the client must treat
    # the mismatch with the validated anchor as fatal.
    my $other = Crypt::Perl::Ed25519::PrivateKey->new();
    $spki_b64 = encode_base64(Luminum::Protocol::raw_to_spki($other->get_public_key()->get_public()), "");
}

open(my $ur, "<", "/dev/urandom") or die "urandom: $!\n";
binmode($ur);
read($ur, my $secret_raw, 32);
close($ur);
my $secret = encode_base64($secret_raw, "");

my $srv = IO::Socket::SSL->new(
    LocalAddr => "127.0.0.1:$port",
    Proto => 'tcp',
    Listen => 1,
    SSL_cert_file => $cert,
    SSL_key_file => $key,
) or die "fake server: cannot listen: $SSL_ERROR\n";
open(my $rf, ">", $ready) or die "fake server: cannot write $ready: $!\n";
close($rf);

my $cs = $srv->accept();
die "fake server: accept failed\n" unless $cs;
$cs->timeout(10);

my $lenbuf;
my $n = $cs->sysread($lenbuf, 4);
die "fake server: no frame length (handshake failed?)\n" unless $n == 4;
my ($len) = unpack("N", $lenbuf);
my $payload = "";
my $got = 0;
while ($got < $len) {
    my $chunk;
    $n = $cs->sysread($chunk, $len - $got);
    last unless $n;
    $payload .= $chunk;
    $got += $n;
}
my ($ok, $req) = Luminum::Protocol::frame_decode($lenbuf . $payload);
my $action = $req->{action} // "";
die "fake server: unexpected action [$action]\n"
    unless $action eq "register" || $action eq "certrenew";

# Sign the presented CSR the way the real broker does (Luminum::Cert):
# the subject is overridden with the assigned UID and the certificate is
# issued by the TLS certificate (which carries CA:TRUE here).
my $clientcert_b64 = "";
my $csr_b64 = $req->{data}{tls_csr} // "";
if ($csr_b64 ne "") {
    my $csr = eval { decode_base64($csr_b64) };
    if (defined $csr && $csr =~ /-----BEGIN CERTIFICATE REQUEST-----/) {
        my ($cfh, $cfile) = tempfile("fakecsr-XXXXXX", SUFFIX => ".csr");
        print $cfh $csr;
        close($cfh);
        my ($ofh, $ofile) = tempfile("fakecrt-XXXXXX", SUFFIX => ".crt");
        close($ofh);
        my $rc = system("openssl x509 -req -in \"$cfile\" -CA \"$cert\" -CAkey \"$key\" "
            . "-set_serial 0x42 -days 30 -subj \"/CN=luminum-client-$uid\" "
            . "-out \"$ofile\" >/dev/null 2>&1");
        if ($rc == 0) {
            my $crt = do { local $/; open(my $rf, "<", $ofile) or die "fake server: $!\n"; <$rf> };
            $clientcert_b64 = encode_base64($crt, "");
        }
        unlink($cfile, $ofile);
    }
}

my %respdata;
if ($action eq "register") {
    %respdata = (
        uid => $uid,
        mqtthost => $mqtthost,
        mqttport => $mqttport,
        mqttsecret => $secret,
        serverpubkey => $spki_b64,
    );
}
$respdata{clientcert} = $clientcert_b64 if $clientcert_b64 ne "";

my $resp = Luminum::Protocol::new_envelope(
    src => "server",
    uid => $req->{uid},
    lumy => $req->{lumy},
    action => $action,
    status => "OK"
);
$resp->{data} = \%respdata;
Luminum::Protocol::sign_envelope($resp, $seed);
my $frame = Luminum::Protocol::frame_encode($resp, 64*1024);
$cs->syswrite($frame);
$cs->close();

open(my $out, ">", $issued) or die "fake server: cannot write $issued: $!\n";
print $out "ACTION=$action\n";
print $out "UID=$uid\n";
print $out "UUID=", ($req->{data}{uuid} // ""), "\n";
print $out "MQTTSECRET=$secret\n";
print $out "MQTTHOST=$mqtthost\n";
print $out "MQTTPORT=$mqttport\n";
print $out "SRVPUB=", encode_base64($pubraw, ""), "\n";
print $out "CSR=", ($csr_b64 ne "" ? "yes" : "no"), "\n";
print $out "CLIENTCERT=", ($clientcert_b64 ne "" ? "yes" : "no"), "\n";
close($out);
PERL

# --- scenario runner ----------------------------------------------------------
# $1 = scenario name, $2 = fake server mode (ok|mismatch),
# $3 = install the signing anchor (1|0). Seeds a fresh client home,
# runs one registration attempt, and leaves the home in $SCEN_HOME.
SCEN_HOME=""
run_scenario() {
    local name="$1" mode="$2" anchor="$3"
    SCEN_HOME="$SCRATCH/home-$1"
    local issued="$SCRATCH/issued-$1" ready="$SCRATCH/ready-$1"
    mkdir -p "$SCEN_HOME/config"

    python3 - "$SCEN_HOME" "$PORT" <<'EOF'
import sqlite3, sys
home, port = sys.argv[1], sys.argv[2]
conn = sqlite3.connect(home + "/config/client.conf.db")
conn.execute("create table if not exists CONFIG (KEY text not null, VALUE text not null)")
for k, v in [("SHOST", "127.0.0.1"), ("SPORT", port), ("SVRKEY", "regtest")]:
    conn.execute("insert into CONFIG (KEY,VALUE) values (?,?)", (k, v))
conn.commit()
EOF
    cp "$CERTDIR/cert.pem" "$SCEN_HOME/config/server.crt"
    [ "$anchor" = "1" ] && cp "$CERTDIR/signing.crt" "$SCEN_HOME/config/server-signing.crt"

    PERL5LIB="$PERL_LIBS" perl "$FAKE" "$PORT" "$CERTDIR/cert.pem" "$CERTDIR/key.pem" \
        "$UID_EXPECTED" "$MQTTHOST_EXPECTED" "$MQTTPORT_EXPECTED" "$issued" "$ready" \
        "$CERTDIR/signing.seed" "$mode" &
    FAKE_PID=$!
    local i
    for i in $(seq 1 40); do
        [ -f "$ready" ] && break
        sleep 0.25
    done
    check "$name: fake server listening" $([ -f "$ready" ]; echo $?)

    LUMINUM_HOME="$SCEN_HOME" "$CLIENT_BIN" > "$SCRATCH/client-$1.log" 2>&1 &
    CLIENT_PID=$!
    # Wait for a stored result (happy path) or a full registration
    # round to elapse (negative scenarios store nothing).
    for i in $(seq 1 20); do
        [ -n "$(cfgval MQTTSECRET "$SCEN_HOME")" ] && break
        sleep 0.5
    done
    kill "$CLIENT_PID" 2>/dev/null
    wait "$CLIENT_PID" 2>/dev/null
    CLIENT_PID=""
    for i in $(seq 1 20); do
        kill -0 "$FAKE_PID" 2>/dev/null || break
        sleep 0.25
    done
    FAKE_PID=""
    SCEN_ISSUED="$issued"
}

# --- scenario 1: happy path (anchor installed, matching serverpubkey) --------
run_scenario happy ok 1
check "registration: client stored MQTTSECRET" \
    $([ -n "$(cfgval MQTTSECRET "$SCEN_HOME")" ]; echo $?) "see $SCRATCH/client-happy.log"
check "registration: stored MQTTSECRET matches the issued secret" \
    $([ "$(cfgval MQTTSECRET "$SCEN_HOME")" = "$(issued_val MQTTSECRET "$SCEN_ISSUED")" ]; echo $?)
check "registration: stored UID" \
    $([ "$(cfgval UID "$SCEN_HOME")" = "$UID_EXPECTED" ]; echo $?)
# The client must present its install UUID (CLUUID): a well-formed UUIDv4,
# persisted in the config DB, and the same value on the wire.
CLUUID=$(cfgval CLUUID "$SCEN_HOME")
check "registration: client sent a UUIDv4" \
    $([[ -n "$CLUUID" && "$CLUUID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$ ]]; echo $?) "cluuid=[$CLUUID]"
check "registration: sent UUID matches stored CLUUID" \
    $([ -n "$CLUUID" ] && [ "$CLUUID" = "$(issued_val UUID "$SCEN_ISSUED")" ]; echo $?)
check "registration: stored MQTTHOST" \
    $([ "$(cfgval MQTTHOST "$SCEN_HOME")" = "$MQTTHOST_EXPECTED" ]; echo $?)
check "registration: stored MQTTPORT" \
    $([ "$(cfgval MQTTPORT "$SCEN_HOME")" = "$MQTTPORT_EXPECTED" ]; echo $?)
check "registration: stored SRVPUB matches the signing certificate key" \
    $([ "$(cfgval SRVPUB "$SCEN_HOME")" = "$(issued_val SRVPUB "$SCEN_ISSUED")" ]; echo $?)
check "registration: config DB mode is 0600" \
    $([ "$(stat -c %a "$SCEN_HOME/config/client.conf.db" 2>/dev/null)" = "600" ]; echo $?)
# Client TLS certificate (protocol §7.1 v1.1): the client generated a P-256
# keypair (config/client.key), presented its CSR in the registration, and
# stored the server-issued certificate (config/client.crt).
check "registration: client sent a TLS CSR" \
    $([ "$(issued_val CSR "$SCEN_ISSUED")" = "yes" ]; echo $?)
check "registration: server issued a certificate for the CSR" \
    $([ "$(issued_val CLIENTCERT "$SCEN_ISSUED")" = "yes" ]; echo $?)
check "registration: client TLS key stored with mode 0600" \
    $([ "$(stat -c %a "$SCEN_HOME/config/client.key" 2>/dev/null)" = "600" ]; echo $?)
check "registration: client certificate stored with mode 0600" \
    $([ "$(stat -c %a "$SCEN_HOME/config/client.crt" 2>/dev/null)" = "600" ]; echo $?)
CRT_SUBJECT=$(openssl x509 -in "$SCEN_HOME/config/client.crt" -noout -subject 2>/dev/null)
check "registration: certificate subject is CN=luminum-client-42" \
    $(echo "$CRT_SUBJECT" | grep -q "CN=luminum-client-42"; echo $?) "subject=[$CRT_SUBJECT]"
check "registration: certificate chains to the server certificate" \
    $(openssl verify -CAfile "$CERTDIR/cert.pem" "$SCEN_HOME/config/client.crt" >/dev/null 2>&1; echo $?)
CRT_PUB=$(openssl x509 -in "$SCEN_HOME/config/client.crt" -noout -pubkey 2>/dev/null | tr -d ' \n')
KEY_PUB=$(openssl pkey -in "$SCEN_HOME/config/client.key" -pubout 2>/dev/null | tr -d ' \n')
check "registration: certificate public key matches the client key" \
    $([ -n "$CRT_PUB" ] && [ "$CRT_PUB" = "$KEY_PUB" ]; echo $?)

# --- scenario 2: serverpubkey mismatch (fatal, nothing stored) ----------------
run_scenario mismatch mismatch 1
check "mismatch: nothing stored (UID)" \
    $([ -z "$(cfgval UID "$SCEN_HOME")" ]; echo $?) "see $SCRATCH/client-mismatch.log"
check "mismatch: nothing stored (MQTTSECRET)" \
    $([ -z "$(cfgval MQTTSECRET "$SCEN_HOME")" ]; echo $?)
check "mismatch: nothing stored (SRVPUB)" \
    $([ -z "$(cfgval SRVPUB "$SCEN_HOME")" ]; echo $?)

# --- scenario 3: no trust anchor (fatal, nothing stored) ----------------------
run_scenario noanchor ok 0
check "noanchor: nothing stored (UID)" \
    $([ -z "$(cfgval UID "$SCEN_HOME")" ]; echo $?) "see $SCRATCH/client-noanchor.log"
check "noanchor: nothing stored (MQTTSECRET)" \
    $([ -z "$(cfgval MQTTSECRET "$SCEN_HOME")" ]; echo $?)
check "noanchor: nothing stored (SRVPUB)" \
    $([ -z "$(cfgval SRVPUB "$SCEN_HOME")" ]; echo $?)

# --- scenario 4: certrenew (registered endpoint, no client certificate) ------
# The fleet upgrade path (protocol §7.1 v1.1): a pre-registered home (UID +
# Ed25519 signing keypair + anchors, but no config/client.crt) starts, the
# client detects the missing certificate, sends a signed certrenew with its
# fingerprint and a fresh TLS CSR, and stores the issued certificate.
SCEN_HOME="$SCRATCH/home-certrenew"
CRT_ISSUED="$SCRATCH/issued-certrenew"
CRT_READY="$SCRATCH/ready-certrenew"
mkdir -p "$SCEN_HOME/config"
# Ed25519 client signing keypair: CLPPRV = base64 32-byte seed, CLPPUB =
# base64 raw public key, FPNT = SHA-256 of the SPKI/DER encoding.
openssl genpkey -algorithm ed25519 -out "$SCRATCH/clsign.key" 2>/dev/null
openssl pkey -in "$SCRATCH/clsign.key" -outform DER 2>/dev/null | tail -c 32 > "$SCRATCH/clsign.seed"
openssl pkey -in "$SCRATCH/clsign.key" -pubout -outform DER 2>/dev/null | tail -c 32 > "$SCRATCH/clsign.pub"
CLPRV=$(base64 -w0 "$SCRATCH/clsign.seed")
CLPUB=$(base64 -w0 "$SCRATCH/clsign.pub")
FPNT=$( { printf '\x30\x2a\x30\x05\x06\x03\x2b\x65\x70\x03\x21\x00'; cat "$SCRATCH/clsign.pub"; } | sha256sum | cut -d' ' -f1 )
python3 - "$SCEN_HOME" "$PORT" <<EOF
import sqlite3, sys
home, port = sys.argv[1], sys.argv[2]
conn = sqlite3.connect(home + "/config/client.conf.db")
conn.execute("create table if not exists CONFIG (KEY text not null, VALUE text not null)")
for k, v in [("SHOST", "127.0.0.1"), ("SPORT", port), ("SVRKEY", "regtest"),
             ("UID", "42"), ("CLPPRV", "$CLPRV"), ("CLPPUB", "$CLPUB"),
             ("FPNT", "$FPNT")]:
    conn.execute("insert into CONFIG (KEY,VALUE) values (?,?)", (k, v))
conn.commit()
EOF
cp "$CERTDIR/cert.pem" "$SCEN_HOME/config/server.crt"
cp "$CERTDIR/signing.crt" "$SCEN_HOME/config/server-signing.crt"

PERL5LIB="$PERL_LIBS" perl "$FAKE" "$PORT" "$CERTDIR/cert.pem" "$CERTDIR/key.pem" \
    "$UID_EXPECTED" "$MQTTHOST_EXPECTED" "$MQTTPORT_EXPECTED" "$CRT_ISSUED" "$CRT_READY" \
    "$CERTDIR/signing.seed" ok &
FAKE_PID=$!
for i in $(seq 1 40); do
    [ -f "$CRT_READY" ] && break
    sleep 0.25
done
check "certrenew: fake server listening" $([ -f "$CRT_READY" ]; echo $?)

LUMINUM_HOME="$SCEN_HOME" "$CLIENT_BIN" > "$SCRATCH/client-certrenew.log" 2>&1 &
CLIENT_PID=$!
# The success marker is the stored certificate file.
for i in $(seq 1 20); do
    [ -f "$SCEN_HOME/config/client.crt" ] && break
    sleep 0.5
done
kill "$CLIENT_PID" 2>/dev/null
wait "$CLIENT_PID" 2>/dev/null
CLIENT_PID=""
for i in $(seq 1 20); do
    kill -0 "$FAKE_PID" 2>/dev/null || break
    sleep 0.25
done
FAKE_PID=""

check "certrenew: client sent a certrenew with a TLS CSR" \
    $([ "$(issued_val ACTION "$CRT_ISSUED")" = "certrenew" ] && [ "$(issued_val CSR "$CRT_ISSUED")" = "yes" ]; echo $?) "see $SCRATCH/client-certrenew.log"
check "certrenew: client stored the issued certificate (0600)" \
    $([ "$(stat -c %a "$SCEN_HOME/config/client.crt" 2>/dev/null)" = "600" ]; echo $?)
CRT_SUBJECT=$(openssl x509 -in "$SCEN_HOME/config/client.crt" -noout -subject 2>/dev/null)
check "certrenew: certificate subject is CN=luminum-client-42" \
    $(echo "$CRT_SUBJECT" | grep -q "CN=luminum-client-42"; echo $?) "subject=[$CRT_SUBJECT]"
check "certrenew: certificate chains to the server certificate" \
    $(openssl verify -CAfile "$CERTDIR/cert.pem" "$SCEN_HOME/config/client.crt" >/dev/null 2>&1; echo $?)
CRT_PUB=$(openssl x509 -in "$SCEN_HOME/config/client.crt" -noout -pubkey 2>/dev/null | tr -d ' \n')
KEY_PUB=$(openssl pkey -in "$SCEN_HOME/config/client.key" -pubout 2>/dev/null | tr -d ' \n')
check "certrenew: certificate public key matches the client key" \
    $([ -n "$CRT_PUB" ] && [ "$CRT_PUB" = "$KEY_PUB" ]; echo $?)

echo "------------------------------------------------------------"
if [ "$FAILURES" -gt 0 ]; then
    echo "FAILED: $FAILURES check(s) failed"
    exit 1
fi
echo "All checks passed."
exit 0
