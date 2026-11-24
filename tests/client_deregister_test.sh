#!/usr/bin/env bash
# Client deregistration test (protocol 6.1, core/unregister): runs the
# client's --deregister against a one-shot fake bootstrap server (TLS +
# length-prefixed frames + Ed25519-signed response, reusing
# Luminum::Protocol so the wire format is exactly the real broker's) and
# verifies:
#   - the client sends a signed unregister request (action, uid, and a
#     signature that verifies against its stored keypair)
#   - on a verified OK the client removes its configuration database
#     (the sanctioned uninstall: the next install is a fresh keypair, UUID,
#     and endpoint record)
#   - on ERR DEACTIVATED (already deregistered server-side) it removes the
#     configuration too - the goal state is already reached
#   - on any other ERR, an unverifiable response signature, or a missing
#     trust anchor it keeps the configuration so the operator can retry
#
# Usage: bash tests/client_deregister_test.sh
set -u
REPO=$(cd "$(dirname "$0")/.." && pwd)
CLIENT_BIN="$REPO/client/linux/target/debug/LuminumClient"
[ -x "$CLIENT_BIN" ] || { echo "SKIP - client binary not built at $CLIENT_BIN"; exit 0; }
[ -x "$(command -v openssl)" ] || { echo "SKIP - openssl not available"; exit 0; }
# Luminum::Protocol lives in the repo; the fake server's non-core modules
# (IO::Socket::SSL, Crypt::Perl::Ed25519) come from the ambient PERL5LIB.
PERL_LIBS="$REPO/server/lib${PERL5LIB:+:$PERL5LIB}"
PERL5LIB="$PERL_LIBS" perl -e \
    'use IO::Socket::SSL; use Crypt::Perl::Ed25519::PrivateKey; use Crypt::Perl::Ed25519::PublicKey; use Luminum::Protocol;' 2>/dev/null \
    || { echo "SKIP - Perl dependencies for the fake bootstrap server are missing"; exit 0; }

PORT=14666
UID_EXPECTED=42

SCRATCH="$HOME/.lumclient-dereg-test.$$"
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
    # Leave the scratch dir (client logs, issued files) behind on failure so
    # the run can be inspected; remove it on success.
    if [ "$FAILURES" -gt 0 ]; then
        echo "Artifacts left in $SCRATCH for inspection."
    else
        rm -rf "$SCRATCH"
    fi
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

# --- server Ed25519 signing key + certificate issued by the TLS certificate ---
openssl genpkey -algorithm ed25519 -out "$CERTDIR/signing.key" 2>/dev/null
openssl req -new -key "$CERTDIR/signing.key" -subj "/CN=127.0.0.1" \
    -out "$CERTDIR/signing.csr" 2>/dev/null
openssl x509 -req -in "$CERTDIR/signing.csr" -CA "$CERTDIR/cert.pem" \
    -CAkey "$CERTDIR/key.pem" -set_serial 0x01 -days 30 \
    -out "$CERTDIR/signing.crt" 2>/dev/null
# PKCS#8 Ed25519 DER is a fixed 48-byte prefix + the 32-byte seed.
openssl pkey -in "$CERTDIR/signing.key" -outform DER 2>/dev/null | tail -c 32 > "$CERTDIR/signing.seed"
[ "$(stat -c %s "$CERTDIR/signing.seed")" = "32" ] || { echo "SKIP - could not derive the signing seed"; exit 0; }

# --- client keypair (stored in the seeded config DB as CLPPRV) ---------------
openssl genpkey -algorithm ed25519 -out "$CERTDIR/client.key" 2>/dev/null
openssl pkey -in "$CERTDIR/client.key" -outform DER 2>/dev/null | tail -c 32 > "$CERTDIR/client.seed"
[ "$(stat -c %s "$CERTDIR/client.seed")" = "32" ] || { echo "SKIP - could not derive the client seed"; exit 0; }
# Ed25519 SPKI/DER is a fixed 12-byte prefix + the 32-byte raw public key.
openssl pkey -in "$CERTDIR/client.key" -pubout -outform DER 2>/dev/null | tail -c 32 > "$CERTDIR/client.pub"
[ "$(stat -c %s "$CERTDIR/client.pub")" = "32" ] || { echo "SKIP - could not derive the client public key"; exit 0; }

