#!/usr/bin/env bash
# Luminum Server configuration backup/restore (luminum-backup.pl):
# installs a scratch server against an isolated MariaDB, starts the
# services, exports a password-protected zip, and verifies the archive
# (wrong password rejected, right password lists the config tree +
# database dump + manifest, the dump carries the live data). It then
# mutates live state (a SYSTEM.CONFIG value and a config file), imports
# the archive, and verifies the restore brought both back and that the
# services were stopped and restarted (new broker PID, ports listening).
# The interactive password prompt is exercised through a pty (script).
#
# Usage: bash tests/backup_test.sh
set -u
REPO=$(cd "$(dirname "$0")/.." && pwd)
SETUP="$REPO/server/setup.pl"
PERL_LIBS="$REPO/server/lib${PERL5LIB:+:$PERL5LIB}"
# The installer requires root; this test drives it as an unprivileged
# user, so use the test escape hatch.
export LUMINUM_SETUP_ALLOW_NONROOT=1

# --- prerequisites -----------------------------------------------------------
for b in zip unzip mysqldump mysql mysqladmin mariadbd mariadb-install-db; do
    command -v "$b" >/dev/null 2>&1 || { echo "SKIP - $b not available"; exit 0; }
done
command -v script >/dev/null 2>&1 || { echo "SKIP - script(1) not available"; exit 0; }
PERL5LIB="$PERL_LIBS" perl -e 'use Luminum::Setup; use DBI;' 2>/dev/null \
    || { echo "SKIP - Perl dependencies for the installer are missing"; exit 0; }

# --- scratch layout (all under one dir, removed on clean exit) ---------------
RUN="$HOME/.lumbackup-test.$$"
DBDIR="$RUN/mariadb"
DBSOCK="$RUN/mysqld.sock"
DBPORT=33071
ROOT="$RUN/install"
LPORT=10465
WPORT=8443
MPORT=8883
SHOST=127.0.0.1
LADDR=127.0.0.1
ADMINPASS="consolepass123"
ZPASS="archivepass123"
FAILURES=0
MARIADB_PID=""

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

