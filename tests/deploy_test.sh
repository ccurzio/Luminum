#!/usr/bin/env bash
# Deployment proof (protocol 4, 7, 9): runs the real installer into a fresh
# root against an isolated MariaDB, starts mosquitto + the broker (which forks
# the MQTT worker), and drives a freshly-registered client end to end:
#   - register over the direct channel (10465)
#   - consume the MQTT creds (uid/sid/mqtthost/mqttport/mqttsecret/serverpubkey)
#     from the signed registration response -- no pre-seeded config
#   - connect to mosquitto (8883) over TLS
#   - check-ins update CLIENTS.STATUS via the worker
#   - a COMMANDS outbox row is published by the worker, verified by the client,
#     and marked ACKED on the client's response
#   - the web console (nginx + php-fpm) serves the logged-in admin: the
#     unauthenticated API is rejected (401), the login issues a session, and
#     /api/clients.php + the Client Status page show the registered client
#
# This proves the whole installer -> broker -> mosquitto -> client -> console
# path, which the isolated scratch tests (mqtt_client_test.sh,
# mqtt_worker_test.sh) do not cover because they pre-seed the client config
# and stand in for the broker.
#
# The installer uses fixed database names (SYSTEM/CLIENTS/...), so this test
# runs it against a throwaway MariaDB to avoid clobbering the dev install.
#
# Usage: bash tests/deploy_test.sh
set -u
REPO=$(cd "$(dirname "$0")/.." && pwd)
CLIENT_BIN="$REPO/client/linux/target/debug/LuminumClient"
SETUP="$REPO/server/setup.pl"
PERL_LIBS="$REPO/server/lib${PERL5LIB:+:$PERL5LIB}"
# The installer requires root; this test drives it as an unprivileged
# user, so use the test escape hatch.
export LUMINUM_SETUP_ALLOW_NONROOT=1

# --- prerequisites -----------------------------------------------------------
[ -x "$CLIENT_BIN" ] || { echo "SKIP - client binary not built at $CLIENT_BIN"; exit 0; }
[ -x "$(command -v mosquitto)" ]          || { echo "SKIP - mosquitto not available"; exit 0; }
[ -x "$(command -v mariadbd)" ]           || { echo "SKIP - mariadbd not available"; exit 0; }
[ -x "$(command -v mariadb-install-db)" ] || { echo "SKIP - mariadb-install-db not available"; exit 0; }
[ -x "$(command -v openssl)" ]            || { echo "SKIP - openssl not available"; exit 0; }
PERL5LIB="$PERL_LIBS" perl -e 'use Luminum::Setup; use Luminum::MQTT;' 2>/dev/null \
    || { echo "SKIP - Perl dependencies for the installer/worker are missing"; exit 0; }

# --- scratch layout (all under one dir, removed on clean exit) ---------------
RUN="$HOME/.lumdeploy-test.$$"
DBDIR="$RUN/mariadb"
DBSOCK="$RUN/mysqld.sock"
DBPORT=33071
ROOT="$RUN/install"
HOME_TEST="$RUN/clienthome"
LPORT=10465
WPORT=8443
MPORT=8883
SHOST=127.0.0.1
LADDR=127.0.0.1
ADMINPASS="consolepass123"
BLOG="$ROOT/log/broker.log"
FAILURES=0
MARIADB_PID=""; MOSQ_PID=""; BROKER_PID=""; CLIENT_PID=""

check() {
    local name="$1" ok="$2" detail="${3:-}"
    if [ "$ok" -eq 0 ]; then
        echo "ok   - $name"
    else
        FAILURES=$((FAILURES + 1))
        echo "FAIL - $name${detail:+ ($detail)}"
    fi
}

dbq() {
    mysql --socket="$DBSOCK" -u root -N -e "$1" 2>/dev/null
}

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

