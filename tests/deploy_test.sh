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
openssl verify -CAfile "$ROOT/config/ssl/luminum-ca.crt" "$ROOT/config/ssl/mosquitto.crt" >/dev/null 2>&1
check "mosquitto leaf chains to the server CA" "$?"
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
# The CLI configuration tool is installed alongside the other operator tools
# and works against the real install's SYSTEM.CONFIG: it reads a seeded value
# (MISSINGAFTER, default 90) and an unseeded, flow-irrelevant key (USERLOGGING)
# can be set and is persisted.
check "luminum-config.pl is installed and executable" $([ -x "$ROOT/luminum-config.pl" ]; echo $?)
PERL5LIB="$PERL_LIBS" perl "$ROOT/luminum-config.pl" get MISSINGAFTER > "$RUN/lumcfg.log" 2>&1
check "luminum-config.pl reads the installed config" $([ "$(cat "$RUN/lumcfg.log")" = "MISSINGAFTER = 90" ]; echo $?) "see $RUN/lumcfg.log"
PERL5LIB="$PERL_LIBS" perl "$ROOT/luminum-config.pl" set USERLOGGING=Enabled > "$RUN/lumcfg2.log" 2>&1
check "luminum-config.pl set persists to SYSTEM.CONFIG" $([ "$(cat "$RUN/lumcfg2.log")" = "set USERLOGGING = Enabled" ] && [ "$(dbq "select CVAL from SYSTEM.CONFIG where CKEY='USERLOGGING';")" = "Enabled" ]; echo $?) "see $RUN/lumcfg2.log"
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

# Install UUID: the client generates CLUUID on first start and presents it
# at registration; the broker must store it in AUTH.UUID (protocol 3.1).
CLUUID_C=$(cfgval CLUUID)
check "client generated and stored CLUUID (UUIDv4)" \
    $([[ -n "$CLUUID_C" && "$CLUUID_C" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$ ]]; echo $?) "cluuid=[$CLUUID_C]"
AUTH_UUID=$(dbq "select UUID from CLIENTS.AUTH where ID=$UID_C;")
check "broker stored the client UUID in AUTH.UUID" $([ "$AUTH_UUID" = "$CLUUID_C" ]; echo $?) "got: [$AUTH_UUID]"

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
assert isinstance(data["checkinint"], int) and data["checkinint"] > 0, "checkinint: %r" % data["checkinint"]
assert isinstance(data["server_ts"], int) and data["server_ts"] > 0, "server_ts: %r" % data["server_ts"]
assert isinstance(row["lastseen_ts"], int) and row["lastseen_ts"] > 0, "lastseen_ts: %r" % row["lastseen_ts"]
assert row["lastseen_ts"] <= data["server_ts"], "lastseen_ts after server clock"
EOF
check "api: registered client listed with hostname and OK state" $? "see $RUN/api-clients.json"

# The Client Status page itself renders for the logged-in session.
code=$(curl -k -s -o "$RUN/cstatus.html" -w '%{http_code}' -b "$RUN/cookies" \
    "https://127.0.0.1:$WPORT/index.php?view=clientstatus")
check "console: Client Status page renders (200)" $([ "$code" = "200" ]; echo $?) "got: $code"
check "console: Client Status table markup present" \
    $(grep -q 'id="cstable"' "$RUN/cstatus.html" 2>/dev/null; echo $?)
# The submenu parent links lay out label + arrow with flex: the arrow is
# pinned to the right edge by margin-left: auto in default.css, so no
# per-label inline margin hacks may remain on the arrow spans.
check "console: submenu arrows carry no inline margin hacks" \
    $(grep -q 'class="arrow"' "$RUN/cstatus.html" 2>/dev/null \
        && ! grep -q 'arrow" style="margin-left' "$RUN/cstatus.html" 2>/dev/null; echo $?)
code=$(curl -k -s -o "$RUN/default.css" -w '%{http_code}' -b "$RUN/cookies" \
    "https://127.0.0.1:$WPORT/layout/default.css")
# The flex rule must be qualified (.dropdown-content .submenu-link) - the
# unqualified selector loses to .dropdown-content a's display: block and
# the arrow collapses back onto the label.
check "console: default.css flex-lays-out the submenu link and pins the arrow" \
    $([ "$code" = "200" ] \
        && grep -q '.dropdown-content .submenu-link' "$RUN/default.css" 2>/dev/null \
        && grep -q 'margin-left: auto' "$RUN/default.css" 2>/dev/null; echo $?)
# Data rows (marked with the luminum-row class) render their text smaller
# than the header/summary/filter rows.
check "console: default.css shrinks the table data row text" \
    $(grep -qF 'tr.luminum-row' "$RUN/default.css" 2>/dev/null \
        && grep -q 'font-size: 14px' "$RUN/default.css" 2>/dev/null; echo $?)
# The top row is the standard format: refresh button, displayed of
# total Items, and the (N Selected) suffix span.
check "console: Client Status top row is refresh + displayed of total Items" \
    $(grep -q 'id="refresh"' "$RUN/cstatus.html" 2>/dev/null \
        && grep -q 'id="viscount"' "$RUN/cstatus.html" 2>/dev/null \
        && grep -q 'id="totcount"' "$RUN/cstatus.html" 2>/dev/null \
        && grep -q 'id="selcount"' "$RUN/cstatus.html" 2>/dev/null; echo $?)
# The footer clock starts as "Processing Query... 0.00 Seconds" (the page
# script flips the prefix to "Query Completed in" when the first poll's
# database query completes).
check "console: Client Status footer carries the processing clock" \
    $(grep -q 'id="cstatusfootprefix"' "$RUN/cstatus.html" 2>/dev/null \
        && grep -q 'Processing Query...' "$RUN/cstatus.html" 2>/dev/null; echo $?)
check "console: check-in filter offers Check-in Interval(s)" \
    $(grep -q 'Check-in Interval(s)' "$RUN/cstatus.html" 2>/dev/null; echo $?)
check "console: status filter checkboxes present" \
    $(grep -q 'id="filtergreen"' "$RUN/cstatus.html" 2>/dev/null \
        && grep -q 'id="filteryellow"' "$RUN/cstatus.html" 2>/dev/null \
        && grep -q 'id="filterred"' "$RUN/cstatus.html" 2>/dev/null \
        && grep -q 'id="filteroffline"' "$RUN/cstatus.html" 2>/dev/null; echo $?)
# The breakdown JS must reference the count spans by their exact markup ids
# (single-quoted here so only the JS string literals match, not id="..."):
# a mismatch leaves the count stuck at 0 while the percentage updates.
check "console: status breakdown wiring references the count spans" \
    $(grep -q "'greencount'" "$RUN/cstatus.html" 2>/dev/null \
        && grep -q "'yellowcount'" "$RUN/cstatus.html" 2>/dev/null \
        && grep -q "'redcount'" "$RUN/cstatus.html" 2>/dev/null \
        && grep -q "'offcount'" "$RUN/cstatus.html" 2>/dev/null; echo $?)
check "console: client version filter table present" \
    $(grep -q 'id="vertable"' "$RUN/cstatus.html" 2>/dev/null \
        && grep -q 'id="verrows"' "$RUN/cstatus.html" 2>/dev/null; echo $?)
check "console: version breakdown wiring references the row container" \
    $(grep -q "'verrows'" "$RUN/cstatus.html" 2>/dev/null; echo $?)
# The inactivity client must be initialized on the page (footer.php injects
# the deadline/timeout/warn config from the live session): timeout is the
# seeded UTIMEOUT in seconds and the 2-minute warning is seeded Enabled.
check "console: inactivity client initialized with the UTIMEOUT config" \
    $(grep -q 'LuminumSession.init' "$RUN/cstatus.html" 2>/dev/null \
        && grep -q 'timeout: 900' "$RUN/cstatus.html" 2>/dev/null \
        && grep -q 'warn: true' "$RUN/cstatus.html" 2>/dev/null; echo $?)

# --- sensor create form (admin/sensors.php POST handler) ---------------------
# The create form posts directly to /admin/sensors.php; a valid POST inserts
# into CONTENT.SENSORS and redirects to the list. The installer's seeded
# "Luminum Default" set is the content set the form offers.
CSET_ID=$(dbq "select ID from CONTENT.SETS where NAME='Luminum Default';")
check "a content set exists for the sensor form" $([ -n "$CSET_ID" ]; echo $?)
AUTHOR_ID=$(dbq "select ID from AUTH.USERS where USERNAME='lumadmin';")

code=$(curl -k -s -o "$RUN/sensor-new.html" -w '%{http_code}' -b "$RUN/cookies" \
    "https://127.0.0.1:$WPORT/index.php?view=sensors&action=new")
check "console: sensor create form renders (200)" $([ "$code" = "200" ]; echo $?) "got: $code"
# The "Split Results into Columns" checkbox reveals the output column name
# fields on the line below: a "Column Name" textfield with the query
# builder's add button (and a remove button), hidden until the checkbox is
# checked (toggleSplit shows #colrow).
check "console: the split checkbox reveals the column name fields" \
    $(grep -q 'id="colrow" style="display: none;"' "$RUN/sensor-new.html" 2>/dev/null \
        && grep -q 'placeholder="Column Name"' "$RUN/sensor-new.html" 2>/dev/null \
        && grep -q 'name="outcol\[\]" class="outcol"' "$RUN/sensor-new.html" 2>/dev/null; echo $?)
check "console: the column fields carry the query builder's add button and a remove button" \
    $(grep -q 'src="/icons/add.png" class="add"' "$RUN/sensor-new.html" 2>/dev/null \
        && grep -q 'src="/icons/remove.png" class="remove"' "$RUN/sensor-new.html" 2>/dev/null; echo $?)
check "console: toggleSplit shows the column field row" \
    $(grep -q 'document.getElementById("colrow").style.display = checkbox.checked ? "" : "none"' "$RUN/sensor-new.html" 2>/dev/null; echo $?)

code=$(curl -k -s -D "$RUN/sensor-post.hdr" -o /dev/null -w '%{http_code}' -b "$RUN/cookies" \
    --data-urlencode "pkgname=Deploy Test Sensor" \
    --data-urlencode "pkgdesc=End-to-end sensor created by the deploy test" \
    --data-urlencode "timeout=30" \
    --data-urlencode "tint=sec" \
    --data-urlencode "rtype=text" \
    --data-urlencode "contentset=$CSET_ID" \
    --data-urlencode "category=none" \
    --data-urlencode "leselect=on" \
    --data-urlencode "lstype=shell" \
    --data-urlencode "lscript=echo probe-output-42" \
    "https://127.0.0.1:$WPORT/admin/sensors.php")
check "console: valid sensor POST redirects (302)" $([ "$code" = "302" ]; echo $?) "got: $code"
check "console: POST redirected to the plain list (no saved flag)" \
    $(grep -qi "Location:.*view=sensors" "$RUN/sensor-post.hdr" 2>/dev/null \
        && ! grep -qi "saved=1" "$RUN/sensor-post.hdr" 2>/dev/null; echo $?)

srow=$(dbq "select concat(NAME,'|',DESCRIPTION,'|',CSET,'|',TIMEOUT,'|',RTYPE,'|',LSTYPE,'|',LSCRIPT,'|',ifnull(MSCRIPT,'NULL'),'|',ifnull(WSCRIPT,'NULL'),'|',USECASE,'|',CSPLIT,'|',ifnull(OUTCOLS,'NULL'),'|',WITHPARAMS,'|',AUTHOR) from CONTENT.SENSORS where NAME='Deploy Test Sensor';")
check "sensor row stored with the posted fields" \
    $([ "$srow" = "Deploy Test Sensor|End-to-end sensor created by the deploy test|$CSET_ID|30S|text|shell|echo probe-output-42|NULL|NULL|0|0|NULL|0|$AUTHOR_ID" ]; echo $?) \
    "got: $srow"