cleanup() {
    if [ -x "$ROOT/bin/stop-web" ]; then "$ROOT/bin/stop-web" >/dev/null 2>&1; fi
    if [ -x "$ROOT/bin/stop-broker" ]; then "$ROOT/bin/stop-broker" >/dev/null 2>&1; fi
    if [ -x "$ROOT/bin/stop-mosquitto" ]; then "$ROOT/bin/stop-mosquitto" >/dev/null 2>&1; fi
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

# Fail fast if something else already holds the service ports: a stale
# broker/mosquitto/nginx from a previous run would make the test
# pass/fail against the wrong processes.
for p in $LPORT $MPORT $WPORT; do
    if (exec 3<>/dev/tcp/127.0.0.1/$p) 2>/dev/null; then
        exec 3>&- 3<&- 2>/dev/null
        echo "FAIL - port $p is already in use; stop the stale service and re-run"
        exit 1
    fi
done

# --- isolated MariaDB (fresh datadir; keeps the test off the dev install) ---
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
[ -x "$ROOT/luminum-backup.pl" ] || { echo "FAIL - luminum-backup.pl was not synced to the install root"; exit 1; }
check "luminum-backup.pl was synced to the install root" $([ -x "$ROOT/luminum-backup.pl" ]; echo $?)

# --- start the services (web console, mosquitto, broker) ----------------------
"$ROOT/bin/start-mosquitto" > "$RUN/start-mosq.log" 2>&1
mosq_up=1
for i in $(seq 1 20); do
    if (exec 3<>/dev/tcp/127.0.0.1/$MPORT) 2>/dev/null; then exec 3>&- 3<&- 2>/dev/null; mosq_up=0; break; fi
    sleep 0.5
done
check "mosquitto is listening on $MPORT" "$mosq_up" "see $RUN/start-mosq.log"
[ "$mosq_up" -eq 0 ] || exit 1

"$ROOT/bin/start-broker" > "$RUN/start-broker.log" 2>&1
broker_up=1
for i in $(seq 1 30); do
    if (exec 3<>/dev/tcp/127.0.0.1/$LPORT) 2>/dev/null; then exec 3>&- 3<&- 2>/dev/null; broker_up=0; break; fi
    sleep 0.5
done
check "broker is listening on $LPORT" "$broker_up" "see $ROOT/log/broker.log"
[ "$broker_up" -eq 0 ] || exit 1
BROKER_PID=$(cat "$ROOT/run/broker.pid" 2>/dev/null)

"$ROOT/bin/start-web" > "$RUN/start-web.log" 2>&1
web_up=1
for i in $(seq 1 20); do
    if (exec 3<>/dev/tcp/127.0.0.1/$WPORT) 2>/dev/null; then exec 3>&- 3<&- 2>/dev/null; web_up=0; break; fi
    sleep 0.5
done
check "web console is listening on $WPORT" "$web_up" "see $RUN/start-web.log"
[ "$web_up" -eq 0 ] || exit 1

# --- baseline state ------------------------------------------------------------
SKEY=$(dbq "select CVAL from SYSTEM.CONFIG where CKEY='SKEY';")
check "installer generated an SKEY" $([ -n "$SKEY" ]; echo $?)
CHECKININT=$(dbq "select CVAL from SYSTEM.CONFIG where CKEY='CHECKININT';")
check "baseline CHECKININT is 5" $([ "$CHECKININT" = "5" ]; echo $?) "got: $CHECKININT"

# --- export (password via --password flag) -------------------------------------
perl "$ROOT/luminum-backup.pl" export --out "$RUN/backup.zip" --password "$ZPASS" \
    > "$RUN/export.log" 2>&1
check "export completed" $([ $? -eq 0 ]; echo $?) "see $RUN/export.log"
check "archive was created" $([ -s "$RUN/backup.zip" ]; echo $?)
perm=$(stat -c %a "$RUN/backup.zip" 2>/dev/null)
check "archive is mode 0600" $([ "$perm" = "600" ]; echo $?) "got: $perm"

# --- archive integrity -----------------------------------------------------------
# (unzip -l only reads the central directory and needs no password, so the
# wrong-password check must attempt a real extraction.)
mkdir -p "$RUN/wrongpw"
unzip -o -q -P "wrongpass" "$RUN/backup.zip" -d "$RUN/wrongpw" > /dev/null 2>&1
check "wrong password is rejected" $([ $? -ne 0 ]; echo $?)
unzip -P "$ZPASS" -l "$RUN/backup.zip" > "$RUN/ziplist.txt" 2>&1
check "right password lists the archive" $([ $? -eq 0 ]; echo $?)
grep -q "config/broker.conf" "$RUN/ziplist.txt"
check "archive contains config/broker.conf" "$?"
grep -q "config/console.conf" "$RUN/ziplist.txt"
check "archive contains config/console.conf" "$?"
grep -q "config/ssl/server.crt" "$RUN/ziplist.txt"
check "archive contains config/ssl/server.crt" "$?"
grep -q "config/ssl/server.key" "$RUN/ziplist.txt"
check "archive contains config/ssl/server.key" "$?"
grep -q "config/mosquitto/mosquitto.conf" "$RUN/ziplist.txt"
check "archive contains config/mosquitto/mosquitto.conf" "$?"
grep -q "database.sql" "$RUN/ziplist.txt"
check "archive contains database.sql" "$?"
grep -q "manifest.txt" "$RUN/ziplist.txt"
check "archive contains manifest.txt" "$?"

XDIR="$RUN/extract"
mkdir -p "$XDIR"
unzip -q -P "$ZPASS" "$RUN/backup.zip" -d "$XDIR"
check "archive extracts cleanly" $([ $? -eq 0 ]; echo $?)
grep -q "CREATE DATABASE" "$XDIR/database.sql"
check "dump contains CREATE DATABASE statements" "$?"
grep -q "$SKEY" "$XDIR/database.sql"
check "dump carries the live SKEY value" "$?"
[ -f "$XDIR/config/ssl/server.key" ]
check "extracted config tree carries the private key" "$?"

# --- export (password via the interactive prompt, driven through a pty) --------
printf '%s\n' "$ZPASS" | timeout 120 script -qec \
    "perl '$ROOT/luminum-backup.pl' export --out '$RUN/backup-prompt.zip'" \
    /dev/null > "$RUN/prompt.log" 2>&1
check "prompted export completed" $([ $? -eq 0 ]; echo $?) "see $RUN/prompt.log"
unzip -P "$ZPASS" -l "$RUN/backup-prompt.zip" > /dev/null 2>&1
check "prompted archive opens with the typed password" $([ $? -eq 0 ]; echo $?)

# --- mutate live state, then import ---------------------------------------------
dbq "update SYSTEM.CONFIG set CVAL='7' where CKEY='CHECKININT';"
MUTED=$(dbq "select CVAL from SYSTEM.CONFIG where CKEY='CHECKININT';")
check "CHECKININT mutated to 7" $([ "$MUTED" = "7" ]; echo $?) "got: $MUTED"
echo "# backup-test-marker" >> "$ROOT/config/broker.conf"
grep -q "backup-test-marker" "$ROOT/config/broker.conf"
check "marker line added to broker.conf" "$?"

perl "$ROOT/luminum-backup.pl" import "$RUN/backup.zip" --password "$ZPASS" \
    > "$RUN/import.log" 2>&1
check "import completed" $([ $? -eq 0 ]; echo $?) "see $RUN/import.log"

RESTORED=$(dbq "select CVAL from SYSTEM.CONFIG where CKEY='CHECKININT';")
check "CHECKININT restored to 5" $([ "$RESTORED" = "5" ]; echo $?) "got: $RESTORED"
grep -q "backup-test-marker" "$ROOT/config/broker.conf"
check "marker line gone from broker.conf" $([ $? -ne 0 ]; echo $?)

# --- services were stopped and restarted -----------------------------------------
broker_up=1
for i in $(seq 1 30); do
    if (exec 3<>/dev/tcp/127.0.0.1/$LPORT) 2>/dev/null; then exec 3>&- 3<&- 2>/dev/null; broker_up=0; break; fi
    sleep 0.5
done
check "broker is listening again after import" "$broker_up" "see $ROOT/log/broker.log"
mosq_up=1
for i in $(seq 1 20); do
    if (exec 3<>/dev/tcp/127.0.0.1/$MPORT) 2>/dev/null; then exec 3>&- 3<&- 2>/dev/null; mosq_up=0; break; fi
    sleep 0.5
done
check "mosquitto is listening again after import" "$mosq_up"
web_up=1
for i in $(seq 1 20); do
    if (exec 3<>/dev/tcp/127.0.0.1/$WPORT) 2>/dev/null; then exec 3>&- 3<&- 2>/dev/null; web_up=0; break; fi
    sleep 0.5
done
check "web console is listening again after import" "$web_up"
NEW_BROKER_PID=$(cat "$ROOT/run/broker.pid" 2>/dev/null)
check "broker was restarted (new PID)" $([ -n "$NEW_BROKER_PID" ] && [ "$NEW_BROKER_PID" != "$BROKER_PID" ]; echo $?) \
    "old: $BROKER_PID new: $NEW_BROKER_PID"

# --- import with the wrong password fails without touching the install ----------
# Re-mutate so a (failed) wrong-password import would be detectable if it
# proceeded, then verify the mutation survives the failed import.
dbq "update SYSTEM.CONFIG set CVAL='9' where CKEY='CHECKININT';"
perl "$ROOT/luminum-backup.pl" import "$RUN/backup.zip" --password "wrongpass" \
    > "$RUN/import-bad.log" 2>&1
check "wrong-password import fails" $([ $? -ne 0 ]; echo $?)
BAD=$(dbq "select CVAL from SYSTEM.CONFIG where CKEY='CHECKININT';")
check "failed import left the database untouched" $([ "$BAD" = "9" ]; echo $?) "got: $BAD"
# ... and the services are still the ones the good import started.
SAME_PID=$(cat "$ROOT/run/broker.pid" 2>/dev/null)
check "failed import did not restart the broker" $([ "$SAME_PID" = "$NEW_BROKER_PID" ]; echo $?) \
    "expected: $NEW_BROKER_PID got: $SAME_PID"
# Restore the baseline so cleanup's stop scripts act on a healthy state.
dbq "update SYSTEM.CONFIG set CVAL='5' where CKEY='CHECKININT';"

# --- summary ----------------------------------------------------------------------
echo
if [ "$FAILURES" -gt 0 ]; then
    echo "backup_test: $FAILURES check(s) FAILED"
    exit 1
fi
echo "backup_test: all checks passed"