cleanup() {
    [ -n "$CLIENT_PID" ] && kill -9 "$CLIENT_PID" 2>/dev/null
    # Web console first (nginx, then php-fpm via the generated stop script).
    [ -x "$ROOT/bin/stop-web" ] && "$ROOT/bin/stop-web" >/dev/null 2>&1
    if [ -n "$BROKER_PID" ]; then "$ROOT/bin/stop-broker" 2>/dev/null; kill "$BROKER_PID" 2>/dev/null; fi
    if [ -n "$MOSQ_PID" ]; then "$ROOT/bin/stop-mosquitto" 2>/dev/null; kill "$MOSQ_PID" 2>/dev/null; fi
    if [ -n "$MARIADB_PID" ]; then
        mysqladmin --socket="$DBSOCK" -u root shutdown 2>/dev/null
        kill "$MARIADB_PID" 2>/dev/null
    fi
    if [ "$FAILURES" -gt 0 ]; then
        echo "Artifacts left in $RUN for inspection."
    else
        rm -rf "$RUN"
    fi
}
trap cleanup EXIT

mkdir -p "$RUN" || exit 1

# --- isolated MariaDB (fresh datadir; keeps the proof off the dev install) ---
mariadb-install-db --datadir="$DBDIR" --auth-root-authentication-method=normal \
    > "$RUN/mariadb-init.log" 2>&1 \
    || { echo "SKIP - could not initialize the isolated MariaDB"; exit 0; }
mariadbd --datadir="$DBDIR" --socket="$DBSOCK" --port=$DBPORT \
    --pid-file="$RUN/mariadb.pid" > "$RUN/mariadb.log" 2>&1 &
MARIADB_PID=$!
ready=1
for i in $(seq 1 60); do [ -S "$DBSOCK" ] && { ready=0; break; }; sleep 0.25; done
check "isolated MariaDB is up" "$ready" "see $RUN/mariadb.log"
[ "$ready" -eq 0 ] || exit 1

# --- run the installer (provision only; services are started manually) -------
PERL5LIB="$PERL_LIBS" perl "$SETUP" --noninteractive --yes --no-start \
    --install-root "$ROOT" \
    --shost "$SHOST" --laddr "$LADDR" --lport $LPORT --wport $WPORT \
    --dbsocket "$DBSOCK" --dbadmin root \
    --adminpass "$ADMINPASS" \
    --perl5lib "$PERL_LIBS" \
    --srcdir "$REPO/server" \
    > "$RUN/setup.log" 2>&1
check "installer completed (provisioning)" $([ $? -eq 0 ]; echo $?) "see $RUN/setup.log"

# --- verify the installer's mosquitto provisioning ---------------------------
check "mosquitto.conf was generated" $([ -s "$ROOT/config/mosquitto/mosquitto.conf" ]; echo $?)
check "mosquitto TLS leaf was generated" $([ -s "$ROOT/config/ssl/mosquitto.crt" ]; echo $?)
openssl verify -CAfile "$ROOT/config/ssl/server.crt" "$ROOT/config/ssl/mosquitto.crt" >/dev/null 2>&1
check "mosquitto leaf chains to the server certificate" "$?"
openssl x509 -in "$ROOT/config/ssl/mosquitto.crt" -noout -ext subjectAltName 2>/dev/null | grep -q "DNS:127.0.0.1"
check "mosquitto leaf has a DNS SAN for the IP host" "$?"
check "start-mosquitto script was generated" $([ -x "$ROOT/bin/start-mosquitto" ]; echo $?)
check "start-broker script was generated" $([ -x "$ROOT/bin/start-broker" ]; echo $?)

# --- start mosquitto, then the broker (which forks the worker) ---------------
# Fail fast if something else already holds the MQTT port: a stale mosquitto
# from a previous run would otherwise serve its (old) certificates and the test
# would pass/fail against the wrong broker.
if (exec 3<>/dev/tcp/127.0.0.1/$MPORT) 2>/dev/null; then
    exec 3>&- 3<&- 2>/dev/null
    echo "FAIL - port $MPORT is already in use; stop the stale mosquitto and re-run"
    exit 1
fi
"$ROOT/bin/start-mosquitto" > "$RUN/start-mosq.log" 2>&1
mosq_up=1
for i in $(seq 1 20); do
    if (exec 3<>/dev/tcp/127.0.0.1/$MPORT) 2>/dev/null; then exec 3>&- 3<&- 2>/dev/null; mosq_up=0; break; fi
    sleep 0.5