# A CSPLIT sensor: the column names post as repeated outcol fields and are
# stored joined by the delimiter in OUTCOLS.
code=$(curl -k -s -D "$RUN/sensor-split-post.hdr" -o /dev/null -w '%{http_code}' -b "$RUN/cookies" \
    --data-urlencode "pkgname=Deploy Split Sensor" \
    --data-urlencode "pkgdesc=Split-output sensor created by the deploy test" \
    --data-urlencode "timeout=30" \
    --data-urlencode "tint=sec" \
    --data-urlencode "rtype=text" \
    --data-urlencode "contentset=$CSET_ID" \
    --data-urlencode "category=none" \
    --data-urlencode "leselect=on" \
    --data-urlencode "lstype=shell" \
    --data-urlencode "lscript=printf 'app-one|1.0.1\napp-two|2.0\n'" \
    --data-urlencode "split=on" \
    --data-urlencode "delimeter=|" \
    --data-urlencode "outcol[]=Name" \
    --data-urlencode "outcol[]=Version" \
    "https://127.0.0.1:$WPORT/admin/sensors.php")
check "console: split sensor POST redirects (302)" $([ "$code" = "302" ]; echo $?) "got: $code"
srow=$(dbq "select concat(CSPLIT,'|',ifnull(DELIMITER,'NULL'),'|',ifnull(OUTCOLS,'NULL'),'|',if(LSCRIPT like 'printf%app-one|1.0.1%app-two|2.0%','yes','no')) from CONTENT.SENSORS where NAME='Deploy Split Sensor';")
check "split sensor stored with CSPLIT, DELIMITER, and the joined OUTCOLS" \
    $([ "$srow" = "1|||Name|Version|yes" ]; echo $?) "got: $srow"
# Splitting with fewer than two column names is rejected (no row stored).
code=$(curl -k -s -D "$RUN/sensor-split-bad.hdr" -o /dev/null -w '%{http_code}' -b "$RUN/cookies" \
    --data-urlencode "pkgname=Deploy Split Bad Sensor" \
    --data-urlencode "pkgdesc=Split sensor with one column name" \
    --data-urlencode "timeout=30" \
    --data-urlencode "tint=sec" \
    --data-urlencode "rtype=text" \
    --data-urlencode "contentset=$CSET_ID" \
    --data-urlencode "category=none" \
    --data-urlencode "leselect=on" \
    --data-urlencode "lstype=shell" \
    --data-urlencode "lscript=echo one" \
    --data-urlencode "split=on" \
    --data-urlencode "delimeter=|" \
    --data-urlencode "outcol[]=Only" \
    "https://127.0.0.1:$WPORT/admin/sensors.php")
check "console: split sensor with one column name redirects to the form (302)" $([ "$code" = "302" ]; echo $?) "got: $code"
check "the rejection points back to the form with err=outcols" \
    $(grep -qi "Location:.*action=new&err=outcols" "$RUN/sensor-split-bad.hdr" 2>/dev/null; echo $?)
check "the rejected split sensor inserted nothing" \
    $([ "$(dbq "select count(*) from CONTENT.SENSORS where NAME='Deploy Split Bad Sensor';")" = "0" ]; echo $?)

code=$(curl -k -s -o "$RUN/sensors.html" -w '%{http_code}' -b "$RUN/cookies" \
    "https://127.0.0.1:$WPORT/index.php?view=sensors")
check "console: sensor list renders after save (200)" $([ "$code" = "200" ]; echo $?) "got: $code"
check "console: created sensor appears in the list" \
    $(grep -q "Deploy Test Sensor" "$RUN/sensors.html" 2>/dev/null; echo $?)
check "console: no success message on the list" \
    $(! grep -q "Sensor created." "$RUN/sensors.html" 2>/dev/null; echo $?)
# The rendered data row carries the luminum-row class so the smaller data-row
# font-size rule applies (the :has()-only rule was dropped by some browsers).
check "console: sensor data row is marked luminum-row" \
    $(grep -qF '<tr class="luminum-row">' "$RUN/sensors.html" 2>/dev/null; echo $?)
# The list header mirrors the Client Status table: displayed of total items,
# with an empty selection span that allCheck() fills with "(N Selected)".
check "console: sensor list top row is displayed of total items with an empty selection span" \
    $(grep -q 'id="viscount"' "$RUN/sensors.html" 2>/dev/null \
        && grep -q 'id="totcount"' "$RUN/sensors.html" 2>/dev/null \
        && grep -qF 'items <span id="selcount"></span>' "$RUN/sensors.html" 2>/dev/null; echo $?)
check "console: sensor list selection span renders (N Selected) when rows are checked" \
    $(grep -qF "textContent = checkTrigger > 0 ? '(' + checkTrigger + ' Selected)' : ''" "$RUN/sensors.html" 2>/dev/null; echo $?)
check "console: sensor list displayed count tracks the text filter" \
    $(grep -qF "attachTextFilter('sensorsfilter', function (visible)" "$RUN/sensors.html" 2>/dev/null \
        && grep -qF "document.getElementById('viscount').textContent = visible" "$RUN/sensors.html" 2>/dev/null; echo $?)

# The Packages list header carries the same displayed-of-total + selection
# counters as the Sensors and Client Status tables. The row-wiring check
# needs at least one rendered row, and the console has no package create
# handler yet, so seed a package directly in the database.
dbq "insert into CONTENT.PACKAGES (NAME,DESCRIPTION,CSET,AUTHOR,CREATED) values ('Deploy Pkg Wiring','Package for the row-wiring checks',$CSET_ID,$AUTHOR_ID,now());"
code=$(curl -k -s -o "$RUN/packages.html" -w '%{http_code}' -b "$RUN/cookies" \
    "https://127.0.0.1:$WPORT/index.php?view=packages")
check "console: packages list renders (200)" $([ "$code" = "200" ]; echo $?) "got: $code"
check "console: packages list top row is displayed of total items with an empty selection span" \
    $(grep -q 'id="viscount"' "$RUN/packages.html" 2>/dev/null \
        && grep -q 'id="totcount"' "$RUN/packages.html" 2>/dev/null \
        && grep -qF 'items <span id="selcount"></span>' "$RUN/packages.html" 2>/dev/null; echo $?)
check "console: packages list displayed count tracks the text filter" \
    $(grep -qF "attachTextFilter('packagesfilter', function (visible)" "$RUN/packages.html" 2>/dev/null \
        && grep -qF "document.getElementById('viscount').textContent = visible" "$RUN/packages.html" 2>/dev/null; echo $?)
check "console: packages list selection span renders (N Selected) when rows are checked" \
    $(grep -qF "n > 0 ? '(' + n + ' Selected)' : ''" "$RUN/packages.html" 2>/dev/null; echo $?)
check "console: packages rows wire the checkbox to row highlight + selection count" \
    $(grep -qF 'function rowHighlight(idnum)' "$RUN/packages.html" 2>/dev/null \
        && grep -qF 'onclick="rowHighlight(' "$RUN/packages.html" 2>/dev/null \
        && grep -qF '); pkgAllCheck();"' "$RUN/packages.html" 2>/dev/null; echo $?)

# The Content Sets list carries the same displayed-of-total + selection
# counters, and its Sensors/Packages columns must count the set's content
# via the CSET foreign key (the old join on the child tables' primary keys
# only matched rows whose own ID equaled the set's ID).
csensors=$(dbq "select count(*) from CONTENT.SENSORS where CSET='$CSET_ID';")
code=$(curl -k -s -o "$RUN/csets.html" -w '%{http_code}' -b "$RUN/cookies" \
    "https://127.0.0.1:$WPORT/index.php?view=csets")
check "console: content sets list renders (200)" $([ "$code" = "200" ]; echo $?) "got: $code"
check "console: content sets top row is displayed of total items with an empty selection span" \
    $(grep -q 'id="viscount"' "$RUN/csets.html" 2>/dev/null \
        && grep -q 'id="totcount"' "$RUN/csets.html" 2>/dev/null \
        && grep -qF 'items <span id="selcount"></span>' "$RUN/csets.html" 2>/dev/null; echo $?)
check "console: content sets displayed count tracks the text filter" \
    $(grep -qF "attachTextFilter('csetsfilter', function (visible)" "$RUN/csets.html" 2>/dev/null \
        && grep -qF "document.getElementById('viscount').textContent = visible" "$RUN/csets.html" 2>/dev/null; echo $?)
check "console: content sets selection span renders (N Selected) when rows are checked" \
    $(grep -qF "textContent = checkTrigger > 0 ? '(' + checkTrigger + ' Selected)' : ''" "$RUN/csets.html" 2>/dev/null; echo $?)
check "console: content sets Sensors column counts the set's sensors via CSET" \
    $(grep -qF "\"${CSET_ID}E\" style=\"background-color: #494a69; font-weight: normal;\">$csensors</td>" "$RUN/csets.html" 2>/dev/null; echo $?) \
    "expected: $csensors"

# The Scheduled Actions and Action History tables are still row-less stubs,
# but their headers carry the same displayed-of-total + selection structure
# so no markup change is needed when the rows land.
code=$(curl -k -s -o "$RUN/actions.html" -w '%{http_code}' -b "$RUN/cookies" \
    "https://127.0.0.1:$WPORT/index.php?view=actions")
check "console: scheduled actions list renders (200)" $([ "$code" = "200" ]; echo $?) "got: $code"
check "console: scheduled actions top row is displayed of total Items with an empty selection span" \
    $(grep -q 'id="viscount"' "$RUN/actions.html" 2>/dev/null \
        && grep -q 'id="totcount"' "$RUN/actions.html" 2>/dev/null \
        && grep -qF 'Items <span id="selcount"></span>' "$RUN/actions.html" 2>/dev/null; echo $?)
check "console: scheduled actions displayed count tracks the text filter" \
    $(grep -qF "attachTextFilter('actionsfilter', function (visible)" "$RUN/actions.html" 2>/dev/null \
        && grep -qF "document.getElementById('viscount').textContent = visible" "$RUN/actions.html" 2>/dev/null; echo $?)
code=$(curl -k -s -o "$RUN/actionhistory.html" -w '%{http_code}' -b "$RUN/cookies" \
    "https://127.0.0.1:$WPORT/index.php?view=actionhistory")
check "console: action history list renders (200)" $([ "$code" = "200" ]; echo $?) "got: $code"
check "console: action history top row is displayed of total Items with an empty selection span" \
    $(grep -q 'id="viscount"' "$RUN/actionhistory.html" 2>/dev/null \
        && grep -q 'id="totcount"' "$RUN/actionhistory.html" 2>/dev/null \
        && grep -qF 'Items <span id="selcount"></span>' "$RUN/actionhistory.html" 2>/dev/null; echo $?)
check "console: action history displayed count tracks the text filter" \
    $(grep -qF "attachTextFilter('actionhistoryfilter', function (visible)" "$RUN/actionhistory.html" 2>/dev/null \
        && grep -qF "document.getElementById('viscount').textContent = visible" "$RUN/actionhistory.html" 2>/dev/null; echo $?)

# A duplicate name is rejected (case-insensitive collation) and adds no row.
code=$(curl -k -s -D "$RUN/sensor-dup.hdr" -o /dev/null -w '%{http_code}' -b "$RUN/cookies" \
    --data-urlencode "pkgname=deploy test sensor" \
    --data-urlencode "pkgdesc=Duplicate attempt" \
    --data-urlencode "timeout=30" \
    --data-urlencode "tint=sec" \
    --data-urlencode "rtype=text" \
    --data-urlencode "contentset=$CSET_ID" \
    --data-urlencode "leselect=on" \
    --data-urlencode "lstype=shell" \
    --data-urlencode "lscript=echo dup" \
    "https://127.0.0.1:$WPORT/admin/sensors.php")
check "console: duplicate-name POST redirects (302)" $([ "$code" = "302" ]; echo $?) "got: $code"
check "console: duplicate name redirected with err=dupname" \
    $(grep -qi "Location:.*err=dupname" "$RUN/sensor-dup.hdr" 2>/dev/null; echo $?)
check "duplicate POST did not add a second row" \
    $([ "$(dbq "select count(*) from CONTENT.SENSORS where NAME='Deploy Test Sensor';")" = "1" ]; echo $?)

