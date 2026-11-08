#!/usr/bin/env bash
# MQTT client control-channel test (protocol 4): runs the client against a
# real Mosquitto broker (one-way TLS, built-in password_file auth, static %u
# ACLs) and verifies the client's MQTT behavior end to end:
#   - connects over TLS and authenticates (password_file)
#   - publishes a signed check-in on the per-UID status topic
#   - receives a server-signed command on each group topic it subscribes to
#     (own UID, all, os/linux, custom group), verifies the signature, and
#     responds on its per-UID resp topic
#   - does NOT respond to a command on a topic it did not subscribe to
#   - publishes a signed offline LWT when killed
#
# The broker worker (server side) is not part of this test; mosquitto_pub,
# running as the server user, stands in for it when issuing commands. Test
# commands are signed with Luminum::Protocol (the same canonicalization the
# Rust client verifies against), so a valid signature is a real check.
#
# Usage: bash tests/mqtt_client_test.sh
set -u
REPO=$(cd "$(dirname "$0")/.." && pwd)
CLIENT_BIN="$REPO/client/linux/target/debug/LuminumClient"
[ -x "$CLIENT_BIN" ] || { echo "SKIP - client binary not built at $CLIENT_BIN"; exit 0; }
[ -x "$(command -v openssl)" ]        || { echo "SKIP - openssl not available"; exit 0; }
[ -x "$(command -v mosquitto)" ]      || { echo "SKIP - mosquitto not available"; exit 0; }
[ -x "$(command -v mosquitto_sub)" ]  || { echo "SKIP - mosquitto_sub not available"; exit 0; }
[ -x "$(command -v mosquitto_pub)" ]  || { echo "SKIP - mosquitto_pub not available"; exit 0; }
[ -x "$(command -v mosquitto_passwd)" ] || { echo "SKIP - mosquitto_passwd not available"; exit 0; }
# Luminum::Protocol lives in the repo; the broker's non-core modules
# (Crypt::Perl::Ed25519) come from the ambient PERL5LIB.
PERL_LIBS="$REPO/server/lib${PERL5LIB:+:$PERL5LIB}"
PERL5LIB="$PERL_LIBS" perl -e \
    'use Crypt::Perl::Ed25519::PrivateKey; use Crypt::Perl::Ed25519::PublicKey; use Luminum::Protocol;' 2>/dev/null \
    || { echo "SKIP - Perl dependencies for signing are missing"; exit 0; }

PORT=18883
SID=1
UID_TEST=42
CLIENT_SECRET="testsecret123"
SERVER_USER="luminum-server"
SERVER_SECRET="serversecret123"
GROUP="testgrp"

SCRATCH="$HOME/.lumclient-mqtt-test.$$"
CERTDIR="$SCRATCH/certs"
HOME_TEST="$SCRATCH/home"
FAILURES=0
MOSQ_PID=""; CLIENT_PID=""; SUB1_PID=""; SUB2_PID=""
CLPPUB_B64=""

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
    [ -n "$CLIENT_PID" ] && kill -9 "$CLIENT_PID" 2>/dev/null
    [ -n "$SUB1_PID" ] && kill "$SUB1_PID" 2>/dev/null
    [ -n "$SUB2_PID" ] && kill "$SUB2_PID" 2>/dev/null
    [ -n "$MOSQ_PID" ] && kill "$MOSQ_PID" 2>/dev/null
    # Leave the scratch dir (client.log, mosquitto.log, status.out, resp.out)
    # behind on failure so the run can be inspected; remove it on success.
    if [ "$FAILURES" -gt 0 ]; then
        echo "Artifacts left in $SCRATCH for inspection."
    else
        rm -rf "$SCRATCH"
    fi
}
trap cleanup EXIT

cfgval() {
    python3 - "$1" "$HOME_TEST" <<'EOF'
import sqlite3, sys
try:
    conn = sqlite3.connect(sys.argv[2] + "/config/client.conf.db")
    row = conn.execute("select VALUE from CONFIG where KEY=?", (sys.argv[1],)).fetchone()
    print(row[0] if row else "")
except Exception:
    print("")
EOF
}

# --- TLS certificate: a CA (trust anchor) + a server leaf it signs -----------
# webpki (the Rust client's rustls) refuses to use a CA:TRUE certificate as the
# presented leaf (CaUsedAsEndEntity), so the broker must present a real leaf
# signed by a separate CA. The client stores the CA as its trust anchor
# (config/server.crt); Mosquitto presents the leaf. The leaf SAN must cover how
# each client verifies the hostname: the Rust client turns the host "127.0.0.1"
# into a DNS name (ServerName::try_from never parses IPs), so it needs a
# DNS:127.0.0.1 entry; the IP:127.0.0.1 entry covers IP-aware clients such as
# mosquitto_sub.
mkdir -p "$CERTDIR" || exit 1
# CA (self-signed, CA:TRUE) - the trust anchor.
openssl req -x509 -newkey rsa:2048 -nodes -days 30 \
    -keyout "$CERTDIR/ca.key" -out "$CERTDIR/ca.pem" \
    -subj "/CN=Luminum Test CA" \
    -addext "basicConstraints=critical,CA:TRUE" \
    -addext "keyUsage=critical,keyCertSign,cRLSign" 2>/dev/null