done
# The pid_file and log live in the system-standard locations on root
# installs and in the install tree otherwise; take both from the
# generated mosquitto.conf.
MOSQ_PIDFILE=$(awk '/^pid_file/ {print $2}' "$ROOT/config/mosquitto/mosquitto.conf")
MOSQ_LOG=$(awk '/^log_dest/ {print $3}' "$ROOT/config/mosquitto/mosquitto.conf")
check "mosquitto is listening on $MPORT" "$mosq_up" "see $MOSQ_LOG"
[ "$mosq_up" -eq 0 ] || exit 1
# Track the mosquitto PID (from its pid_file) so cleanup can stop it
# even if the install tree is later removed.
MOSQ_PID=$(cat "$MOSQ_PIDFILE" 2>/dev/null)

"$ROOT/bin/start-broker" > "$RUN/start-broker.log" 2>&1
broker_up=1
for i in $(seq 1 30); do
    if (exec 3<>/dev/tcp/127.0.0.1/$LPORT) 2>/dev/null; then exec 3>&- 3<&- 2>/dev/null; broker_up=0; break; fi
    sleep 0.5
done
check "broker is listening on $LPORT" "$broker_up" "see $BLOG"
[ "$broker_up" -eq 0 ] || exit 1
BROKER_PID=$(cat "$ROOT/run/broker.pid" 2>/dev/null)

# The worker is forked by the broker (startmqtt); the parent logs its PID.
WORKER_PID=""
for i in $(seq 1 20); do
    WORKER_PID=$(grep -o 'MQTT worker started (PID [0-9]*)' "$BLOG" 2>/dev/null | grep -o '[0-9]*' | head -n1)
    [ -n "$WORKER_PID" ] && break
    sleep 0.5
done
check "broker forked the MQTT worker" $([ -n "$WORKER_PID" ]; echo $?) "see $BLOG"
worker_alive=1
[ -n "$WORKER_PID" ] && kill -0 "$WORKER_PID" 2>/dev/null && worker_alive=0
check "MQTT worker process is alive" "$worker_alive"
wp_parent=$(ps -o ppid= -p "${WORKER_PID:-0}" 2>/dev/null | tr -d ' ')
check "MQTT worker is a child of the broker" $([ "$wp_parent" = "$BROKER_PID" ]; echo $?)

# --- fresh client home, provisioned out of band (as on a real endpoint): the
# --- server generates config.ini from its own installed state (mkprovision.pl)
# --- and the client imports it. NO pre-seeded UID/MQTT* (so registration must
# --- supply them); the SKEY + trust anchors come from the generated file.
SKEY=$(dbq "select CVAL from SYSTEM.CONFIG where CKEY='SKEY';")
check "installer generated an SKEY" $([ -n "$SKEY" ]; echo $?)
PERL5LIB="$PERL_LIBS" perl "$ROOT/mkprovision.pl" --out "$RUN/config.ini" > "$RUN/mkprov.log" 2>&1
check "mkprovision.pl generated config.ini" $([ -s "$RUN/config.ini" ]; echo $?) "see $RUN/mkprov.log"
python3 - "$RUN/config.ini" "$SKEY" "$LPORT" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["server"]["key"] == sys.argv[2], "SKEY mismatch in generated file"
assert d["server"]["port"] == int(sys.argv[3]), "port mismatch in generated file"
assert "BEGIN CERTIFICATE" in d["certificates"]["server"], "server cert missing"
assert "BEGIN CERTIFICATE" in d["certificates"]["signing"], "signing cert missing"
EOF
check "config.ini carries the SKEY, port, and both certificates" $?
LUMINUM_HOME="$HOME_TEST" "$CLIENT_BIN" --import "$RUN/config.ini" > "$RUN/import.log" 2>&1
check "client imported config.ini" $([ $? -eq 0 ]; echo $?) "see $RUN/import.log"
check "imported SHOST matches the server" $([ "$(cfgval SHOST)" = "$SHOST" ]; echo $?)
check "imported SVRKEY matches the SKEY" $([ "$(cfgval SVRKEY)" = "$SKEY" ]; echo $?)
check "imported server.crt present" $([ -f "$HOME_TEST/config/server.crt" ]; echo $?)
check "imported server-signing.crt present" $([ -f "$HOME_TEST/config/server-signing.crt" ]; echo $?)