# The save failure is shown in the overlay popup on the create form.
code=$(curl -k -s -o "$RUN/sensor-dup-form.html" -w '%{http_code}' -b "$RUN/cookies" \
    "https://127.0.0.1:$WPORT/index.php?view=sensors&action=new&err=dupname")
check "console: create form renders with err=dupname (200)" $([ "$code" = "200" ]; echo $?) "got: $code"
check "console: save failure shown via the overlay popup" \
    $(grep -q "LuminumOverlay.show" "$RUN/sensor-dup-form.html" 2>/dev/null \
        && grep -q "A sensor with that name already exists." "$RUN/sensor-dup-form.html" 2>/dev/null; echo $?)

# A POST with no platform enabled fails validation (err=os) and inserts nothing.
code=$(curl -k -s -D "$RUN/sensor-bad.hdr" -o /dev/null -w '%{http_code}' -b "$RUN/cookies" \
    --data-urlencode "pkgname=Bad Sensor" \
    --data-urlencode "pkgdesc=No script provided" \
    --data-urlencode "timeout=30" \
    --data-urlencode "tint=sec" \
    --data-urlencode "rtype=text" \
    --data-urlencode "contentset=$CSET_ID" \
    "https://127.0.0.1:$WPORT/admin/sensors.php")
check "console: scriptless POST redirected with err=os" \
    $(grep -qi "Location:.*err=os" "$RUN/sensor-bad.hdr" 2>/dev/null; echo $?)
check "scriptless POST inserted nothing" \
    $([ "$(dbq "select count(*) from CONTENT.SENSORS where NAME='Bad Sensor';")" = "0" ]; echo $?)

# An anonymous POST is bounced and inserts nothing.
code=$(curl -k -s -o /dev/null -w '%{http_code}' \
    --data-urlencode "pkgname=Anon Sensor" \
    --data-urlencode "pkgdesc=No session" \
    --data-urlencode "timeout=30" \
    --data-urlencode "tint=sec" \
    --data-urlencode "rtype=text" \
    --data-urlencode "contentset=$CSET_ID" \
    --data-urlencode "leselect=on" \
    --data-urlencode "lstype=shell" \
    --data-urlencode "lscript=echo anon" \
    "https://127.0.0.1:$WPORT/admin/sensors.php")
check "console: anonymous sensor POST rejected (302)" $([ "$code" = "302" ]; echo $?) "got: $code"
check "anonymous POST inserted nothing" \
    $([ "$(dbq "select count(*) from CONTENT.SENSORS where NAME='Anon Sensor';")" = "0" ]; echo $?)

# --- sensor edit form (Edit Selected -> action=edit) -------------------------
# The list's Edit Selected button opens the create form pre-filled with the
# selected sensor's stored values; saving posts the same fields plus a hidden
# sensorid, which switches the handler to an UPDATE (MODIFIED/EDITOR stamped).
check "console: create form carries a null editor payload" \
    $(grep -qF 'var editData = null;' "$RUN/sensor-new.html" 2>/dev/null; echo $?)
SENSOR_E=$(dbq "select ID from CONTENT.SENSORS where NAME='Deploy Test Sensor';")
code=$(curl -k -s -o "$RUN/sensor-edit.html" -w '%{http_code}' -b "$RUN/cookies" \
    "https://127.0.0.1:$WPORT/index.php?view=sensors&action=edit&id=$SENSOR_E")
check "console: sensor edit form renders (200)" $([ "$code" = "200" ]; echo $?) "got: $code"
check "console: edit form is titled Edit Sensor" \
    $(grep -q "<h1>Edit Sensor</h1>" "$RUN/sensor-edit.html" 2>/dev/null; echo $?)
check "console: edit form pre-fills the stored name and description" \
    $(grep -qF 'value="Deploy Test Sensor"' "$RUN/sensor-edit.html" 2>/dev/null \
        && grep -qF 'value="End-to-end sensor created by the deploy test"' "$RUN/sensor-edit.html" 2>/dev/null; echo $?)
check "console: edit form carries the hidden sensor id and the stored script" \
    $(grep -qF "name=\"sensorid\" value=\"$SENSOR_E\"" "$RUN/sensor-edit.html" 2>/dev/null \
        && grep -q "echo probe-output-42" "$RUN/sensor-edit.html" 2>/dev/null; echo $?)
check "console: list wires Edit Selected to the edit form" \
    $(grep -q 'action=edit&id=' "$RUN/sensors.html" 2>/dev/null; echo $?)
# Edit Selected enables on any single selection (the create form stamps the
# logged-in user as AUTHOR, so the old lumadmin-author guard disabled the
# button for every sensor a lumadmin session created); only the still-stub
# Delete button keeps an author guard.
check "console: Edit Selected is no longer gated on the lumadmin author" \
    $([ "$(grep -c 'innerText != "lumadmin"' "$RUN/sensors.html" 2>/dev/null)" = "1" ]; echo $?)

# An unknown id renders an in-view error (the console header is already
# printed by index.php, so the view cannot redirect).
code=$(curl -k -s -o "$RUN/sensor-edit-bad.html" -w '%{http_code}' -b "$RUN/cookies" \
    "https://127.0.0.1:$WPORT/index.php?view=sensors&action=edit&id=999999")
check "console: edit form with unknown id renders (200)" $([ "$code" = "200" ]; echo $?) "got: $code"
check "console: unknown id shows Sensor Not Found and no form" \
    $(grep -q "<h1 style=\"color: red\">Sensor Not Found</h1>" "$RUN/sensor-edit-bad.html" 2>/dev/null \
        && ! grep -q 'id="nsform"' "$RUN/sensor-edit-bad.html" 2>/dev/null; echo $?)

# A dedicated sensor for the save-path checks (the query section below relies
# on Deploy Test Sensor's script, so that one is only used for render checks).
code=$(curl -k -s -D "$RUN/sensor-editc-post.hdr" -o /dev/null -w '%{http_code}' -b "$RUN/cookies" \
    --data-urlencode "pkgname=Deploy Edit Sensor" \
    --data-urlencode "pkgdesc=Sensor created for the edit-form checks" \
    --data-urlencode "timeout=2" \
    --data-urlencode "tint=min" \
    --data-urlencode "rtype=number" \
    --data-urlencode "contentset=$CSET_ID" \
    --data-urlencode "category=none" \
    --data-urlencode "leselect=on" \
    --data-urlencode "lstype=shell" \
    --data-urlencode "lscript=echo edit-probe-42" \
    "https://127.0.0.1:$WPORT/admin/sensors.php")
check "console: edit-test sensor POST redirects (302)" $([ "$code" = "302" ]; echo $?) "got: $code"
SENSOR_X=$(dbq "select ID from CONTENT.SENSORS where NAME='Deploy Edit Sensor';")
check "edit-test sensor stored" $([ -n "$SENSOR_X" ]; echo $?)

# The edit form pre-fills the minute timeout, the number result type, and the
# stored script in the editor payload.
code=$(curl -k -s -o "$RUN/sensor-edit-x.html" -w '%{http_code}' -b "$RUN/cookies" \
    "https://127.0.0.1:$WPORT/index.php?view=sensors&action=edit&id=$SENSOR_X")
check "console: edit form for the edit-test sensor renders (200)" $([ "$code" = "200" ]; echo $?) "got: $code"
check "console: edit form pre-fills the minute timeout and number rtype" \
    $(grep -qF 'id="timeout" name="timeout" type="text" style="width: 30px;" value="2"' "$RUN/sensor-edit-x.html" 2>/dev/null \
        && grep -q '<option value="min" selected="selected">' "$RUN/sensor-edit-x.html" 2>/dev/null \
        && grep -q '<option value="number" selected="selected">' "$RUN/sensor-edit-x.html" 2>/dev/null; echo $?)
check "console: edit form editor payload carries the stored script" \
    $(grep -q "echo edit-probe-42" "$RUN/sensor-edit-x.html" 2>/dev/null; echo $?)

# A valid edit updates the row, stamps MODIFIED/EDITOR, and snapshots the
# pre-edit state into SENSORHISTORY (revision 1).
code=$(curl -k -s -D "$RUN/sensor-edit-post.hdr" -o /dev/null -w '%{http_code}' -b "$RUN/cookies" \
    --data-urlencode "sensorid=$SENSOR_X" \
    --data-urlencode "pkgname=Deploy Edit Sensor" \
    --data-urlencode "pkgdesc=Edited by the deploy test" \
    --data-urlencode "timeout=45" \
    --data-urlencode "tint=sec" \
    --data-urlencode "rtype=text" \
    --data-urlencode "contentset=$CSET_ID" \
    --data-urlencode "category=none" \
    --data-urlencode "leselect=on" \
    --data-urlencode "lstype=shell" \
    --data-urlencode "lscript=echo edit-probe-43" \
    "https://127.0.0.1:$WPORT/admin/sensors.php")
check "console: valid sensor edit POST redirects (302)" $([ "$code" = "302" ]; echo $?) "got: $code"
check "console: edit POST redirected to the plain list" \
    $(grep -qi "Location:.*view=sensors" "$RUN/sensor-edit-post.hdr" 2>/dev/null \
        && ! grep -qi "action=edit" "$RUN/sensor-edit-post.hdr" 2>/dev/null; echo $?)
erow=$(dbq "select concat(DESCRIPTION,'|',TIMEOUT,'|',RTYPE,'|',ifnull(MODIFIED,'NULL'),'|',ifnull(EDITOR,'NULL')) from CONTENT.SENSORS where ID='$SENSOR_X';")
check "sensor row updated with the posted fields" \
    $([ "$(dbq "select if(DESCRIPTION='Edited by the deploy test' and TIMEOUT='45S' and RTYPE='text' and MODIFIED is not null and EDITOR='$AUTHOR_ID','yes','no') from CONTENT.SENSORS where ID='$SENSOR_X';")" = "yes" ]; echo $?) \
    "got: $erow"
check "edit did not add a second row" \
    $([ "$(dbq "select count(*) from CONTENT.SENSORS where NAME='Deploy Edit Sensor';")" = "1" ]; echo $?)

# The pre-edit state is snapshotted as revision 1 (the sensor's original
# values), stamped with the editor and a timestamp.
hrow=$(dbq "select concat(REV,'|',DESCRIPTION,'|',TIMEOUT,'|',LSCRIPT,'|',ifnull(TIMESTAMP,'NULL'),'|',EDITOR) from CONTENT.SENSORHISTORY where ID='$SENSOR_X' order by REV;")
check "edit snapshotted the pre-edit state as revision 1" \
    $([ "$(dbq "select if(DESCRIPTION='Sensor created for the edit-form checks' and TIMEOUT='2M' and LSCRIPT='echo edit-probe-42' and TIMESTAMP is not null and EDITOR='$AUTHOR_ID','yes','no') from CONTENT.SENSORHISTORY where ID='$SENSOR_X' and REV=1;")" = "yes" ]; echo $?) \
    "got: $hrow"
check "SENSORHISTORY carries the SENSOR_REV unique key" \
    $([ "$(dbq "select count(*) from information_schema.STATISTICS where TABLE_SCHEMA='CONTENT' and TABLE_NAME='SENSORHISTORY' and INDEX_NAME='SENSOR_REV' and NON_UNIQUE=0;")" = "2" ]; echo $?)

# A second edit snapshots the intermediate state as revision 2.
code=$(curl -k -s -D "$RUN/sensor-edit2-post.hdr" -o /dev/null -w '%{http_code}' -b "$RUN/cookies" \
    --data-urlencode "sensorid=$SENSOR_X" \
    --data-urlencode "pkgname=Deploy Edit Sensor" \
    --data-urlencode "pkgdesc=Edited twice by the deploy test" \
    --data-urlencode "timeout=45" \
    --data-urlencode "tint=sec" \
    --data-urlencode "rtype=text" \
    --data-urlencode "contentset=$CSET_ID" \
    --data-urlencode "category=none" \
    --data-urlencode "leselect=on" \
    --data-urlencode "lstype=shell" \
    --data-urlencode "lscript=echo edit-probe-43" \
    "https://127.0.0.1:$WPORT/admin/sensors.php")
