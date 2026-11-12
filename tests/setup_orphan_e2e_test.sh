#!/usr/bin/env bash
# setup_orphan_e2e_test.sh - regression test for the installer's
# orphan-broker recovery (Luminum::Setup::stop_running_broker).
#
# A broker left running whose pid file is missing or lost is invisible to
# the stop script's pid-file path yet still holds the listener port, so
# re-runs died at the pre-start probe with "port already in use" while the
# stop scripts reported "no pid file".
#
# This test reproduces that state end to end against a scratch MariaDB:
#   1. provision an install (--no-start)
#   2. start mosquitto and a broker MANUALLY (no start script); the broker
#      writes its own pid file once the listener is bound - verify that,
#      then delete the file to reproduce the lost-pid-file state
#   2b. start a FOREIGN nginx (a different config, like the distro's) on
#       the web port - "nginx -c <our conf> -s quit" cannot reach it
#   3. re-run the installer with start=1
# and checks that the orphan and the foreign nginx are stopped and the
# install completes with all services listening.
#
# Usage: bash tests/setup_orphan_e2e_test.sh
set -u
REPO=$(cd "$(dirname "$0")/.." && pwd)
SETUP="$REPO/server/setup.pl"
PERL_LIBS="$REPO/server/lib${PERL5LIB:+:$PERL5LIB}"
# The installer requires root; this test drives it as an unprivileged
# user, so use the test escape hatch.
export LUMINUM_SETUP_ALLOW_NONROOT=1

# --- prerequisites -----------------------------------------------------------
[ -x "$(command -v mosquitto)" ]          || { echo "SKIP - mosquitto not available"; exit 0; }
[ -x "$(command -v mariadbd)" ]           || { echo "SKIP - mariadbd not available"; exit 0; }
[ -x "$(command -v mariadb-install-db)" ] || { echo "SKIP - mariadb-install-db not available"; exit 0; }
[ -x "$(command -v openssl)" ]            || { echo "SKIP - openssl not available"; exit 0; }
command -v nginx >/dev/null 2>&1 || [ -x /usr/sbin/nginx ] \
    || { echo "SKIP - nginx not available"; exit 0; }
# ls exits nonzero if ANY glob is unmatched, so test the output instead.
phpfpm=$(ls /usr/sbin/php-fpm* /usr/local/sbin/php-fpm* 2>/dev/null | head -n1)
[ -n "$phpfpm" ] || { echo "SKIP - php-fpm not available"; exit 0; }
PERL5LIB="$PERL_LIBS" perl -e 'use Luminum::Setup;' 2>/dev/null \
    || { echo "SKIP - Perl dependencies for the installer are missing"; exit 0; }

# --- scratch layout (all under one dir, removed on clean exit) ---------------
# $HOME, not /tmp: /tmp is noexec in some containers and the generated
# start/stop scripts must be executable.
RUN="$HOME/.lum-orphan-e2e-test.$$"
DBDIR="$RUN/mariadb"
DBSOCK="$RUN/mysqld.sock"
DBPORT=33073
ROOT="$RUN/install"
LPORT=10465
WPORT=8443
MPORT=8883
SHOST=127.0.0.1
LADDR=127.0.0.1
FAILURES=0
MARIADB_PID=""; MOSQ_PID=""; ORPHAN_PID=""; NEW_BROKER_PID=""

check() {
    local name="$1" ok="$2" detail="${3:-}"
    if [ "$ok" -eq 0 ]; then
        echo "ok   - $name"
    else
        FAILURES=$((FAILURES + 1))
        echo "FAIL - $name${detail:+ ($detail)}"
    fi
}

# The connect happens in a subshell, so its fd 3 dies with it; the main
# shell must not touch fd 3 (an "exec 3>&- 2>/dev/null" there would
# permanently redirect the shell's stderr to /dev/null).
port_open() {
    (exec 3<>/dev/tcp/127.0.0.1/"$1") 2>/dev/null
}