# The client binds IPC (10461) and the data channel (10704); both must be free.
port_busy=0
for p in 10461 10704; do
    if (exec 3<>/dev/tcp/127.0.0.1/$p) 2>/dev/null; then exec 3>&- 3<&- 2>/dev/null; port_busy=1; fi
done
check "client IPC/data ports are free" "$port_busy" "port 10461 or 10704 in use"

# Pre-seed the client's out-queue with an event that was "queued while
# offline" (protocol §9.1). On its first MQTT connect the client must flush it
# to the per-UID events topic and mark the row SENT. The UID is filled in by
# the client at drain time, so only the module/action/payload are pre-set.
python3 - "$HOME_TEST" <<'EOF'
import os, sqlite3, sys, time
home = sys.argv[1]
os.makedirs(home + "/config", exist_ok=True)
conn = sqlite3.connect(home + "/config/outqueue.db")
conn.execute("create table if not exists OUTQUEUE ( ID integer primary key autoincrement, TS integer not null, LUMY text not null, ACTION text not null, PAYLOAD text not null, SENT integer not null default 0 )")
conn.execute("insert into OUTQUEUE (TS, LUMY, ACTION, PAYLOAD) values (?,?,?,?)",
    (int(time.time()), "integrity", "alert", '{"file":"/etc/passwd","change":"modified"}'))
conn.commit(); conn.close()
EOF

# --- run the client (registers, then opens the MQTT control channel) ---------
LUMINUM_HOME="$HOME_TEST" LUMINUM_CHECKIN_SECS=2 "$CLIENT_BIN" -d > "$RUN/client.log" 2>&1 &
CLIENT_PID=$!

# --- registration: a UID is assigned and the client stores the MQTT creds ----
SID=$(dbq "select CVAL from SYSTEM.CONFIG where CKEY='SID';")
check "installer generated a SID" $([ -n "$SID" ]; echo $?)
UID_C=""
for i in $(seq 1 40); do
    UID_C=$(dbq "select ID from CLIENTS.STATUS order by ID desc limit 1;")
    [ -n "$UID_C" ] && break
    sleep 0.5
done
check "client registered (a UID was assigned)" $([ -n "$UID_C" ]; echo $?) "see $RUN/client.log"

# The client was NOT pre-seeded with these; they must come from the signed
# registration response.
check "client stored UID from the registration response" $([ "$(cfgval UID)" = "$UID_C" ]; echo $?) "see $RUN/client.log"
check "client stored SID from the registration response" $([ "$(cfgval SID)" = "$SID" ]; echo $?)
check "client stored MQTTSECRET from the registration response" $([ -n "$(cfgval MQTTSECRET)" ]; echo $?)
check "client stored MQTTHOST from the registration response" $([ "$(cfgval MQTTHOST)" = "$LADDR" ]; echo $?)
check "client stored MQTTPORT from the registration response" $([ "$(cfgval MQTTPORT)" = "$MPORT" ]; echo $?)
check "client stored SRVPUB from the registration response" $([ -n "$(cfgval SRVPUB)" ]; echo $?)

# --- MQTT: the client connects and its check-in updates STATUS via the worker
conn_ok=1
for i in $(seq 1 40); do
    grep -q "MQTT connected" "$RUN/client.log" 2>/dev/null && { conn_ok=0; break; }
    sleep 0.5
done
check "client connected to mosquitto over TLS" "$conn_ok" "see $RUN/client.log"

# --- out-queue drain: the event queued while offline is flushed on connect ----
# The client drained its out-queue on the first ConnAck (protocol §9.1); the
# worker logged the event, and the row is now marked SENT.
ev_ok=1
for i in $(seq 1 40); do
    grep -q "events: UID $UID_C alert OK" "$BLOG" 2>/dev/null && { ev_ok=0; break; }
    sleep 0.5