check "console: second edit POST redirects (302)" $([ "$code" = "302" ]; echo $?) "got: $code"
hrow2=$(dbq "select concat(REV,'|',DESCRIPTION,'|',LSCRIPT) from CONTENT.SENSORHISTORY where ID='$SENSOR_X' and REV=2;")
check "second edit snapshotted the intermediate state as revision 2" \
    $([ "$(dbq "select if(DESCRIPTION='Edited by the deploy test' and LSCRIPT='echo edit-probe-43','yes','no') from CONTENT.SENSORHISTORY where ID='$SENSOR_X' and REV=2;")" = "yes" ]; echo $?) \
    "got: $hrow2"

# The edit form now offers the prior revisions: the multi-line Revisions
# select lists each snapshot's datetime (newest first) and the embedded
# payload carries the old scripts so a selection loads them into the
# editors without a round trip.
code=$(curl -k -s -o "$RUN/sensor-edit-rev.html" -w '%{http_code}' -b "$RUN/cookies" \
    "https://127.0.0.1:$WPORT/index.php?view=sensors&action=edit&id=$SENSOR_X")
check "console: edit form with history renders (200)" $([ "$code" = "200" ]; echo $?) "got: $code"
check "console: Revisions label is bold with a line break" \
    $(grep -qF '<span style="color: #444; font-weight: bold;">Revisions:</span><br>' "$RUN/sensor-edit-rev.html" 2>/dev/null; echo $?)
check "console: Revisions select lists both prior revisions' datetimes" \
    $(grep -q 'id="revisions"' "$RUN/sensor-edit-rev.html" 2>/dev/null \
        && grep -q 'size="5"' "$RUN/sensor-edit-rev.html" 2>/dev/null \
        && grep -qE 'value="2">[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}<' "$RUN/sensor-edit-rev.html" 2>/dev/null \
        && grep -qE 'value="1">[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}<' "$RUN/sensor-edit-rev.html" 2>/dev/null; echo $?)
check "console: Revisions select leads with the Current option" \
    $(grep -A1 'value="Current"' "$RUN/sensor-edit-rev.html" 2>/dev/null | grep -q 'value="2">'; echo $?)
modts=$(dbq "select MODIFIED from CONTENT.SENSORS where ID='$SENSOR_X';")
check "console: Current option is selected by default and shows the current datetime" \
    $(grep -qF "value=\"Current\" selected=\"selected\">Current ($modts)</option>" "$RUN/sensor-edit-rev.html" 2>/dev/null; echo $?) "modts=[$modts]"
check "console: revision payload carries the pre-edit script" \
    $(grep -q 'revisionData' "$RUN/sensor-edit-rev.html" 2>/dev/null \
        && grep -q 'echo edit-probe-42' "$RUN/sensor-edit-rev.html" 2>/dev/null; echo $?)
check "console: create form has no Revisions select" \
    $(! grep -q 'id="revisions"' "$RUN/sensor-new.html" 2>/dev/null; echo $?)

# The list's "Modified By" column must show the editor's username, not the
# raw user ID (the row's EDITOR column is an AUTH.USERS foreign key).
code=$(curl -k -s -o "$RUN/sensor-list-editor.html" -w '%{http_code}' -b "$RUN/cookies" \
    "https://127.0.0.1:$WPORT/index.php?view=sensors")
check "console: sensor list renders (200)" $([ "$code" = "200" ]; echo $?) "got: $code"
check "console: Modified By column shows the editor's username" \
    $(grep -qF "\"${SENSOR_X}H\" style=\"background-color: #494a69; font-weight: normal;\">lumadmin</td>" "$RUN/sensor-list-editor.html" 2>/dev/null; echo $?)
check "console: Modified By column does not show the raw editor ID" \
    $(! grep -qF "\"${SENSOR_X}H\" style=\"background-color: #494a69; font-weight: normal;\">$AUTHOR_ID</td>" "$RUN/sensor-list-editor.html" 2>/dev/null; echo $?)

# Renaming to another sensor's name is rejected; the failure redirect keeps
# the edit form's id so the overlay popup shows on it.
code=$(curl -k -s -D "$RUN/sensor-edit-dup.hdr" -o /dev/null -w '%{http_code}' -b "$RUN/cookies" \
    --data-urlencode "sensorid=$SENSOR_X" \
    --data-urlencode "pkgname=Deploy Test Sensor" \
    --data-urlencode "pkgdesc=Steal the other name" \
    --data-urlencode "timeout=45" \
    --data-urlencode "tint=sec" \
    --data-urlencode "rtype=text" \
    --data-urlencode "contentset=$CSET_ID" \
    --data-urlencode "category=none" \
    --data-urlencode "leselect=on" \
    --data-urlencode "lstype=shell" \
    --data-urlencode "lscript=echo edit-probe-42" \
    "https://127.0.0.1:$WPORT/admin/sensors.php")
check "console: rename to an existing name redirects (302)" $([ "$code" = "302" ]; echo $?) "got: $code"
check "console: rename redirected with err=dupname on the edit form" \
    $(grep -qi "Location:.*action=edit&id=$SENSOR_X&err=dupname" "$RUN/sensor-edit-dup.hdr" 2>/dev/null; echo $?)
check "rename did not change the sensor name" \
    $([ "$(dbq "select NAME from CONTENT.SENSORS where ID='$SENSOR_X';")" = "Deploy Edit Sensor" ]; echo $?)

# An edit that disables every platform fails validation (err=os) and changes
# nothing.
code=$(curl -k -s -D "$RUN/sensor-edit-os.hdr" -o /dev/null -w '%{http_code}' -b "$RUN/cookies" \
    --data-urlencode "sensorid=$SENSOR_X" \
    --data-urlencode "pkgname=Deploy Edit Sensor" \
    --data-urlencode "pkgdesc=No platforms left" \
    --data-urlencode "timeout=45" \
    --data-urlencode "tint=sec" \
    --data-urlencode "rtype=text" \
    --data-urlencode "contentset=$CSET_ID" \
    --data-urlencode "category=none" \
    "https://127.0.0.1:$WPORT/admin/sensors.php")
check "console: platform-less edit redirected with err=os" \
    $(grep -qi "Location:.*action=edit&id=$SENSOR_X&err=os" "$RUN/sensor-edit-os.hdr" 2>/dev/null; echo $?)
check "platform-less edit changed nothing" \
    $([ "$(dbq "select if(DESCRIPTION='Edited twice by the deploy test' and LSCRIPT='echo edit-probe-43','yes','no') from CONTENT.SENSORS where ID='$SENSOR_X';")" = "yes" ]; echo $?)

# An edit POST for a nonexistent sensor bounces to the list and inserts nothing.
code=$(curl -k -s -D "$RUN/sensor-edit-ghost.hdr" -o /dev/null -w '%{http_code}' -b "$RUN/cookies" \
    --data-urlencode "sensorid=999999" \
    --data-urlencode "pkgname=Ghost Edit Sensor" \
    --data-urlencode "pkgdesc=Editing a sensor that does not exist" \
    --data-urlencode "timeout=30" \
    --data-urlencode "tint=sec" \
    --data-urlencode "rtype=text" \
    --data-urlencode "contentset=$CSET_ID" \
    --data-urlencode "category=none" \
    --data-urlencode "leselect=on" \
    --data-urlencode "lstype=shell" \
    --data-urlencode "lscript=echo ghost" \
    "https://127.0.0.1:$WPORT/admin/sensors.php")
check "console: edit POST for a missing sensor redirects (302)" $([ "$code" = "302" ]; echo $?) "got: $code"
check "console: missing-sensor redirect goes to the plain list" \
    $(grep -qi "Location:.*view=sensors" "$RUN/sensor-edit-ghost.hdr" 2>/dev/null \
        && ! grep -qi "action=edit" "$RUN/sensor-edit-ghost.hdr" 2>/dev/null; echo $?)
check "missing-sensor edit inserted nothing" \
    $([ "$(dbq "select count(*) from CONTENT.SENSORS where NAME='Ghost Edit Sensor';")" = "0" ]; echo $?)

# --- query builder + results (protocol 7.3 condition filtering) --------------
# The query UI posts to /api/commands.php: a broadcast (target "all") query
# whose condition tree the live client evaluates itself - it answers only
# when the conditions match, and QUERYRESULTS is filled by the worker.
code=$(curl -k -s -o "$RUN/query.html" -w '%{http_code}' -b "$RUN/cookies" \
    "https://127.0.0.1:$WPORT/modules.php?view=query")
check "console: query page renders (200)" $([ "$code" = "200" ]; echo $?) "got: $code"
check "console: query page offers the sensor fields and catalog" \
    $(grep -q 'placeholder="Sensor"' "$RUN/query.html" 2>/dev/null \
        && grep -q "Deploy Test Sensor" "$RUN/query.html" 2>/dev/null; echo $?)
# The left form button follows the active tab: Reset Form on the Query
# Builder tab, Copy to Builder on the Saved Queries tab.
check "console: the builder tab's form button is Reset Form" \
    $(grep -q '>Reset Form<' "$RUN/query.html" 2>/dev/null; echo $?)
# The header menu's "Saved Queries" link opens the query page on its Saved
# Queries tab (?tab=saved) - the old standalone Saved Queries page is gone.
code=$(curl -k -s -o "$RUN/query-saved.html" -w '%{http_code}' -b "$RUN/cookies" \
    "https://127.0.0.1:$WPORT/modules.php?view=query&tab=saved")
check "console: query page with tab=saved renders (200)" $([ "$code" = "200" ]; echo $?) "got: $code"
check "console: tab=saved opens the page on the Saved Queries tab" \
    $(grep -q 'tablink tabbarsel" style="border-right: 1px solid #07f;" onclick="switchTab(event, .Saved.)"' "$RUN/query-saved.html" 2>/dev/null; echo $?)
check "console: the Saved tab's form button is Copy to Builder" \
    $(grep -q '>Copy to Builder<' "$RUN/query-saved.html" 2>/dev/null; echo $?)
# Copy to Builder starts disabled on the Saved tab (no saved query is
# selected yet); the module enables it when a row's radio is checked.
check "console: the Saved tab's form button starts disabled" \
    $(grep -q 'disabled="disabled">Copy to Builder<' "$RUN/query-saved.html" 2>/dev/null; echo $?)
# Delete Selected sits to the left of the form button: a Saved-tab-only
# button (hidden on the Query Builder tab) that starts disabled and the
# module enables it when a row's radio is checked.
check "console: the Saved tab carries the Delete Selected button, starting disabled" \
    $(grep -q 'disabled="disabled">Delete Selected</button> <button id="resetform"' "$RUN/query-saved.html" 2>/dev/null; echo $?)
check "console: the builder tab hides the Delete Selected button" \
    $(grep -q 'style="display: none;margin-right: 0;" disabled="disabled">Delete Selected<' "$RUN/query.html" 2>/dev/null; echo $?)
# The Saved Queries tab carries the console's standard table (the old
# "No saved queries yet." placeholder is gone): the displayed-of-total
# count, the right-hand filter box, and the checkbox / Name /
# Structure / Author / Create Date columns - saved queries have no storage
# yet, so the table renders its empty state. The Structure column renders
# the query's full text-based interpretation.
check "console: the Saved Queries tab carries the standard table" \
    $(grep -q 'id="savedqueriesfilter"' "$RUN/query-saved.html" 2>/dev/null \
        && grep -q '>Name<' "$RUN/query-saved.html" 2>/dev/null \
        && grep -q '>Structure<' "$RUN/query-saved.html" 2>/dev/null \
        && grep -q '>Author<' "$RUN/query-saved.html" 2>/dev/null \
        && grep -q '>Create Date<' "$RUN/query-saved.html" 2>/dev/null; echo $?)