# --- one-shot fake bootstrap server ------------------------------------------
# Listens, signals readiness, accepts exactly one connection, reads the
# deregistration frame, verifies it is a signed core/unregister from the
# expected UID (signature checked against the client's stored public key),
# and answers per mode: ok (OK), err (ERR MALFORMED_UID), deactivated
# (ERR DEACTIVATED), badsig (an OK signed with a *different* key, which the
# client must reject). The observed request is written to $ISSUED.
cat > "$FAKE" <<'PERL'
use strict;
use warnings;
use IO::Socket::SSL;
use Luminum::Protocol;

my ($port, $cert, $key, $uid, $issued, $ready, $seedfile, $clientpubfile, $mode) = @ARGV;

open(my $sf, "<", $seedfile) or die "fake server: cannot read seed: $!\n";
binmode($sf);
read($sf, my $seed, 32);
close($sf);
open(my $cf, "<", $clientpubfile) or die "fake server: cannot read client pubkey: $!\n";
binmode($cf);
read($cf, my $clientpub, 32);
close($cf);

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
die "fake server: bad request frame\n" unless $ok;

my $sigok = Luminum::Protocol::verify_envelope($req, $clientpub) ? 1 : 0;

my $status = "OK";
my $err;
if ($mode eq "err") {
    $status = "ERR";
    $err = "MALFORMED_UID";
}
elsif ($mode eq "deactivated") {
    $status = "ERR";
    $err = "DEACTIVATED";
}
my $resp = Luminum::Protocol::new_envelope(
    src => "server",
    uid => $req->{uid},
    lumy => $req->{lumy},
    action => $req->{action},
    status => $status
);
$resp->{err} = $err if defined $err;
if ($mode eq "badsig") {
    # A response signed by a key the client has not validated: the client
    # must reject it and keep its configuration.
    open(my $ur, "<", "/dev/urandom") or die "fake server: urandom: $!\n";
    binmode($ur);
    read($ur, my $otherseed, 32);
    close($ur);
    Luminum::Protocol::sign_envelope($resp, $otherseed);
}
else {
    Luminum::Protocol::sign_envelope($resp, $seed);
}
my $frame = Luminum::Protocol::frame_encode($resp, 64*1024);
$cs->syswrite($frame);
$cs->close();