done
check "out-queue: queued event flushed to the events topic" "$ev_ok" "see $BLOG"
SENT=$(python3 - "$HOME_TEST" <<'EOF'
import sqlite3, sys
try:
    c = sqlite3.connect(sys.argv[1] + "/config/outqueue.db")
    print(c.execute("select count(*) from OUTQUEUE where SENT = 1").fetchone()[0])
except Exception:
    print(0)
EOF
)
check "out-queue: flushed event marked SENT" $([ "$SENT" -ge 1 ]; echo $?) "sent=$SENT"

checkin_ok=1
for i in $(seq 1 40); do
    grep -q "\[mqtt\] status: UID $UID_C OK" "$BLOG" 2>/dev/null && { checkin_ok=0; break; }
    sleep 0.5
done
check "worker processed the client's MQTT check-in" "$checkin_ok" "see $BLOG"
cstate=$(dbq "select CSTATE from CLIENTS.STATUS where ID=$UID_C;")
check "STATUS.CSTATE is OK" $([ "$cstate" = "OK" ]; echo $?) "got: $cstate"

# --- check-in interval sync (protocol 7.2) -----------------------------------
# The client started with LUMINUM_CHECKIN_SECS=2 and no persisted value, so
# its check-ins report 2s against the server's CHECKININT=5 (300s); the
# worker must push core/setcheckinint and the client must persist and apply it.
push_ok=1
for i in $(seq 1 40); do
    grep -q "pushed setcheckinint" "$BLOG" 2>/dev/null && { push_ok=0; break; }
    sleep 0.5
done
check "worker pushed the server check-in interval (setcheckinint)" "$push_ok" "see $BLOG"
check "client persisted the pushed interval (CHECKIN_SECS=300)" $([ "$(cfgval CHECKIN_SECS)" = "300" ]; echo $?) "got: $(cfgval CHECKIN_SECS)"
intack_ok=1
for i in $(seq 1 40); do
    grep -q "resp: UID $UID_C response (core/setcheckinint)" "$BLOG" 2>/dev/null && { intack_ok=0; break; }
    sleep 0.5
done
check "client acked the interval push" "$intack_ok" "see $BLOG"

# Admin changes the interval: the worker reads CHECKININT live, so no broker
# restart is needed. Restart the client - it must start from the persisted
# 300s (not the 2s env override) and its next check-in must trigger a push of
# the new value (1 min = 60s).
dbq "update SYSTEM.CONFIG set CVAL='1' where CKEY='CHECKININT';"
kill "$CLIENT_PID" 2>/dev/null
wait "$CLIENT_PID" 2>/dev/null
LUMINUM_HOME="$HOME_TEST" LUMINUM_CHECKIN_SECS=2 "$CLIENT_BIN" -d >> "$RUN/client.log" 2>&1 &
CLIENT_PID=$!
push2_ok=1
for i in $(seq 1 60); do
    grep -q "client 300s, server 60s" "$BLOG" 2>/dev/null && { push2_ok=0; break; }
    sleep 0.5
done
check "admin change propagated on the client's next check-in (300s -> 60s)" "$push2_ok" "see $BLOG"
check "client persisted the changed interval (CHECKIN_SECS=60)" $([ "$(cfgval CHECKIN_SECS)" = "60" ]; echo $?) "got: $(cfgval CHECKIN_SECS)"

# --- command round trip: outbox -> worker publish -> client -> resp -> ACKED
QID=$(python3 -c 'import uuid;print(uuid.uuid4())')
dbq "insert into CLIENTS.COMMANDS (SID,TARGET,LUMY,ACTION,QID,STATUS,CREATED) values ('$SID','$UID_C','core','deploytest','$QID','PENDING',now());"
ack_ok=1
for i in $(seq 1 60); do
    st=$(dbq "select STATUS from CLIENTS.COMMANDS where QID='$QID';")
    [ "$st" = "ACKED" ] && { ack_ok=0; break; }
    sleep 0.5