# The selection column's header checkbox is a permanently disabled dummy:
# the rows are radio buttons (one selection), so there is no select-all.
check "console: the Saved tab's header selection is a disabled dummy checkbox" \
    $(grep -q '<td><input type="checkbox" disabled="disabled"></td><td>Name</td>' "$RUN/query-saved.html" 2>/dev/null; echo $?)
# The table sits inside the blue content box with the standard module
# padding, and the checkbox column is pinned to a fixed 32px in the
# colgroup (table-layout: fixed) so it does not stretch with the table;
# the Name and Structure columns are the flexible (width-less) columns.
check "console: the Saved Queries table carries the standard module inset" \
    $(grep -q '<div style="padding: 5px 20px 20px 20px;">' "$RUN/query-saved.html" 2>/dev/null; echo $?)
check "console: the Saved Queries table pins its checkbox column in a colgroup" \
    $(grep -q 'table-layout: fixed;' "$RUN/query-saved.html" 2>/dev/null \
        && grep -q '<colgroup><col style="width: 32px;"><col><col>' "$RUN/query-saved.html" 2>/dev/null; echo $?)
check "console: the Saved Queries table's Name column is a flexible column" \
    $(grep -q '<td>Name</td>' "$RUN/query-saved.html" 2>/dev/null; echo $?)
check "console: the Saved Queries table's Structure column is a flexible column" \
    $(grep -q '<td>Structure</td>' "$RUN/query-saved.html" 2>/dev/null; echo $?)
check "console: the Saved Queries tab shows the displayed-of-total count" \
    $(grep -q '<span id="sqviscount">0</span> of <span id="sqtotcount">0</span> items <span id="sqselcount"></span>' "$RUN/query-saved.html" 2>/dev/null; echo $?)
check "console: the Saved Queries placeholder text is gone" \
    $(! grep -q 'No saved queries yet.' "$RUN/query-saved.html" 2>/dev/null; echo $?)
code=$(curl -k -s -o "$RUN/savedqueries.html" -w '%{http_code}' -b "$RUN/cookies" \
    "https://127.0.0.1:$WPORT/index.php?view=savedqueries")
# (the header menu still carries the "Saved Queries" nav link, so match the
# old page's <h1> specifically)
check "console: the standalone savedqueries view no longer renders" \
    $([ "$code" = "200" ] && ! grep -q '<h1>Saved Queries</h1>' "$RUN/savedqueries.html" 2>/dev/null; echo $?)

SENSOR_Q=$(dbq "select ID from CONTENT.SENSORS where NAME='Deploy Test Sensor';")
body=$(python3 -c 'import json,sys;print(json.dumps({"target":"all","action":"query","sensors":[{"sid":int(sys.argv[1])}],"conditions":{"sid":int(sys.argv[1]),"op":"==","value":"probe-output-42"}}))' "$SENSOR_Q")
code=$(curl -k -s -o "$RUN/query-post.json" -w '%{http_code}' -b "$RUN/cookies" \
    -H 'Content-Type: application/json' -d "$body" \
    "https://127.0.0.1:$WPORT/api/commands.php")
check "api: matching broadcast query accepted (200)" $([ "$code" = "200" ]; echo $?) "got: $code"
QID_Q=$(python3 -c "import json;print(json.load(open('$RUN/query-post.json'))['qid'])")
CMD_Q=$(python3 -c "import json;print(json.load(open('$RUN/query-post.json'))['command'])")
CFG_Q=$(python3 -c "import json;print(json.load(open('$RUN/query-post.json'))['config_command'])")
check "query row enqueued for the broadcast target" \
    $([ "$(dbq "select concat(ACTION,'|',TARGET) from CLIENTS.COMMANDS where ID='$CMD_Q';")" = "query|all" ]; echo $?)
check "config row enqueued for the broadcast target" \
    $([ "$(dbq "select TARGET from CLIENTS.COMMANDS where ID='$CFG_Q';")" = "all" ]; echo $?)
check "query DATA carries the condition tree" \
    $([ "$(dbq "select if(DATA like '%conditions%','yes','no') from CLIENTS.COMMANDS where ID='$CMD_Q';")" = "yes" ]; echo $?)
check "config DATA carries the sensor definition" \
    $([ "$(dbq "select if(DATA like '%Deploy Test Sensor%','yes','no') from CLIENTS.COMMANDS where ID='$CFG_Q';")" = "yes" ]; echo $?)

res_ok=1
for i in $(seq 1 60); do
    r=$(dbq "select concat(UID,'|',SENSORID,'|',STATUS) from CLIENTS.QUERYRESULTS where QID='$QID_Q';")
    [ -n "$r" ] && { res_ok=0; break; }
    sleep 0.5
done
check "matching query answered by the live client" "$res_ok" "no QUERYRESULTS row for $QID_Q"
check "result row is from the live client with OK status" \
    $([ "$r" = "$UID_C|$SENSOR_Q|OK" ]; echo $?) "got: $r"
check "result row carries the sensor output" \
    $([ "$(dbq "select if(OUTPUT like '%probe-output-42%','yes','no') from CLIENTS.QUERYRESULTS where QID='$QID_Q';")" = "yes" ]; echo $?)

# A query whose condition the client cannot match must get NO answer: the
# client evaluates the tree, finds it false, and publishes nothing.
body=$(python3 -c 'import json,sys;print(json.dumps({"target":"all","action":"query","sensors":[{"sid":int(sys.argv[1])}],"conditions":{"sid":int(sys.argv[1]),"op":"==","value":"does-not-match"}}))' "$SENSOR_Q")
code=$(curl -k -s -o "$RUN/query-nomatch.json" -w '%{http_code}' -b "$RUN/cookies" \
    -H 'Content-Type: application/json' -d "$body" \
    "https://127.0.0.1:$WPORT/api/commands.php")
check "api: non-matching broadcast query accepted (200)" $([ "$code" = "200" ]; echo $?) "got: $code"
QID_N=$(python3 -c "import json;print(json.load(open('$RUN/query-nomatch.json'))['qid'])")
sent_ok=1
for i in $(seq 1 60); do
    st=$(dbq "select STATUS from CLIENTS.COMMANDS where QID='$QID_N';")
    [ "$st" = "SENT" ] && { sent_ok=0; break; }
    sleep 0.5
done
check "non-matching query reached the client (SENT)" "$sent_ok" "final status: $(dbq "select STATUS from CLIENTS.COMMANDS where QID='$QID_N';")"
sleep 5
check "non-matching query got no answer (client stayed silent)" \
    $([ "$(dbq "select count(*) from CLIENTS.QUERYRESULTS where QID='$QID_N';")" = "0" ]; echo $?)

# Invalid sensors are rejected server-side: a query naming a nonexistent
# sensor ID is never processed (no outbox rows) and the error names every
# missing ID, not just the first.
N_BEFORE=$(dbq "select count(*) from CLIENTS.COMMANDS;")
body=$(python3 -c 'import json;print(json.dumps({"target":"all","action":"query","sensors":[{"sid":999999}]}))')
code=$(curl -k -s -o "$RUN/query-badsid.json" -w '%{http_code}' -b "$RUN/cookies" \
    -H 'Content-Type: application/json' -d "$body" \
    "https://127.0.0.1:$WPORT/api/commands.php")
check "api: query with a nonexistent sensor rejected (404)" $([ "$code" = "404" ]; echo $?) "got: $code"
check "api: the error names the missing sensor" \
    $(grep -q "No such sensor: 999999" "$RUN/query-badsid.json" 2>/dev/null; echo $?)
body=$(python3 -c 'import json;print(json.dumps({"target":"all","action":"query","sensors":[{"sid":999999},{"sid":888888}],"conditions":{"sid":777777,"op":"==","value":"x"}}))')
code=$(curl -k -s -o "$RUN/query-badsids.json" -w '%{http_code}' -b "$RUN/cookies" \
    -H 'Content-Type: application/json' -d "$body" \
    "https://127.0.0.1:$WPORT/api/commands.php")
check "api: every missing sensor ID is reported at once" \
    $([ "$code" = "404" ] && grep -q "No such sensor: 999999, 888888, 777777" "$RUN/query-badsids.json" 2>/dev/null; echo $?) "got: $code"
check "rejected queries enqueued nothing" \
    $([ "$(dbq "select count(*) from CLIENTS.COMMANDS;")" = "$N_BEFORE" ]; echo $?)
# A valid retrieve sensor with a nonexistent condition sensor is rejected too.
body=$(python3 -c 'import json,sys;print(json.dumps({"target":"all","action":"query","sensors":[{"sid":int(sys.argv[1])}],"conditions":{"sid":777777,"op":"==","value":"x"}}))' "$SENSOR_Q")
code=$(curl -k -s -o "$RUN/query-badcond.json" -w '%{http_code}' -b "$RUN/cookies" \
    -H 'Content-Type: application/json' -d "$body" \
    "https://127.0.0.1:$WPORT/api/commands.php")
check "api: a query with a nonexistent condition sensor rejected (404)" \
    $([ "$code" = "404" ] && grep -q "No such sensor: 777777" "$RUN/query-badcond.json" 2>/dev/null; echo $?) "got: $code"
check "rejected condition query enqueued nothing" \
    $([ "$(dbq "select count(*) from CLIENTS.COMMANDS;")" = "$N_BEFORE" ]; echo $?)
# The builder's client-side validation: the submit button is disabled while
# any typed sensor fails to resolve, and a force-submitted form gets the
# overlay warning naming every invalid sensor with an OK button (every other
# query error carries one too).
code=$(curl -k -s -o "$RUN/querybuilder.js" -w '%{http_code}' -b "$RUN/cookies" \
    "https://127.0.0.1:$WPORT/layout/querybuilder.js")
check "console: query builder disables submit on invalid sensors" \
    $([ "$code" = "200" ] && grep -q "submitEnabled" "$RUN/querybuilder.js" 2>/dev/null \
        && grep -q "invalidSensorNames" "$RUN/querybuilder.js" 2>/dev/null; echo $?)
check "console: query errors show the overlay with an OK button" \
    $(grep -q "Invalid Sensor(s)" "$RUN/querybuilder.js" 2>/dev/null \
        && grep -q "label: 'OK'" "$RUN/querybuilder.js" 2>/dev/null; echo $?)
# Copy to Builder (the Saved Queries tab's form button): the page boots the
# sensor catalog the module reads, and the served module carries the copy
# wiring (the selected row's checkbox payload in data-payload).
check "console: the Copy to Builder wiring is served" \
    $(grep -q "luminumSensorCatalog" "$RUN/query.html" 2>/dev/null \
        && grep -q "function copyToBuilder" "$RUN/querybuilder.js" 2>/dev/null \
        && grep -q "data-payload" "$RUN/querybuilder.js" 2>/dev/null; echo $?)
# Run Query processes only the visible tab: the served module carries the
# tab-aware submit wiring (the active tab's validity drives the button, and
# the Saved tab submits the selected row's data-payload).
check "console: the Run Query tab wiring is served" \
    $(grep -q "function activeTab" "$RUN/querybuilder.js" 2>/dev/null \
        && grep -q "function savedSelection" "$RUN/querybuilder.js" 2>/dev/null \
        && grep -q "function submitPayload" "$RUN/querybuilder.js" 2>/dev/null; echo $?)

# --- per-OS sensor pairs (protocol 7.3): a client runs only its own pair ---
# The config command carries all six type/script fields per sensor; the
# client stores only the pair for its own OS and skips sensors the server
# did not define for it. A Mac-only sensor must not break the Linux
# client's config, must come back UNKNOWN_SENSOR when retrieved, and must
# evaluate false when used as a condition.
code=$(curl -k -s -D "$RUN/sensor-mac-post.hdr" -o /dev/null -w '%{http_code}' -b "$RUN/cookies" \
    --data-urlencode "pkgname=Deploy Test Mac Sensor" \
    --data-urlencode "pkgdesc=Mac-only sensor created by the deploy test" \
    --data-urlencode "timeout=30" \
    --data-urlencode "tint=sec" \
    --data-urlencode "rtype=text" \
    --data-urlencode "contentset=$CSET_ID" \
    --data-urlencode "category=none" \
    --data-urlencode "meselect=on" \
    --data-urlencode "mstype=shell" \
    --data-urlencode "mscript=echo mac-only-output-43" \
    "https://127.0.0.1:$WPORT/admin/sensors.php")