open(my $out, ">", $issued) or die "fake server: cannot write $issued: $!\n";
print $out "ACTION=", ($req->{action} // ""), "\n";
print $out "LUMY=", ($req->{lumy} // ""), "\n";
print $out "UID=", ($req->{uid} // ""), "\n";
print $out "SIGOK=$sigok\n";
close($out);
PERL

# --- scenario runner ----------------------------------------------------------
# $1 = scenario name, $2 = fake server mode (ok|err|deactivated|badsig),
# $3 = install the signing anchor (1|0). Seeds a fresh registered client
# home, runs one --deregister attempt, and leaves the home in $SCEN_HOME.
SCEN_HOME=""
run_scenario() {
    local name="$1" mode="$2" anchor="$3"
    SCEN_HOME="$SCRATCH/home-$1"
    local issued="$SCRATCH/issued-$1" ready="$SCRATCH/ready-$1"
    mkdir -p "$SCEN_HOME/config"

    python3 - "$SCEN_HOME" "$PORT" "$CERTDIR/client.seed" <<'EOF'
import sqlite3, sys, base64
home, port, seedfile = sys.argv[1], sys.argv[2], sys.argv[3]
seed = open(seedfile, "rb").read()
conn = sqlite3.connect(home + "/config/client.conf.db")
conn.execute("create table if not exists CONFIG (KEY text not null, VALUE text not null)")
for k, v in [("SHOST", "127.0.0.1"), ("SPORT", port), ("SVRKEY", "deregtest"),
             ("UID", "42"),
             ("CLPPRV", base64.b64encode(seed).decode()),
             ("CLUUID", "12345678-1234-4abc-8abc-123456789abc")]:
    conn.execute("insert into CONFIG (KEY,VALUE) values (?,?)", (k, v))
conn.commit()
EOF
    cp "$CERTDIR/cert.pem" "$SCEN_HOME/config/server.crt"
    [ "$anchor" = "1" ] && cp "$CERTDIR/signing.crt" "$SCEN_HOME/config/server-signing.crt"

    PERL5LIB="$PERL_LIBS" perl "$FAKE" "$PORT" "$CERTDIR/cert.pem" "$CERTDIR/key.pem" \
        "$UID_EXPECTED" "$issued" "$ready" \
        "$CERTDIR/signing.seed" "$CERTDIR/client.pub" "$mode" &
    FAKE_PID=$!
    local i
    for i in $(seq 1 40); do
        [ -f "$ready" ] && break
        sleep 0.25
    done
    check "$name: fake server listening" $([ -f "$ready" ]; echo $?)

    # --deregister is one-shot: it exits on its own (0 on success, 1 on
    # failure), so run it in the foreground with a timeout.
    LUMINUM_HOME="$SCEN_HOME" timeout 30 "$CLIENT_BIN" --deregister > "$SCRATCH/client-$1.log" 2>&1
    SCEN_RC=$?
    for i in $(seq 1 20); do
        kill -0 "$FAKE_PID" 2>/dev/null || break
        sleep 0.25
    done
    FAKE_PID=""
    SCEN_ISSUED="$issued"
}

# --- scenario 1: happy path (verified OK removes the configuration) ----------
run_scenario happy ok 1
check "happy: client sent core/unregister" \
    $([ "$(issued_val ACTION "$SCEN_ISSUED")" = "unregister" ]; echo $?) "see $SCRATCH/issued-happy"
check "happy: request carried the stored UID" \
    $([ "$(issued_val UID "$SCEN_ISSUED")" = "$UID_EXPECTED" ]; echo $?)
check "happy: request signature verified against the stored keypair" \
    $([ "$(issued_val SIGOK "$SCEN_ISSUED")" = "1" ]; echo $?)
check "happy: exit status 0" $([ "$SCEN_RC" -eq 0 ]; echo $?) "rc=$SCEN_RC see $SCRATCH/client-happy.log"
check "happy: configuration database removed" \
    $([ ! -e "$SCEN_HOME/config/client.conf.db" ]; echo $?)

# --- scenario 2: already deactivated (ERR DEACTIVATED still uninstalls) ------
run_scenario deactivated deactivated 1
check "deactivated: exit status 0" $([ "$SCEN_RC" -eq 0 ]; echo $?) "rc=$SCEN_RC see $SCRATCH/client-deactivated.log"
check "deactivated: configuration database removed" \
    $([ ! -e "$SCEN_HOME/config/client.conf.db" ]; echo $?)

# --- scenario 3: server error (configuration kept for retry) ------------------
run_scenario err err 1
check "err: exit status 1" $([ "$SCEN_RC" -eq 1 ]; echo $?) "rc=$SCEN_RC see $SCRATCH/client-err.log"
check "err: configuration database kept" \
    $([ -e "$SCEN_HOME/config/client.conf.db" ]; echo $?)
check "err: UID still stored" \
    $([ "$(cfgval UID "$SCEN_HOME")" = "$UID_EXPECTED" ]; echo $?)

# --- scenario 4: unverifiable response signature (configuration kept) --------
run_scenario badsig badsig 1
check "badsig: exit status 1" $([ "$SCEN_RC" -eq 1 ]; echo $?) "rc=$SCEN_RC see $SCRATCH/client-badsig.log"
check "badsig: configuration database kept" \
    $([ -e "$SCEN_HOME/config/client.conf.db" ]; echo $?)

# --- scenario 5: no trust anchor (configuration kept) -------------------------
run_scenario noanchor ok 0
check "noanchor: exit status 1" $([ "$SCEN_RC" -eq 1 ]; echo $?) "rc=$SCEN_RC see $SCRATCH/client-noanchor.log"
check "noanchor: configuration database kept" \
    $([ -e "$SCEN_HOME/config/client.conf.db" ]; echo $?)

echo "------------------------------------------------------------"
if [ "$FAILURES" -gt 0 ]; then
    echo "FAILED: $FAILURES check(s) failed"
    exit 1
fi
echo "All checks passed."
exit 0