# Server leaf (CA:FALSE) signed by the CA, with the hostname SANs.
openssl genpkey -algorithm rsa -pkeyopt rsa_keygen_bits:2048 -out "$CERTDIR/tls.key" 2>/dev/null
openssl req -new -key "$CERTDIR/tls.key" -subj "/CN=127.0.0.1" -out "$CERTDIR/tls.csr" 2>/dev/null
cat > "$CERTDIR/tls.ext" <<'EOF'
subjectAltName=DNS:127.0.0.1,IP:127.0.0.1
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
EOF
openssl x509 -req -in "$CERTDIR/tls.csr" -CA "$CERTDIR/ca.pem" -CAkey "$CERTDIR/ca.key" \
    -set_serial 0x01 -days 30 -extfile "$CERTDIR/tls.ext" -out "$CERTDIR/tls.crt" 2>/dev/null
[ -s "$CERTDIR/tls.crt" ] || { echo "SKIP - could not issue the TLS server leaf"; exit 0; }

# --- server Ed25519 signing key (signs the test commands) --------------------
openssl genpkey -algorithm ed25519 -out "$CERTDIR/srv.key" 2>/dev/null
# PKCS#8 Ed25519 DER is a fixed 48-byte prefix + the 32-byte seed.
openssl pkey -in "$CERTDIR/srv.key" -outform DER 2>/dev/null | tail -c 32 > "$CERTDIR/srv.seed"
[ "$(stat -c %s "$CERTDIR/srv.seed")" = "32" ] || { echo "SKIP - could not derive the server signing seed"; exit 0; }
# SRVPUB = base64 of the raw 32-byte public key (what the client stores).
SRVPUB_B64=$(PERL5LIB="$PERL_LIBS" perl -e '
    use Crypt::Perl::Ed25519::PrivateKey; use MIME::Base64;
    open(my $sf, "<", $ARGV[0]) or die "seed: $!"; binmode($sf); read($sf, my $seed, 32); close($sf);
    my $priv = Crypt::Perl::Ed25519::PrivateKey->new($seed);
    print encode_base64($priv->get_public_key()->get_public(), "");
' "$CERTDIR/srv.seed")
[ -n "$SRVPUB_B64" ] || { echo "SKIP - could not derive the server public key"; exit 0; }

# --- client home + pre-seeded config DB --------------------------------------
# UID/SID/MQTT* are pre-seeded so the client skips registration and goes
# straight to the MQTT control channel. CLPPRV/CLPPUB are deliberately absent:
# the client generates its own keypair, and we read CLPPUB back to verify the
# check-in/LWT/response signatures. GROUPS names a custom group the client
# must subscribe to.
mkdir -p "$HOME_TEST/config"
python3 - "$HOME_TEST" "$PORT" "$SRVPUB_B64" <<'EOF'
import sqlite3, sys
home, port, srvpub = sys.argv[1], sys.argv[2], sys.argv[3]
conn = sqlite3.connect(home + "/config/client.conf.db")
conn.execute("create table if not exists CONFIG (KEY text not null, VALUE text not null)")
for k, v in [
    ("UID", "42"), ("SID", "1"),
    ("MQTTSECRET", "testsecret123"), ("MQTTHOST", "127.0.0.1"), ("MQTTPORT", port),
    ("GROUPS", "testgrp"), ("SRVPUB", srvpub),
]:
    conn.execute("insert into CONFIG (KEY,VALUE) values (?,?)", (k, v))
conn.commit()
EOF
chmod 600 "$HOME_TEST/config/client.conf.db"
# The client's MQTT trust anchor is the CA (it verifies the broker's leaf).
cp "$CERTDIR/ca.pem" "$HOME_TEST/config/server.crt"

# --- Mosquitto password_file, acl_file, config --------------------------------
mosquitto_passwd -b -c "$SCRATCH/passwd" "$UID_TEST" "$CLIENT_SECRET"
mosquitto_passwd -b "$SCRATCH/passwd" "$SERVER_USER" "$SERVER_SECRET"

cat > "$SCRATCH/acl" <<EOF
# Per-endpoint topics: each client reads its own cmd, writes its own resp/status/events
pattern read  luminum/$SID/%u/cmd
pattern write luminum/$SID/%u/resp
pattern write luminum/$SID/%u/status
pattern write luminum/$SID/%u/events
# Group topics: readable by any authenticated client (isolation by self-subscription).
# Mosquitto 2.0.x 'topic' ACLs grant the SUBSCRIBE (SUBACK) but never deliver the
# message; only 'pattern' ACLs actually deliver. 'pattern' cannot use +/# wildcards,
# so the OS and group topics are enumerated explicitly here. In production the server
# generates these lines from the known OS values and the group names in the DB.
pattern read  luminum/$SID/all/cmd
pattern read  luminum/$SID/os/linux/cmd
pattern read  luminum/$SID/os/windows/cmd
pattern read  luminum/$SID/os/macos/cmd
pattern read  luminum/$SID/grp/$GROUP/cmd
# Server: unrestricted within the Luminum tree
user $SERVER_USER
topic readwrite luminum/$SID/#
EOF
chmod 600 "$SCRATCH/acl" "$SCRATCH/passwd"

cat > "$SCRATCH/mosquitto.conf" <<EOF
listener $PORT 127.0.0.1
cafile $CERTDIR/ca.pem
certfile $CERTDIR/tls.crt
keyfile $CERTDIR/tls.key
password_file $SCRATCH/passwd
acl_file $SCRATCH/acl
max_packet_size 65536
allow_anonymous false
pid_file $SCRATCH/mosquitto.pid
log_dest file $SCRATCH/mosquitto.log
log_type error
log_type warning
log_type notice
log_type debug
EOF

# --- start Mosquitto ----------------------------------------------------------
mosquitto -c "$SCRATCH/mosquitto.conf" &
MOSQ_PID=$!
ready=1
for i in $(seq 1 40); do
    if (exec 3<>/dev/tcp/127.0.0.1/$PORT) 2>/dev/null; then
        exec 3>&- 3<&- 2>/dev/null
        ready=0
        break
    fi
    sleep 0.25
done
check "Mosquitto is listening on port $PORT" "$ready" "see $SCRATCH/mosquitto.log"
[ "$ready" -eq 0 ] || exit 1

# --- subscribers (run as the server user, which may read status/resp) --------
mosquitto_sub -h 127.0.0.1 -p "$PORT" --cafile "$CERTDIR/ca.pem" \
    -u "$SERVER_USER" -P "$SERVER_SECRET" \
    -t "luminum/$SID/$UID_TEST/status" > "$SCRATCH/status.out" 2>"$SCRATCH/status.err" &
SUB1_PID=$!
mosquitto_sub -h 127.0.0.1 -p "$PORT" --cafile "$CERTDIR/ca.pem" \
    -u "$SERVER_USER" -P "$SERVER_SECRET" \
    -t "luminum/$SID/$UID_TEST/resp" > "$SCRATCH/resp.out" 2>"$SCRATCH/resp.err" &
SUB2_PID=$!
sleep 1

# --- start the client ---------------------------------------------------------
LUMINUM_HOME="$HOME_TEST" LUMINUM_CHECKIN_SECS=2 "$CLIENT_BIN" > "$SCRATCH/client.log" 2>&1 &
CLIENT_PID=$!
sleep 1
check "client process is alive after startup" "$(kill -0 "$CLIENT_PID" 2>/dev/null; echo $?)" "see $SCRATCH/client.log"

# --- wait for a signed check-in on the status topic ---------------------------
CHECKIN=""
for i in $(seq 1 40); do
    if grep -q '"status":"OK"' "$SCRATCH/status.out" 2>/dev/null; then
        CHECKIN=$(grep '"status":"OK"' "$SCRATCH/status.out" | head -n 1)
        break
    fi
    sleep 0.5
done
check "client published a check-in on the status topic" $([ -n "$CHECKIN" ]; echo $?) "see $SCRATCH/client.log"

CLPPUB_B64=$(cfgval CLPPUB)
check "client generated and stored its signing keypair (CLPPUB)" $([ -n "$CLPPUB_B64" ]; echo $?)

# Verify an envelope JSON line: valid signature vs CLPPUB + expected action/status.
# $1 = json line, $2 = expected action, $3 = expected status. Returns 0 on success.
verify_envelope() {
    printf '%s' "$1" | CLPPUB_B64="$CLPPUB_B64" PERL5LIB="$PERL_LIBS" perl -e '
        use strict; use warnings;
        use JSON::PP; use MIME::Base64;
        use Luminum::Protocol;
        my ($action, $status) = @ARGV;
        local $/; my $json = <STDIN>;
        my $env = eval { JSON::PP->new->utf8->decode($json) };
        exit 1 unless ref($env) eq "HASH";
        my $clpub = decode_base64($ENV{CLPPUB_B64});
        exit 1 unless length($clpub) == 32;
        exit 1 unless Luminum::Protocol::verify_envelope($env, $clpub);
        exit 1 unless ($env->{action} // "") eq $action;
        exit 1 unless ($env->{status} // "") eq $status;
        exit 0;
    ' "$2" "$3"
}
if [ -n "$CHECKIN" ]; then
    verify_envelope "$CHECKIN" checkin OK
    check "check-in is a valid signed envelope (action=checkin, status=OK)" "$?"
fi

# --- sign a server command and publish it to a topic --------------------------
# $1 = action, $2 = topic. Signs with the server key (Luminum::Protocol) and
# publishes as the server user.
sign_and_pub() {
    local action="$1" topic="$2" payload
    payload=$(PERL5LIB="$PERL_LIBS" perl -e '
        use strict; use warnings;
        use JSON::PP;
        use Crypt::Perl::Ed25519::PrivateKey;
        use Luminum::Protocol;
        my ($seedfile, $uid, $action) = @ARGV;
        open(my $sf, "<", $seedfile) or die "seed: $!"; binmode($sf); read($sf, my $seed, 32); close($sf);
        my $env = Luminum::Protocol::new_envelope(src=>"server", uid=>$uid, lumy=>"core", action=>$action, status=>"OK");
        Luminum::Protocol::sign_envelope($env, $seed);
        print JSON::PP->new->utf8->encode($env);
    ' "$CERTDIR/srv.seed" "$UID_TEST" "$action") || return 1
    mosquitto_pub -h 127.0.0.1 -p "$PORT" --cafile "$CERTDIR/ca.pem" \
        -u "$SERVER_USER" -P "$SERVER_SECRET" -t "$topic" -m "$payload"
}

# Wait for a response with the given action on the resp topic; verify it.
# $1 = action. Returns 0 if a valid signed response arrived.
await_resp() {
    local action="$1" resp
    for i in $(seq 1 30); do
        resp=$(grep "\"action\":\"$action\"" "$SCRATCH/resp.out" 2>/dev/null | head -n 1)
        [ -n "$resp" ] && break
        sleep 0.5
    done
    [ -n "$resp" ] || return 1
    verify_envelope "$resp" "$action" OK
}

# --- group command round trips ------------------------------------------------
# Each of the topics the client subscribes to must deliver a signed command
# that the client verifies and acknowledges on its resp topic.
sign_and_pub queryall  "luminum/$SID/all/cmd"
await_resp queryall
check "client verified + responded to a command on all/cmd" "$?"

sign_and_pub queryos   "luminum/$SID/os/linux/cmd"
await_resp queryos
check "client verified + responded to a command on os/linux/cmd" "$?"

sign_and_pub querygrp  "luminum/$SID/grp/$GROUP/cmd"
await_resp querygrp
check "client verified + responded to a command on grp/$GROUP/cmd" "$?"

sign_and_pub queryuid  "luminum/$SID/$UID_TEST/cmd"
await_resp queryuid
check "client verified + responded to a command on its own UID cmd topic" "$?"

# --- negative: a topic the client did not subscribe to ------------------------
sign_and_pub querywin "luminum/$SID/os/windows/cmd"
sleep 3
# The client must NOT have responded to the unsubscribed topic. grep -q prints
# nothing, so capture its status into a variable (an unquoted $(! grep ...)
# expands to empty and drops the argument, tripping set -u on $2).
negfail=0
grep -q '"action":"querywin"' "$SCRATCH/resp.out" 2>/dev/null && negfail=1
check "client did NOT respond to a command on an unsubscribed topic (os/windows)" "$negfail"

# --- LWT: kill the client, expect a signed offline envelope -------------------
kill -9 "$CLIENT_PID" 2>/dev/null
CLIENT_PID=""
LWT=""
for i in $(seq 1 40); do
    if grep -q '"status":"offline"' "$SCRATCH/status.out" 2>/dev/null; then
        LWT=$(grep '"status":"offline"' "$SCRATCH/status.out" | head -n 1)
        break
    fi
    sleep 0.5
done
check "client published an offline LWT on death" $([ -n "$LWT" ]; echo $?) "see $SCRATCH/mosquitto.log"
if [ -n "$LWT" ]; then
    verify_envelope "$LWT" checkin offline
    check "LWT is a valid signed offline envelope (action=checkin, status=offline)" "$?"
fi

echo "------------------------------------------------------------"
if [ "$FAILURES" -gt 0 ]; then
    echo "FAILED: $FAILURES check(s) failed"
    echo "Artifacts left in $SCRATCH for inspection (client.log, mosquitto.log, status.out, resp.out)"
    exit 1
fi
echo "All checks passed."
exit 0