check "console: Mac-only sensor POST redirects (302)" $([ "$code" = "302" ]; echo $?) "got: $code"
SENSOR_M=$(dbq "select ID from CONTENT.SENSORS where NAME='Deploy Test Mac Sensor';")
check "Mac-only sensor stored with a NULL Linux pair" \
    $([ "$(dbq "select if(LSTYPE is null and MSTYPE='shell' and MSCRIPT='echo mac-only-output-43','yes','no') from CONTENT.SENSORS where ID='$SENSOR_M';")" = "yes" ]; echo $?)

# A broadcast query retrieving both sensors: the Linux client applies its
# own definition, skips the Mac-only one, and answers OK for its own sensor
# and UNKNOWN_SENSOR for the other.
body=$(python3 -c 'import json,sys;print(json.dumps({"target":"all","action":"query","sensors":[{"sid":int(sys.argv[1])},{"sid":int(sys.argv[2])}],"conditions":{"sid":int(sys.argv[1]),"op":"==","value":"probe-output-42"}}))' "$SENSOR_Q" "$SENSOR_M")
code=$(curl -k -s -o "$RUN/query-mixed.json" -w '%{http_code}' -b "$RUN/cookies" \
    -H 'Content-Type: application/json' -d "$body" \
    "https://127.0.0.1:$WPORT/api/commands.php")
check "api: mixed-platform broadcast query accepted (200)" $([ "$code" = "200" ]; echo $?) "got: $code"
QID_M=$(python3 -c "import json;print(json.load(open('$RUN/query-mixed.json'))['qid'])")
res_ok=1
for i in $(seq 1 60); do
    n=$(dbq "select count(*) from CLIENTS.QUERYRESULTS where QID='$QID_M';")
    [ "$n" = "2" ] && { res_ok=0; break; }
    sleep 0.5
done
check "mixed query answered with both per-sensor rows" "$res_ok" "rows: $(dbq "select count(*) from CLIENTS.QUERYRESULTS where QID='$QID_M';")"
check "Linux sensor row is OK with its output" \
    $([ "$(dbq "select concat(STATUS,'|',if(OUTPUT like '%probe-output-42%','yes','no')) from CLIENTS.QUERYRESULTS where QID='$QID_M' and SENSORID='$SENSOR_Q';")" = "OK|yes" ]; echo $?)
check "Mac-only sensor row is ERR UNKNOWN_SENSOR (skipped by the Linux client)" \
    $([ "$(dbq "select concat(STATUS,'|',ifnull(ERR,'NULL')) from CLIENTS.QUERYRESULTS where QID='$QID_M' and SENSORID='$SENSOR_M';")" = "ERR|UNKNOWN_SENSOR" ]; echo $?)

# A query retrieving the CSPLIT sensor: the client answers with the full
# multi-line output, and the results API carries the sensor's split
# metadata (csplit/delimiter/outcols) the results page uses to expand the
# output into named sub-columns.
SENSOR_S=$(dbq "select ID from CONTENT.SENSORS where NAME='Deploy Split Sensor';")
body=$(python3 -c 'import json,sys;print(json.dumps({"target":"all","action":"query","sensors":[{"sid":int(sys.argv[1])}],"conditions":{"sid":int(sys.argv[2]),"op":"==","value":"probe-output-42"}}))' "$SENSOR_S" "$SENSOR_Q")
code=$(curl -k -s -o "$RUN/query-split.json" -w '%{http_code}' -b "$RUN/cookies" \
    -H 'Content-Type: application/json' -d "$body" \
    "https://127.0.0.1:$WPORT/api/commands.php")
check "api: split-sensor broadcast query accepted (200)" $([ "$code" = "200" ]; echo $?) "got: $code"
QID_S=$(python3 -c "import json;print(json.load(open('$RUN/query-split.json'))['qid'])")
CMD_S=$(python3 -c "import json;print(json.load(open('$RUN/query-split.json'))['command'])")
res_ok=1
for i in $(seq 1 60); do
    r=$(dbq "select concat(UID,'|',SENSORID,'|',STATUS) from CLIENTS.QUERYRESULTS where QID='$QID_S';")
    [ -n "$r" ] && { res_ok=0; break; }
    sleep 0.5
done
check "split-sensor query answered by the live client" "$res_ok" "no QUERYRESULTS row for $QID_S"
check "the split sensor's answer carries both output lines" \
    $([ "$(dbq "select if(OUTPUT like '%app-one|1.0.1%' and OUTPUT like '%app-two|2.0%','yes','no') from CLIENTS.QUERYRESULTS where QID='$QID_S';")" = "yes" ]; echo $?)

# A condition on a sensor that is not defined for this OS evaluates false:
# the Linux client cannot run the Mac-only condition sensor, so it stays
# silent even though the value would match on a Mac.
body=$(python3 -c 'import json,sys;print(json.dumps({"target":"all","action":"query","sensors":[{"sid":int(sys.argv[1])}],"conditions":{"sid":int(sys.argv[2]),"op":"==","value":"mac-only-output-43"}}))' "$SENSOR_Q" "$SENSOR_M")
code=$(curl -k -s -o "$RUN/query-maccond.json" -w '%{http_code}' -b "$RUN/cookies" \
    -H 'Content-Type: application/json' -d "$body" \
    "https://127.0.0.1:$WPORT/api/commands.php")
check "api: Mac-condition broadcast query accepted (200)" $([ "$code" = "200" ]; echo $?) "got: $code"
QID_C=$(python3 -c "import json;print(json.load(open('$RUN/query-maccond.json'))['qid'])")
sent_ok=1
for i in $(seq 1 60); do
    st=$(dbq "select STATUS from CLIENTS.COMMANDS where QID='$QID_C';")
    [ "$st" = "SENT" ] && { sent_ok=0; break; }
    sleep 0.5
done
check "Mac-condition query reached the client (SENT)" "$sent_ok" "final status: $(dbq "select STATUS from CLIENTS.COMMANDS where QID='$QID_C';")"
sleep 5
check "Mac-condition query got no answer (condition sensor unknown on Linux)" \
    $([ "$(dbq "select count(*) from CLIENTS.QUERYRESULTS where QID='$QID_C';")" = "0" ]; echo $?)

code=$(curl -k -s -o "$RUN/queryresults.json" -w '%{http_code}' -b "$RUN/cookies" \
    "https://127.0.0.1:$WPORT/api/queryresults.php")
check "api: queryresults renders (200)" $([ "$code" = "200" ]; echo $?) "got: $code"
check "api: queryresults carries the answered query and its output" \
    $(grep -q "$QID_Q" "$RUN/queryresults.json" 2>/dev/null \
        && grep -q "probe-output-42" "$RUN/queryresults.json" 2>/dev/null; echo $?)

# The results are consolidated into the query page: the ?id= filter narrows
# the API to a single query (the query command's COMMANDS.ID), and the page
# passed that ID opens on the Results tab polling for it.
code=$(curl -k -s -o "$RUN/queryresults-id.json" -w '%{http_code}' -b "$RUN/cookies" \
    "https://127.0.0.1:$WPORT/api/queryresults.php?id=$CMD_Q")
check "api: queryresults?id renders (200)" $([ "$code" = "200" ]; echo $?) "got: $code"
check "api: queryresults?id carries only the named query and its output" \
    $(grep -q '"count":1' "$RUN/queryresults-id.json" 2>/dev/null \
        && grep -q "$QID_Q" "$RUN/queryresults-id.json" 2>/dev/null \
        && grep -q "probe-output-42" "$RUN/queryresults-id.json" 2>/dev/null; echo $?)
# The footer clock's inputs: the command's deadline (set when the worker
# published it), the online endpoints in the target, and the unique
# endpoints that answered.
check "api: queryresults carries the clock fields (deadline/online/answered)" \
    $(grep -q '"deadline_ts"' "$RUN/queryresults-id.json" 2>/dev/null \
        && grep -q '"target_online"' "$RUN/queryresults-id.json" 2>/dev/null \
        && grep -q '"answered"' "$RUN/queryresults-id.json" 2>/dev/null \
        && grep -q '"last_answer_ts"' "$RUN/queryresults-id.json" 2>/dev/null; echo $?)
# The CSPLIT sensor's retrieve entry carries the split metadata the results
# page expands the output with (the unsplit sensor's entry does not).
code=$(curl -k -s -o "$RUN/queryresults-split.json" -w '%{http_code}' -b "$RUN/cookies" \
    "https://127.0.0.1:$WPORT/api/queryresults.php?id=$CMD_S")
check "api: queryresults?id for the split query renders (200)" $([ "$code" = "200" ]; echo $?) "got: $code"
check "api: the split sensor carries csplit/delimiter/outcols" \
    $(grep -q '"csplit":1' "$RUN/queryresults-split.json" 2>/dev/null \
        && grep -q '"delimiter":"|"' "$RUN/queryresults-split.json" 2>/dev/null \
        && grep -q '"outcols":\["Name","Version"\]' "$RUN/queryresults-split.json" 2>/dev/null; echo $?)
check "api: the unsplit sensor's retrieve entry carries no split metadata" \
    $(grep -q '"csplit":0' "$RUN/queryresults-id.json" 2>/dev/null \
        && grep -q '"outcols":null' "$RUN/queryresults-id.json" 2>/dev/null; echo $?)

code=$(curl -k -s -o "$RUN/query-results.html" -w '%{http_code}' -b "$RUN/cookies" \
    "https://127.0.0.1:$WPORT/modules.php?view=query&id=$CMD_Q")
check "console: query page with a query ID renders (200)" $([ "$code" = "200" ]; echo $?) "got: $code"
# The page boots the results wiring (layout/queryresults.js) with the query
# ID; the module polls /api/queryresults.php?id=<that ID>.
check "console: query page with a query ID boots the results wiring for that query" \
    $(grep -q "LuminumQueryResults.init($CMD_Q)" "$RUN/query-results.html" 2>/dev/null; echo $?)
check "console: results table shell (count/filter row) present" \
    $(grep -q 'id="qrcount"' "$RUN/query-results.html" 2>/dev/null \
        && grep -q 'id="qrfilter"' "$RUN/query-results.html" 2>/dev/null \
        && grep -q 'id="qrtable-body"' "$RUN/query-results.html" 2>/dev/null; echo $?)
# The footer clock starts as "Processing Query... 0.00 Seconds" (the
# module flips the prefix to "Query Completed in" when the query finishes).
check "console: the results footer carries the processing clock" \
    $(grep -q 'id="qrfootprefix"' "$RUN/query-results.html" 2>/dev/null \
        && grep -q 'Processing Query...' "$RUN/query-results.html" 2>/dev/null; echo $?)
# The top row is the standard format: refresh button, displayed of
# total Items, and the (N Selected) suffix span.
check "console: results top row is refresh + displayed of total Items" \
    $(grep -q 'id="qrrefresh"' "$RUN/query-results.html" 2>/dev/null \
        && grep -q 'id="qrselcount"' "$RUN/query-results.html" 2>/dev/null; echo $?)
# Sensor output is often multi-line formatted text: the results table's
# sensor cells must render their newlines (white-space: pre-wrap), which
# needs the cellStyle support in table.js plus the flag in queryresults.js.
code=$(curl -k -s -o "$RUN/queryresults.js" -w '%{http_code}' -b "$RUN/cookies" \
    "https://127.0.0.1:$WPORT/layout/queryresults.js")
curl -k -s -o "$RUN/table.js" -b "$RUN/cookies" "https://127.0.0.1:$WPORT/layout/table.js"
check "console: query results pre-wrap the multi-line sensor output" \
    $([ "$code" = "200" ] && grep -q "whiteSpace: 'pre-wrap'" "$RUN/queryresults.js" 2>/dev/null \
        && grep -q 'col.whiteSpace' "$RUN/table.js" 2>/dev/null; echo $?)
