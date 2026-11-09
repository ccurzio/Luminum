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
#
# This proves the whole installer -> broker -> mosquitto -> client path, which
# the isolated scratch tests (mqtt_client_test.sh, mqtt_worker_test.sh) do not
# cover because they pre-seed the client config and stand in for the broker.
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
check "mosquitto is listening on $MPORT" "$mosq_up" "see $ROOT/log/mosquitto.log"
[ "$mosq_up" -eq 0 ] || exit 1
# Track the mosquitto PID (from its pid_file) so cleanup can stop it even if
# the install tree is later removed.
MOSQ_PID=$(cat "$ROOT/config/mosquitto/mosquitto.pid" 2>/dev/null)

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

# --- fresh client home: trust anchors + bootstrap config, NO pre-seeded
# --- UID/MQTT* (so registration must supply them). The SKEY is provisioned
# --- out of band (as on a real endpoint) so the broker accepts the request.
SKEY=$(dbq "select CVAL from SYSTEM.CONFIG where CKEY='SKEY';")
check "installer generated an SKEY" $([ -n "$SKEY" ]; echo $?)
mkdir -p "$HOME_TEST/config"
python3 - "$HOME_TEST" "$LPORT" "$SKEY" <<'EOF'
import sqlite3, sys
home, port, skey = sys.argv[1], sys.argv[2], sys.argv[3]
conn = sqlite3.connect(home + "/config/client.conf.db")
conn.execute("create table if not exists CONFIG (KEY text not null, VALUE text not null)")
for k, v in [("SHOST", "127.0.0.1"), ("SPORT", port), ("SVRKEY", skey)]:
    conn.execute("insert into CONFIG (KEY,VALUE) values (?,?)", (k, v))
conn.commit()
EOF
chmod 600 "$HOME_TEST/config/client.conf.db"
cp "$ROOT/config/ssl/server.crt" "$HOME_TEST/config/server.crt"
cp "$ROOT/config/ssl/server-signing.crt" "$HOME_TEST/config/server-signing.crt"

# The client binds IPC (10461) and the data channel (10704); both must be free.
port_busy=0
for p in 10461 10704; do
    if (exec 3<>/dev/tcp/127.0.0.1/$p) 2>/dev/null; then exec 3>&- 3<&- 2>/dev/null; port_busy=1; fi
done
check "client IPC/data ports are free" "$port_busy" "port 10461 or 10704 in use"

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
checkin_ok=1
for i in $(seq 1 40); do
    grep -q "\[mqtt\] status: UID $UID_C OK" "$BLOG" 2>/dev/null && { checkin_ok=0; break; }
    sleep 0.5
done
check "worker processed the client's MQTT check-in" "$checkin_ok" "see $BLOG"
cstate=$(dbq "select CSTATE from CLIENTS.STATUS where ID=$UID_C;")
check "STATUS.CSTATE is OK" $([ "$cstate" = "OK" ]; echo $?) "got: $cstate"

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

echo "------------------------------------------------------------"
if [ "$FAILURES" -gt 0 ]; then
    echo "FAILED: $FAILURES check(s) failed"
    echo "Artifacts left in $RUN for inspection (setup.log, client.log, broker.log, mosquitto.log)"
    exit 1
fi
echo "All checks passed."
exit 0