done
check "outbox command round-tripped to ACKED" "$ack_ok" "final status: $(dbq "select STATUS from CLIENTS.COMMANDS where QID='$QID';")"

# --- web console: nginx + php-fpm serve the logged-in admin -------------------
# The generated start-web script brings up php-fpm (socket) then nginx (TLS on
# WPORT) with the installer's console configuration.
"$ROOT/bin/start-web" > "$RUN/start-web.log" 2>&1
web_up=1
for i in $(seq 1 20); do
    if (exec 3<>/dev/tcp/127.0.0.1/$WPORT) 2>/dev/null; then exec 3>&- 3<&- 2>/dev/null; web_up=0; break; fi
    sleep 0.5
done
check "web console is listening on $WPORT" "$web_up" "see $RUN/start-web.log"
[ "$web_up" -eq 0 ] || exit 1

# The API auth gate requires a live console session: anonymous access is a 401.
code=$(curl -k -s -o "$RUN/api-anon.json" -w '%{http_code}' "https://127.0.0.1:$WPORT/api/clients.php")
check "api: unauthenticated request rejected (401)" $([ "$code" = "401" ]; echo $?) "got: $code"

# Log in as the console admin (lumadmin / the --adminpass value) over the real
# login flow; the PHP session cookie is what the API auth gate validates.
code=$(curl -k -s -o "$RUN/login.html" -w '%{http_code}' -c "$RUN/cookies" \
    --data "username=lumadmin&password=$ADMINPASS" "https://127.0.0.1:$WPORT/index.php")
check "login: POST to index.php succeeds (200)" $([ "$code" = "200" ]; echo $?) "got: $code"
check "login: PHP session cookie issued" \
    $(grep -q "PHPSESSID" "$RUN/cookies" 2>/dev/null; echo $?)
check "login: session row recorded in AUTH.SESSION" \
    $([ "$(dbq "select count(*) from AUTH.SESSION;")" -ge 1 ]; echo $?)

# The Client Status API must show the client that registered and checked in
# above, with the hostname and state the worker wrote to CLIENTS.STATUS.
HOST_DB=$(dbq "select HOSTNAME from CLIENTS.STATUS where ID=$UID_C;")
code=$(curl -k -s -o "$RUN/api-clients.json" -w '%{http_code}' -b "$RUN/cookies" \
    "https://127.0.0.1:$WPORT/api/clients.php")
check "api: authenticated clients.php returns 200" $([ "$code" = "200" ]; echo $?) "got: $code"
python3 - "$RUN/api-clients.json" "$UID_C" "$HOST_DB" <<'EOF'
import json, sys
data = json.load(open(sys.argv[1]))
uid, host = int(sys.argv[2]), sys.argv[3]
row = next((r for r in data["rows"] if r["id"] == uid), None)
assert row is not None, "client row missing from API response"
assert row["hostname"] == host, "hostname mismatch: %r != %r" % (row["hostname"], host)
assert row["state"] == "OK", "state: %r" % row["state"]
assert data["platforms"]["linux"] >= 1, "linux platform tally missing"
EOF
check "api: registered client listed with hostname and OK state" $? "see $RUN/api-clients.json"

# The Client Status page itself renders for the logged-in session.
code=$(curl -k -s -o "$RUN/cstatus.html" -w '%{http_code}' -b "$RUN/cookies" \
    "https://127.0.0.1:$WPORT/index.php?view=clientstatus")
check "console: Client Status page renders (200)" $([ "$code" = "200" ]; echo $?) "got: $code"
check "console: Client Status table markup present" \
    $(grep -q 'id="cstable"' "$RUN/cstatus.html" 2>/dev/null; echo $?)

echo "------------------------------------------------------------"
if [ "$FAILURES" -gt 0 ]; then
    echo "FAILED: $FAILURES check(s) failed"
    echo "Artifacts left in $RUN for inspection (setup.log, client.log, broker.log; mosquitto log: $MOSQ_LOG)"
    exit 1
fi
echo "All checks passed."
exit 0