# A CSPLIT sensor's output expands into named sub-columns: the module
# splits each output line on the sensor's delimiter (expandRow) and the
# table renderer carries the two-tier header + the spanning rows.
check "console: the results module expands CSPLIT output into sub-columns" \
    $(grep -q "function expandRow" "$RUN/queryresults.js" 2>/dev/null \
        && grep -q "sub: sub" "$RUN/queryresults.js" 2>/dev/null \
        && grep -q "physicalColumns" "$RUN/table.js" 2>/dev/null; echo $?)

# --- system information (Memory tab) -----------------------------------------
# The Memory tab reads /proc/meminfo for the totals and dmidecode for the
# per-slot module details, and its usage graph reads SYSTEM.MEMHIST
# (populated by the not-yet-built memory health check, like CPUHIST).
check "database: SYSTEM.MEMHIST table exists" \
    $([ "$(dbq "select count(*) from information_schema.tables where table_schema='SYSTEM' and table_name='MEMHIST';")" = "1" ]; echo $?)
code=$(curl -k -s -o "$RUN/sysinfo.html" -w '%{http_code}' -b "$RUN/cookies" \
    "https://127.0.0.1:$WPORT/index.php?view=sysinfo")
check "console: System Information page renders (200)" $([ "$code" = "200" ]; echo $?) "got: $code"
check "console: Memory tab markup present" \
    $(grep -q 'id="Memory"' "$RUN/sysinfo.html" 2>/dev/null \
        && grep -q '/images/ram.png' "$RUN/sysinfo.html" 2>/dev/null; echo $?)
# The Total Memory and Swap Total values must match the live /proc/meminfo
# within the page's one-decimal rounding.
python3 - "$RUN/sysinfo.html" <<'EOF'
import re, sys
html = open(sys.argv[1]).read()
def row(label):
    m = re.search(label + r':</td><td[^>]*>([^<]*)</td>', html)
    assert m, "row missing: " + label
    return m.group(1).strip()
def to_kb(val):
    num, unit = val.split()
    return float(num) * {'KB': 1, 'MB': 1024, 'GB': 1024**2, 'TB': 1024**3}[unit]
meminfo = {}
for line in open('/proc/meminfo'):
    parts = line.split()
    if len(parts) >= 2 and parts[1].isdigit():
        meminfo[parts[0].rstrip(':')] = int(parts[1])
for label, key in (('Total Memory', 'MemTotal'), ('Swap Total', 'SwapTotal')):
    got, want = to_kb(row(label)), meminfo[key]
    assert abs(got - want) / want < 0.01, "%s: %s vs %d kB" % (label, got, want)
EOF
check "console: Memory totals match /proc/meminfo" $? "see $RUN/sysinfo.html"
check "console: Memory used/free/available/swap rows present" \
    $(grep -q '>Used:</td>' "$RUN/sysinfo.html" 2>/dev/null \
        && grep -q '>Free:</td>' "$RUN/sysinfo.html" 2>/dev/null \
        && grep -q '>Available:</td>' "$RUN/sysinfo.html" 2>/dev/null \
        && grep -q '>Swap Total:</td>' "$RUN/sysinfo.html" 2>/dev/null \
        && grep -q '>Swap Used:</td>' "$RUN/sysinfo.html" 2>/dev/null \
        && grep -q '>Swap Free:</td>' "$RUN/sysinfo.html" 2>/dev/null; echo $?)
# The module section renders the per-slot details when dmidecode can read
# the SMBIOS data, and the not-available row otherwise (this test container
# exposes no DMI data, so the fallback is what renders here).
flag=0
grep -q 'Slot 1' "$RUN/sysinfo.html" 2>/dev/null || grep -q 'Not available' "$RUN/sysinfo.html" 2>/dev/null || flag=1
check "console: Memory module section renders (slots or fallback)" "$flag"
# The usage graph is wired like the CPU chart: a canvas, a title, and the
# JS payload built from the MEMHIST rows.
check "console: Memory usage graph wired to MEMHIST" \
    $(grep -q 'id="memchart"' "$RUN/sysinfo.html" 2>/dev/null \
        && grep -q 'Memory Usage History' "$RUN/sysinfo.html" 2>/dev/null \
        && grep -q 'const memXValues' "$RUN/sysinfo.html" 2>/dev/null \
        && grep -q 'const memYValues' "$RUN/sysinfo.html" 2>/dev/null; echo $?)
# Both usage charts draw their line with a solid border color (the CPU
# chart originally had the colors swapped, leaving a 0.1-alpha line
# invisible against the white canvas).
check "console: CPU chart draws its line with a solid border color" \
    $(grep -qF 'borderColor: "rgba(200,100,100,1.0)"' "$RUN/sysinfo.html" 2>/dev/null; echo $?)
check "console: Memory chart draws its line with a solid border color" \
    $(grep -qF 'borderColor: "rgba(100,150,220,1.0)"' "$RUN/sysinfo.html" 2>/dev/null; echo $?)
# Seed two history samples: they must reach the chart payload in
# oldest-first order, like the CPU chart's rows.
dbq "insert into SYSTEM.MEMHIST (TIMESTAMP,PCT) values (now() - interval 30 minute, '42'), (now() - interval 15 minute, '57');"
code=$(curl -k -s -o "$RUN/sysinfo2.html" -w '%{http_code}' -b "$RUN/cookies" \
    "https://127.0.0.1:$WPORT/index.php?view=sysinfo")
check "console: System Information re-renders with history (200)" $([ "$code" = "200" ]; echo $?) "got: $code"
check "console: MEMHIST samples reach the chart payload oldest first" \
    $(grep -q 'const memYValues = \[42,57\];' "$RUN/sysinfo2.html" 2>/dev/null; echo $?)

# --- devices tab ---------------------------------------------------------------
# The Devices tab enumerates the PCI and USB buses directly from sysfs (no
# lspci/lsusb dependency) and groups them into Device Manager-style
# categories; the rendered count must match what sysfs actually exposes.
check "console: Devices tab markup present" \
    $(grep -q 'id="Devices"' "$RUN/sysinfo.html" 2>/dev/null \
        && grep -q '/images/devices.png' "$RUN/sysinfo.html" 2>/dev/null; echo $?)
pci_n=0
for d in /sys/bus/pci/devices/*; do
    [ -d "$d" ] || continue
    a=$(basename "$d")
    if [[ "$a" =~ ^[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{1,2}\.[0-9a-f]$ ]]; then pci_n=$((pci_n + 1)); fi
done
usb_n=0
for d in /sys/bus/usb/devices/*; do
    n=$(basename "$d")
    case "$n" in *:*) continue;; esac
    case "$n" in *-*) ;; *) continue;; esac
    [ -f "$d/idVendor" ] && usb_n=$((usb_n + 1))
done
cpu_n=0
grep -q 'model name' /proc/cpuinfo && cpu_n=1
dev_expect=$((pci_n + usb_n + cpu_n))
dev_got=$(sed -n 's/.*Devices found:<\/b> &nbsp;&nbsp; \([0-9][0-9]*\).*/\1/p' "$RUN/sysinfo.html" 2>/dev/null | head -n1)
check "console: Devices found count matches sysfs" \
    $([ "$dev_got" = "$dev_expect" ]; echo $?) "got: ${dev_got:-<none>} expected: $dev_expect"
check "console: device categories render with the toggle wiring" \
    $(grep -q 'onclick="toggleDeviceCat(' "$RUN/sysinfo.html" 2>/dev/null \
        && grep -q 'function toggleDeviceCat' "$RUN/sysinfo.html" 2>/dev/null; echo $?)
