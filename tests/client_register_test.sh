#!/usr/bin/env bash
# Client registration test: runs the client against a one-shot fake
# bootstrap server (TLS + length-prefixed frames + Ed25519-signed
# response, reusing Luminum::Protocol so the wire format is exactly
# the real broker's) and verifies the client stores UID, SRVPUB,
# MQTTSECRET, MQTTHOST, and MQTTPORT from the signed registration
# response (protocol 7.1).
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
LUMY_HOME="$SCRATCH/home"
FAKE="$SCRATCH/fakeserver.pl"
ISSUED="$SCRATCH/issued"
READY="$SCRATCH/ready"
CLIENT_PID=""
FAKE_PID=""
FAILURES=0
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
    grep "^$1=" "$ISSUED" 2>/dev/null | head -n 1 | cut -d= -f2-
}

# --- TLS certificate valid for 127.0.0.1 (the client verifies the hostname) ---
mkdir -p "$CERTDIR" "$LUMY_HOME/config" || exit 1
openssl req -x509 -newkey rsa:2048 -nodes -days 30 \
    -keyout "$CERTDIR/key.pem" -out "$CERTDIR/cert.pem" \
    -subj "/CN=127.0.0.1" -addext "subjectAltName=IP:127.0.0.1" 2>/dev/null

# --- one-shot fake bootstrap server ------------------------------------------
# Listens, signals readiness, accepts exactly one connection, reads the
# registration frame, and answers with a signed OK response carrying the
# MQTT credentials. The issued values are written to $ISSUED for the
# test to compare against the client's config DB.
cat > "$FAKE" <<'PERL'
use strict;
use warnings;
use IO::Socket::SSL;
use MIME::Base64;
use Crypt::Perl::Ed25519::PrivateKey;
use Luminum::Protocol;

my ($port, $cert, $key, $uid, $mqtthost, $mqttport, $issued, $ready) = @ARGV;

my $priv = Crypt::Perl::Ed25519::PrivateKey->new();
my $seed = $priv->get_private();
my $pubraw = $priv->get_public_key()->get_public();
my $spki_b64 = encode_base64(Luminum::Protocol::raw_to_spki($pubraw), "");

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
die "fake server: bad request frame\n" unless $ok && ($req->{action} // "") eq "register";

my $resp = Luminum::Protocol::new_envelope(
    src => "server",
    uid => $req->{uid},
    lumy => $req->{lumy},
    action => $req->{action},
    status => "OK"
);
$resp->{data} = {
    uid => $uid,
    mqtthost => $mqtthost,
    mqttport => $mqttport,
    mqttsecret => $secret,
    serverpubkey => $spki_b64,
};
Luminum::Protocol::sign_envelope($resp, $seed);
my $frame = Luminum::Protocol::frame_encode($resp, 64*1024);
$cs->syswrite($frame);
$cs->close();

open(my $out, ">", $issued) or die "fake server: cannot write $issued: $!\n";
print $out "UID=$uid\n";
print $out "MQTTSECRET=$secret\n";
print $out "MQTTHOST=$mqtthost\n";
print $out "MQTTPORT=$mqttport\n";
print $out "SRVPUB=", encode_base64($pubraw, ""), "\n";
close($out);
PERL

# --- seed the client config (no UID: registration is triggered) ---------------
python3 - "$LUMY_HOME" "$PORT" <<'EOF'
import sqlite3, sys
home, port = sys.argv[1], sys.argv[2]
conn = sqlite3.connect(home + "/config/client.conf.db")
conn.execute("create table if not exists CONFIG (KEY text not null, VALUE text not null)")
for k, v in [("SHOST", "127.0.0.1"), ("SPORT", port), ("SVRKEY", "regtest")]:
    conn.execute("insert into CONFIG (KEY,VALUE) values (?,?)", (k, v))
conn.commit()
EOF
cp "$CERTDIR/cert.pem" "$LUMY_HOME/config/server.crt"

# --- start the fake server, wait for readiness, start the client ---------------
PERL5LIB="$PERL_LIBS" perl "$FAKE" "$PORT" "$CERTDIR/cert.pem" "$CERTDIR/key.pem" \
    "$UID_EXPECTED" "$MQTTHOST_EXPECTED" "$MQTTPORT_EXPECTED" "$ISSUED" "$READY" &
FAKE_PID=$!
ready=1
for _ in $(seq 1 40); do
    [ -f "$READY" ] && { ready=0; break; }
    sleep 0.25
done
check "fake server: listening" $ready

LUMINUM_HOME="$LUMY_HOME" "$CLIENT_BIN" > "$SCRATCH/client.log" 2>&1 &
CLIENT_PID=$!

# --- wait for the registration to land in the config DB ------------------------
found=1
for _ in $(seq 1 30); do
    [ -n "$(cfgval MQTTSECRET "$LUMY_HOME")" ] && { found=0; break; }
    sleep 0.5
done
check "registration: client stored MQTTSECRET" $found "see $SCRATCH/client.log"

kill "$CLIENT_PID" 2>/dev/null
wait "$CLIENT_PID" 2>/dev/null
CLIENT_PID=""
for _ in $(seq 1 20); do
    kill -0 "$FAKE_PID" 2>/dev/null || break
    sleep 0.25
done

# --- verify the stored values against what the server issued --------------------
check "registration: stored MQTTSECRET matches the issued secret" \
    $([ "$(cfgval MQTTSECRET "$LUMY_HOME")" = "$(issued_val MQTTSECRET)" ]; echo $?)
check "registration: stored UID" $([ "$(cfgval UID "$LUMY_HOME")" = "$UID_EXPECTED" ]; echo $?)
check "registration: stored MQTTHOST" $([ "$(cfgval MQTTHOST "$LUMY_HOME")" = "$MQTTHOST_EXPECTED" ]; echo $?)
check "registration: stored MQTTPORT" $([ "$(cfgval MQTTPORT "$LUMY_HOME")" = "$MQTTPORT_EXPECTED" ]; echo $?)
check "registration: stored SRVPUB matches the server signing key" \
    $([ "$(cfgval SRVPUB "$LUMY_HOME")" = "$(issued_val SRVPUB)" ]; echo $?)
check "registration: config DB mode is 0600" \
    $([ "$(stat -c %a "$LUMY_HOME/config/client.conf.db" 2>/dev/null)" = "600" ]; echo $?)

echo "------------------------------------------------------------"
if [ "$FAILURES" -gt 0 ]; then
    echo "FAILED: $FAILURES check(s) failed"
    exit 1
fi
echo "All checks passed."
exit 0