cleanup() {
    [ -n "$NEW_BROKER_PID" ] && kill "$NEW_BROKER_PID" 2>/dev/null
    [ -n "$ORPHAN_PID" ] && kill "$ORPHAN_PID" 2>/dev/null
    # Command-line fallback: a broker whose pid file was lost is exactly
    # what this test is about, so the stop scripts alone may not reach it.
    pkill -f "$ROOT/broker\.pl" 2>/dev/null
    if [ -d "$ROOT/bin" ]; then
        "$ROOT/bin/stop-broker" 2>/dev/null
        "$ROOT/bin/stop-mosquitto" 2>/dev/null
        "$ROOT/bin/stop-web" 2>/dev/null
    fi
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

# Fail fast if a stale service from a previous run holds a fixed port.
for p in $LPORT $MPORT $WPORT; do
    if port_open "$p"; then
        echo "FAIL - port $p is already in use; stop the stale service and re-run"
        exit 1
    fi
done

mkdir -p "$RUN" || exit 1

# --- isolated MariaDB ---------------------------------------------------------
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

# --- 1. provision an install (services not started) ---------------------------
PERL5LIB="$PERL_LIBS" perl "$SETUP" --noninteractive --yes --no-start \
    --install-root "$ROOT" \
    --shost "$SHOST" --laddr "$LADDR" --lport $LPORT --wport $WPORT \
    --dbsocket "$DBSOCK" --dbadmin root \
    --perl5lib "$PERL_LIBS" \
    --srcdir "$REPO/server" \
    > "$RUN/setup1.log" 2>&1
check "installer completed (provisioning)" $([ $? -eq 0 ]; echo $?) "see $RUN/setup1.log"

# --- 2. the orphan: mosquitto + a broker started manually, NO pid file -------
"$ROOT/bin/start-mosquitto" > "$RUN/start-mosq.log" 2>&1
mosq_up=1
for i in $(seq 1 20); do
    if port_open "$MPORT"; then mosq_up=0; break; fi
    sleep 0.5
done
check "mosquitto is listening on $MPORT" "$mosq_up" "see $RUN/start-mosq.log"
[ "$mosq_up" -eq 0 ] || exit 1
MOSQ_PID=$(cat "$ROOT/config/mosquitto/mosquitto.pid" 2>/dev/null)

cd "$ROOT"
PERL5LIB="$PERL_LIBS" nohup perl broker.pl > "$RUN/orphan-broker.log" 2>&1 &
ORPHAN_PID=$!
orphan_up=1
for i in $(seq 1 30); do
    if port_open "$LPORT"; then orphan_up=0; break; fi
    sleep 0.5
done
check "orphan broker is listening on $LPORT" "$orphan_up" "see $RUN/orphan-broker.log"
[ "$orphan_up" -eq 0 ] || exit 1
# The broker writes its own pid file once the listener is bound, so a
# manual start is visible to the stop script; the PID in it must be live.
ORPHAN_SELF_PID=$(cat "$ROOT/run/broker.pid" 2>/dev/null)
check "orphan broker wrote its own pid file with a live PID" \
    $([ -n "$ORPHAN_SELF_PID" ] && kill -0 "$ORPHAN_SELF_PID" 2>/dev/null; echo $?)
# Delete the file to reproduce the lost-pid-file state the command-line
# fallback must recover from.
rm -f "$ROOT/run/broker.pid"
check "no broker pid file exists" $([ ! -f "$ROOT/run/broker.pid" ]; echo $?)

# --- 2b. a foreign nginx on the web port (another config, like the distro's) -
# stop-web's "nginx -c <our conf> -s quit" cannot reach it (different pid
# file); the installer's command-line fallback must stop it so the new
# nginx can bind the web port.
WCONF="$RUN/foreign-nginx.conf"
cat > "$WCONF" <<NGINX
pid $RUN/foreign-nginx.pid;
error_log $RUN/foreign-nginx.log;
events {}
http {
    access_log off;
    client_body_temp_path $RUN/nginx-tmp/client;
    proxy_temp_path $RUN/nginx-tmp/proxy;
    fastcgi_temp_path $RUN/nginx-tmp/fastcgi;
    uwsgi_temp_path $RUN/nginx-tmp/uwsgi;
    scgi_temp_path $RUN/nginx-tmp/scgi;
    server {
        listen 127.0.0.1:$WPORT;
        return 200;
    }
}
NGINX
mkdir -p "$RUN/nginx-tmp"
nginx -c "$WCONF" > "$RUN/foreign-nginx-start.log" 2>&1
fng_up=1
for i in $(seq 1 20); do
    if port_open "$WPORT"; then fng_up=0; break; fi
    sleep 0.5
done
check "foreign nginx is listening on $WPORT" "$fng_up" "see $RUN/foreign-nginx-start.log"
[ "$fng_up" -eq 0 ] || exit 1
FNG_PID=$(cat "$RUN/foreign-nginx.pid" 2>/dev/null)

# --- 3. re-run the installer with start=1 -------------------------------------
PERL5LIB="$PERL_LIBS" perl "$SETUP" --noninteractive --yes \
    --install-root "$ROOT" \
    --shost "$SHOST" --laddr "$LADDR" --lport $LPORT --wport $WPORT \
    --dbsocket "$DBSOCK" --dbadmin root \
    --perl5lib "$PERL_LIBS" \
    --srcdir "$REPO/server" \
    > "$RUN/setup2.log" 2>&1
rc=$?
check "installer re-run completed" $([ $rc -eq 0 ]; echo $rc) "see $RUN/setup2.log"
# The installed stop script's command-line fallback reaches the orphan
# (relative start, working directory at the install root), so the
# installer's own pgrep layer is not needed here.
check "installer stopped the orphan" \
    $(grep -q 'Stopping existing Luminum broker' "$RUN/setup2.log"; echo $?)
# The orphan is our child; bash reaps dead background jobs, so once it is
# gone /proc/$ORPHAN_PID disappears (an alive or unreaped zombie keeps it).
orphan_gone=1
for i in $(seq 1 40); do
    [ ! -d "/proc/$ORPHAN_PID" ] && { orphan_gone=0; break; }
    sleep 0.25
done
check "orphan broker process is gone" "$orphan_gone" "PID $ORPHAN_PID still present"
# The foreign nginx is not our child (nginx daemonizes), so an unreaped
# zombie is possible: an empty cmdline means dead either way.
check "installer stopped the foreign nginx" \
    $(grep -q 'Stopping existing Luminum web console' "$RUN/setup2.log"; echo $?)
fng_gone=1
for i in $(seq 1 40); do
    if [ ! -d "/proc/$FNG_PID" ] || [ ! -s "/proc/$FNG_PID/cmdline" ]; then
        fng_gone=0; break;
    fi
    sleep 0.25
done
check "foreign nginx process is gone" "$fng_gone" "PID $FNG_PID still present"

# --- the new install is up -----------------------------------------------------
NEW_BROKER_PID=$(cat "$ROOT/run/broker.pid" 2>/dev/null)
check "new broker pid file was written" $([ -n "$NEW_BROKER_PID" ]; echo $?)
l_up=1; m_up=1; w_up=1
for i in $(seq 1 20); do
    port_open "$LPORT" && l_up=0
    port_open "$MPORT" && m_up=0
    port_open "$WPORT" && w_up=0
    [ "${l_up}${m_up}${w_up}" = "000" ] && break
    sleep 0.5
done
check "broker is listening on $LPORT" "$l_up"
check "mosquitto is listening on $MPORT" "$m_up"
check "web console is listening on $WPORT" "$w_up"
check "installer printed the completion summary" \
    $(grep -q 'Luminum Server installed at' "$RUN/setup2.log"; echo $?)

echo "------------------------------------------------------------"
if [ "$FAILURES" -gt 0 ]; then
    echo "FAILED: $FAILURES check(s) failed"
    echo "Artifacts left in $RUN for inspection (setup1.log, setup2.log, orphan-broker.log; broker log: $ROOT/log/broker.log)"
    exit 1
fi
echo "All checks passed."
exit 0