usb_prod=""
for d in /sys/bus/usb/devices/*; do
    n=$(basename "$d")
    case "$n" in *:*) continue;; esac
    case "$n" in *-*) ;; *) continue;; esac
    if [ -f "$d/product" ]; then usb_prod=$(cat "$d/product"); break; fi
done
if [ -n "$usb_prod" ]; then
    check "console: USB device product from sysfs is rendered" \
        $(grep -qF "$usb_prod" "$RUN/sysinfo.html" 2>/dev/null; echo $?) "product: $usb_prod"
fi

# --- server options -----------------------------------------------------------
# The Server Options form (config.php?view=options) posts to
# /system/serveropts.php and must persist every presented option to
# SYSTEM.CONFIG (and the administrator email to AUTH.USERS).
code=$(curl -k -s -o "$RUN/serveropts.html" -w '%{http_code}' -b "$RUN/cookies" \
    "https://127.0.0.1:$WPORT/config.php?view=options")
check "console: Server Options page renders (200)" $([ "$code" = "200" ]; echo $?) "got: $code"
check "console: Server Options form posts to serveropts.php" \
    $(grep -q 'action="/system/serveropts.php"' "$RUN/serveropts.html" 2>/dev/null; echo $?)
CSET_ID=$(dbq "select ID from CONTENT.SETS where NAME = 'Luminum Default';")
check "database: Luminum Default content set exists" $([ -n "$CSET_ID" ]; echo $?)
# A full valid save: every tab's options in one POST.
code=$(curl -k -s -D "$RUN/serveropts-post.hdr" -o /dev/null -w '%{http_code}' -b "$RUN/cookies" \
    --data-urlencode "adminemail=ops@example.com" \
    --data-urlencode "minactconf=enabled" \
    --data-urlencode "actconfclients=100" \
    --data-urlencode "commproto=hybrid" \
    --data-urlencode "checkinint=10" \
    --data-urlencode "missingafter=45" \
    --data-urlencode "sensorset=$CSET_ID" \
    --data-urlencode "packageset=$CSET_ID" \
    --data-urlencode "sensorhist=Enabled" \
    --data-urlencode "srevcnt=7" \
    --data-urlencode "packagehist=Disabled" \
    --data-urlencode "passlen=12" \
    --data-urlencode "complexpass=enabled" \
    --data-urlencode "pwdcase=on" \
    --data-urlencode "pwdspec=on" \
    --data-urlencode "passkeys=Enabled" \
    --data-urlencode "2fa=Required" \
    --data-urlencode "inactiveint=30" \
    --data-urlencode "inttype=hour" \
    --data-urlencode "2minwarn=disabled" \
    "https://127.0.0.1:$WPORT/system/serveropts.php")
check "console: Server Options save redirects (302)" $([ "$code" = "302" ]; echo $?) "got: $code"
check "console: save redirects with saved=1" \
    $(grep -qi 'location:.*saved=1' "$RUN/serveropts-post.hdr" 2>/dev/null; echo $?)
# Every value must land in SYSTEM.CONFIG.
for pair in "TARGETCONF:Enabled" "TCONFTHRESHOLD:100" "ENDPOINTCOMM:hybrid" "CHECKININT:10" \
            "MISSINGAFTER:45" "DEFSENSORSET:$CSET_ID" "DEFPKGSET:$CSET_ID" "SENREVS:7" "PKGREVS:0" \
            "MINPASS:12" "COMPLEXPASS:Enabled" "PCUPPERLOWER:Enabled" "PCLETNUM:Disabled" \
            "PCSPECIAL:Enabled" "PASSKEYS:Enabled" "2FA:Required" "UTIMEOUT:30H" "UTIMEOUTWARN:Disabled"; do
    key=${pair%%:*}; val=${pair#*:}
    check "database: $key saved to $val" \
        $([ "$(dbq "select CVAL from SYSTEM.CONFIG where CKEY = '$key';")" = "$val" ]; echo $?)
done
check "database: admin email saved" \
    $([ "$(dbq "select EMAIL from AUTH.USERS where USERNAME = 'lumadmin';")" = "ops@example.com" ]; echo $?)
# The save must re-stamp the CURRENT session's deadline from the NEW UTIMEOUT
# before the redirect: the handler's own gate had refreshed it with the old
# seeded 15M (and the per-request UTIMEOUT cache would keep a plain touch
# stale), so without the re-stamp the delta would still be ~15 minutes.
delta=$(dbq "select timestampdiff(second, now(), EXPIRES) from AUTH.SESSION;")
check "session: save re-stamps the deadline from the new UTIMEOUT (30H)" \
    $([ "$delta" -gt 107000 ] && [ "$delta" -lt 109000 ]; echo $?) "delta: ${delta}s"
# ...and the page must re-render with the saved values (following the
# redirect target the browser lands on after the save).
code=$(curl -k -s -o "$RUN/serveropts2.html" -w '%{http_code}' -b "$RUN/cookies" \
    "https://127.0.0.1:$WPORT/config.php?view=options&saved=1")
check "console: Server Options re-renders after save (200)" $([ "$code" = "200" ]; echo $?) "got: $code"
# The save confirmation is the forced-focus overlay (shown when the reloaded
# page carries ?saved=1) with an OK button - not the old green banner.
check "console: saved confirmation shows the overlay with an OK button" \
    $(grep -q "get('saved') === '1'" "$RUN/serveropts2.html" 2>/dev/null \
        && grep -q "'Configuration saved.'" "$RUN/serveropts2.html" 2>/dev/null \
        && grep -q "label: 'OK'" "$RUN/serveropts2.html" 2>/dev/null; echo $?)
check "console: the old saved banner is gone" \
    $(! grep -q 'background-color: #e6f4e6' "$RUN/serveropts2.html" 2>/dev/null; echo $?)
check "console: saved values re-render (email, threshold, check-in)" \
    $(grep -qF 'value="ops@example.com"' "$RUN/serveropts2.html" 2>/dev/null \
        && grep -qF 'value="100"' "$RUN/serveropts2.html" 2>/dev/null \
        && grep -qF 'value="10"' "$RUN/serveropts2.html" 2>/dev/null; echo $?)
check "console: saved choices re-render selected (hybrid, Required, 30 hour)" \
    $(grep -q 'value="hybrid" selected="selected"' "$RUN/serveropts2.html" 2>/dev/null \
        && grep -q 'value="Required" selected="selected"' "$RUN/serveropts2.html" 2>/dev/null \
        && grep -qF 'value="30"' "$RUN/serveropts2.html" 2>/dev/null \
        && grep -q 'value="hour" selected="selected"' "$RUN/serveropts2.html" 2>/dev/null; echo $?)
check "console: saved content sets re-render selected" \
    $(grep -q "value=\"$CSET_ID\" selected=\"selected\"" "$RUN/serveropts2.html" 2>/dev/null; echo $?)
check "console: complexity checkboxes re-render checked" \
    $(grep -q 'id="pwdcase" name="pwdcase" type="checkbox" checked="checked"' "$RUN/serveropts2.html" 2>/dev/null \
        && grep -q 'id="pwdspec" name="pwdspec" type="checkbox" checked="checked"' "$RUN/serveropts2.html" 2>/dev/null; echo $?)
# An invalid save must redirect with the offending fields and write nothing.
before=$(dbq "select CVAL from SYSTEM.CONFIG where CKEY = 'CHECKININT';")
code=$(curl -k -s -D "$RUN/serveropts-bad.hdr" -o /dev/null -w '%{http_code}' -b "$RUN/cookies" \
    --data-urlencode "adminemail=not-an-email" \
    --data-urlencode "minactconf=enabled" \
    --data-urlencode "actconfclients=100" \
    --data-urlencode "commproto=mqtt" \
    --data-urlencode "checkinint=0" \
    --data-urlencode "missingafter=45" \
    --data-urlencode "sensorset=$CSET_ID" \
    --data-urlencode "packageset=$CSET_ID" \
    --data-urlencode "sensorhist=Enabled" \
    --data-urlencode "srevcnt=7" \
    --data-urlencode "packagehist=Disabled" \
    --data-urlencode "passlen=12" \
    --data-urlencode "complexpass=enabled" \
    --data-urlencode "pwdcase=on" \
    --data-urlencode "passkeys=Enabled" \
    --data-urlencode "2fa=Required" \
    --data-urlencode "inactiveint=30" \
    --data-urlencode "inttype=hour" \
    --data-urlencode "2minwarn=disabled" \
    "https://127.0.0.1:$WPORT/system/serveropts.php")
check "console: invalid save redirects (302)" $([ "$code" = "302" ]; echo $?) "got: $code"
check "console: invalid save reports the offending fields" \
    $(grep -qi 'location:.*err=adminemail,checkinint' "$RUN/serveropts-bad.hdr" 2>/dev/null; echo $?)
check "database: invalid save wrote nothing" \
    $([ "$(dbq "select CVAL from SYSTEM.CONFIG where CKEY = 'CHECKININT';")" = "$before" ]; echo $?)
# A nonexistent content set is rejected (the dropdowns only list real sets).
code=$(curl -k -s -D "$RUN/serveropts-ghost.hdr" -o /dev/null -w '%{http_code}' -b "$RUN/cookies" \
    --data-urlencode "adminemail=ops@example.com" \
    --data-urlencode "minactconf=enabled" \
    --data-urlencode "actconfclients=100" \
    --data-urlencode "commproto=mqtt" \
    --data-urlencode "checkinint=10" \
    --data-urlencode "missingafter=45" \
    --data-urlencode "sensorset=9999" \
    --data-urlencode "packageset=$CSET_ID" \
    --data-urlencode "sensorhist=Enabled" \
    --data-urlencode "srevcnt=7" \
    --data-urlencode "packagehist=Disabled" \
    --data-urlencode "passlen=12" \
    --data-urlencode "complexpass=enabled" \
    --data-urlencode "pwdcase=on" \
    --data-urlencode "passkeys=Enabled" \
    --data-urlencode "2fa=Required" \
    --data-urlencode "inactiveint=30" \
    --data-urlencode "inttype=hour" \
    --data-urlencode "2minwarn=disabled" \
    "https://127.0.0.1:$WPORT/system/serveropts.php")
check "console: nonexistent content set rejected" \
    $(grep -qi 'location:.*err=sensorset' "$RUN/serveropts-ghost.hdr" 2>/dev/null; echo $?)
# A markup-breaking email (attribute-breakout payload) must be rejected by
# the backend validator and must not reach AUTH.USERS.
before=$(dbq "select EMAIL from AUTH.USERS where USERNAME = 'lumadmin';")
code=$(curl -k -s -D "$RUN/serveropts-xss.hdr" -o /dev/null -w '%{http_code}' -b "$RUN/cookies" \
    --data-urlencode 'adminemail=a"onfocus=alert(1)@x.com' \
    --data-urlencode "minactconf=enabled" \
    --data-urlencode "actconfclients=100" \
    --data-urlencode "commproto=mqtt" \
    --data-urlencode "checkinint=10" \
    --data-urlencode "missingafter=45" \
    --data-urlencode "sensorset=$CSET_ID" \
    --data-urlencode "packageset=$CSET_ID" \
    --data-urlencode "sensorhist=Enabled" \
    --data-urlencode "srevcnt=7" \
    --data-urlencode "packagehist=Disabled" \
    --data-urlencode "passlen=12" \
    --data-urlencode "complexpass=enabled" \
    --data-urlencode "pwdcase=on" \
    --data-urlencode "passkeys=Enabled" \
    --data-urlencode "2fa=Required" \
    --data-urlencode "inactiveint=30" \
    --data-urlencode "inttype=hour" \
    --data-urlencode "2minwarn=disabled" \
    "https://127.0.0.1:$WPORT/system/serveropts.php")
check "console: markup-breaking email rejected" \
    $(grep -qi 'location:.*err=adminemail' "$RUN/serveropts-xss.hdr" 2>/dev/null; echo $?)
check "database: markup-breaking email not stored" \
    $([ "$(dbq "select EMAIL from AUTH.USERS where USERNAME = 'lumadmin';")" = "$before" ]; echo $?)
# Restore the seeded UTIMEOUT: the inactivity section below verifies the 15M
# deadline stamping, and a page load re-stamps the deadline from the value.
dbq "update SYSTEM.CONFIG set CVAL = '15M' where CKEY = 'UTIMEOUT';"
curl -k -s -o /dev/null -b "$RUN/cookies" "https://127.0.0.1:$WPORT/index.php?view=clientstatus"

# --- inactivity session timeout ----------------------------------------------
# Login must stamp the deadline from the UTIMEOUT server option (seeded 15M),
# not the old hardcoded 60 minutes.
delta=$(dbq "select timestampdiff(second, now(), EXPIRES) from AUTH.SESSION;")
check "session: EXPIRES stamped from UTIMEOUT (15M)" \
    $([ "$delta" -gt 870 ] && [ "$delta" -lt 930 ]; echo $?) "delta: ${delta}s"

# The extend endpoint refreshes the deadline and reports it to the client.
before=$(dbq "select unix_timestamp(EXPIRES) from AUTH.SESSION;")
sleep 2
code=$(curl -k -s -o "$RUN/touch.json" -w '%{http_code}' -b "$RUN/cookies" \
    "https://127.0.0.1:$WPORT/api/touch.php")
after=$(dbq "select unix_timestamp(EXPIRES) from AUTH.SESSION;")
check "api: touch.php refreshes the deadline (200)" $([ "$code" = "200" ]; echo $?) "got: $code"
check "api: touch.php moved EXPIRES forward" $([ "$after" -gt "$before" ]; echo $?) \
    "before=$before after=$after"
python3 - "$RUN/touch.json" <<'EOF'
import json, sys
data = json.load(open(sys.argv[1]))
assert data.get("ok") is True, "ok flag missing"
assert isinstance(data.get("expires"), int) and data["expires"] > 0, "expires missing"
assert isinstance(data.get("now"), int) and data["now"] > 0, "now missing"
EOF
check "api: touch.php reports ok/expires/now" $? "see $RUN/touch.json"

# Background API polling must NOT refresh the deadline: the Client Status
# table polls /api/clients.php every 5 seconds, and that is what used to
# hold idle sessions alive.
before=$(dbq "select unix_timestamp(EXPIRES) from AUTH.SESSION;")
curl -k -s -o /dev/null -b "$RUN/cookies" "https://127.0.0.1:$WPORT/api/clients.php"
curl -k -s -o /dev/null -b "$RUN/cookies" "https://127.0.0.1:$WPORT/api/clients.php"
after=$(dbq "select unix_timestamp(EXPIRES) from AUTH.SESSION;")
check "api: polling clients.php does not extend the deadline" \
    $([ "$before" -eq "$after" ]; echo $?) "before=$before after=$after"

# A page load IS activity and refreshes the deadline.
before=$(dbq "select unix_timestamp(EXPIRES) from AUTH.SESSION;")
sleep 2
curl -k -s -o /dev/null -b "$RUN/cookies" "https://127.0.0.1:$WPORT/index.php?view=clientstatus"
after=$(dbq "select unix_timestamp(EXPIRES) from AUTH.SESSION;")
check "console: page load refreshes the deadline" $([ "$after" -gt "$before" ]; echo $?) \
    "before=$before after=$after"

# An expired session is rejected by the API gate and bounced from pages, and
# the server-side session row is removed.
dbq "update AUTH.SESSION set EXPIRES = now() - interval 1 minute;"
code=$(curl -k -s -o /dev/null -w '%{http_code}' -b "$RUN/cookies" \
    "https://127.0.0.1:$WPORT/api/clients.php")
check "api: expired session rejected (401)" $([ "$code" = "401" ]; echo $?) "got: $code"
code=$(curl -k -s -o /dev/null -w '%{http_code}' -b "$RUN/cookies" \
    "https://127.0.0.1:$WPORT/index.php?view=clientstatus")
check "console: expired session bounced to login (302)" $([ "$code" = "302" ]; echo $?) "got: $code"
check "console: expired session row removed" \
    $([ "$(dbq "select count(*) from AUTH.SESSION;")" -eq 0 ]; echo $?)

echo "------------------------------------------------------------"
if [ "$FAILURES" -gt 0 ]; then
    echo "FAILED: $FAILURES check(s) failed"
    echo "Artifacts left in $RUN for inspection (setup.log, client.log, broker.log; mosquitto log: $MOSQ_LOG)"
    exit 1
fi
echo "All checks passed."
exit 0
