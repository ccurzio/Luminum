#!/usr/bin/env bash
# Console deregistration endpoint test (protocol 6.1): serves the real
# server/console/html/api/deregister.php through PHP's built-in web server
# against a scratch MariaDB (the same /tmp/mysqld.sock test database the
# other DB-backed tests use) and verifies the endpoint's gates end to end:
#   - an unauthenticated request is a 401 (the _init.php session gate)
#   - a POST without the session's CSRF token is a 403 (CSRF gate)
#   - a non-Administrator session is a 403 (role gate: only ROLE = 1)
#   - an unknown target is a 404, an invalid target a 400
#   - an already-deactivated client (CSTATE = 'DEACT', the client-initiated
#     path) is accepted and queued: the console's Deregister removes the
#     record the deactivation left behind
#   - a valid request queues exactly one PENDING row in CLIENTS.DEREGS
#     (the broker's MQTT worker performs the removal) and a repeat
#     request is idempotent (ok, queued=false, no duplicate row)
#   - a non-POST request is a 405
#
# The AUTH.USERS / AUTH.SESSION / CLIENTS.STATUS rows are seeded with high
# IDs and a PID-qualified session id so a shared test database is left
# exactly as found (only this test's rows are removed on cleanup).
#
# Usage: bash tests/console_deregister_test.sh
set -u
REPO=$(cd "$(dirname "$0")/.." && pwd)
[ -x "$(command -v php)" ]   || { echo "SKIP - php not available"; exit 0; }
php -m 2>/dev/null | grep -q '^mysqli$' || { echo "SKIP - PHP mysqli extension not available"; exit 0; }
[ -x "$(command -v curl)" ]  || { echo "SKIP - curl not available"; exit 0; }
[ -x "$(command -v mysql)" ] || { echo "SKIP - mysql client not available"; exit 0; }
[ -S /tmp/mysqld.sock ]      || { echo "SKIP - MariaDB not running at /tmp/mysqld.sock"; exit 0; }

PORT=14667
DBSOCK=/tmp/mysqld.sock
# High IDs keep the seeded rows clear of any real data in a shared test DB.
UID_ADMIN=980101
UID_POWER=980102
UID_OK=980201
UID_DEACT=980202
SID_ADMIN="dreg${UID_ADMIN}a"
SID_POWER="dreg${UID_POWER}b"

SCRATCH="$HOME/.lumconsole-dereg-test.$$"
FAILURES=0
PHP_PID=""
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
    [ -n "$PHP_PID" ] && kill "$PHP_PID" 2>/dev/null
    mysql --socket="$DBSOCK" -u root -e \
        "delete from AUTH.SESSION where SID in ('$SID_ADMIN','$SID_POWER');
         delete from AUTH.USERS where ID in ($UID_ADMIN,$UID_POWER);
         delete from CLIENTS.DEREGS where UID in ($UID_OK,$UID_DEACT);
         delete from CLIENTS.STATUS where ID in ($UID_OK,$UID_DEACT);
         drop user if exists '${DBUSER:-dregtest}'@'localhost';" 2>/dev/null
    # Leave the scratch dir (responses, server log) behind on failure so the
    # run can be inspected; remove it on success.
    if [ "$FAILURES" -gt 0 ]; then
        echo "Artifacts left in $SCRATCH for inspection."
    else
        rm -rf "$SCRATCH"
    fi
}
trap cleanup EXIT

dbq() {
    mysql --socket="$DBSOCK" -u root -N -e "$1" 2>/dev/null
}

mkdir -p "$SCRATCH" || exit 1

# --- scratch database: the endpoint hardcodes the AUTH and CLIENTS database
# --- names, so the tables must live there. create-if-not-exists + unique
# --- seed IDs keep a shared test database usable by other tests. The PHP
# --- side connects as a dedicated user (layout/db.php's conf parser cannot
# --- express an empty password, so root's blank one would not work).
DBUSER="dregtest"
DBPASS="dregtestpw"
dbq "create user if not exists '$DBUSER'@'localhost' identified by '$DBPASS';
     grant all privileges on *.* to '$DBUSER'@'localhost';
     create database if not exists AUTH default character set utf8mb4 collate utf8mb4_general_ci;
     create database if not exists CLIENTS default character set utf8mb4 collate utf8mb4_general_ci;"
dbq "use AUTH;
     create table if not exists SESSION (
       ID int(20) not null,
       SID tinytext not null,
       START timestamp not null,
       EXPIRES timestamp null default null
     ) engine=InnoDB default charset=utf8mb4 collate=utf8mb4_general_ci;
     create table if not exists USERS (
       ID int(20) not null auto_increment,
       USERNAME tinytext not null,
       FULLNAME tinytext not null,
       PASSWORD tinytext not null,
       EMAIL tinytext default null,
       PHONE tinytext not null,
       TYPE tinytext not null,
       ROLE tinyint(4) default null,
       REGDATE datetime not null,
       LASTSEEN datetime default null,
       ENABLED tinyint(4) not null default 1,
       CHANGEPASS tinyint(1) not null default 0,
       primary key (ID)
     ) engine=InnoDB default charset=utf8mb4 collate=utf8mb4_general_ci;
     delete from SESSION where SID in ('$SID_ADMIN','$SID_POWER');
     delete from USERS where ID in ($UID_ADMIN,$UID_POWER);
     insert into USERS (ID,USERNAME,FULLNAME,PASSWORD,PHONE,TYPE,ROLE,REGDATE,ENABLED)
       values ($UID_ADMIN,'dregadmin','Dereg Admin','x','', 'console',1,now(),1),
              ($UID_POWER,'dregpower','Dereg Power','x','','console',2,now(),1);
     insert into SESSION (ID,SID,START,EXPIRES)
       values ($UID_ADMIN,'$SID_ADMIN',now(),date_add(now(),interval 1 hour)),
              ($UID_POWER,'$SID_POWER',now(),date_add(now(),interval 1 hour));
     use CLIENTS;
     create table if not exists STATUS (
       ID int(20) not null,
       HOSTNAME tinytext not null,
       IPV4 tinytext not null,
       IPV6 tinytext default null,
       OSPLATFORM tinytext not null,
       OSRELEASE tinytext not null,
       CLIENTVER tinytext not null,
       CSTATE tinytext not null,
       INGROUPS text default null,
       REGDATE datetime not null,
       LASTSEEN datetime default null,
       MISSING tinyint(1) default 0,
       primary key (ID)
     ) engine=InnoDB default charset=utf8mb4 collate=utf8mb4_general_ci;
     create table if not exists DEREGS (
       ID int(20) not null auto_increment,
       UID int(20) not null,
       REQUESTED datetime not null,
       STATUS tinytext not null default 'PENDING',
       DONE datetime default null,
       primary key (ID),
       key IDX_DEREGS_STATUS (STATUS)
     ) engine=InnoDB default charset=utf8mb4 collate=utf8mb4_general_ci;
     delete from STATUS where ID in ($UID_OK,$UID_DEACT);
     delete from DEREGS where UID in ($UID_OK,$UID_DEACT);
     insert into STATUS (ID,HOSTNAME,IPV4,OSPLATFORM,OSRELEASE,CLIENTVER,CSTATE,REGDATE)
       values ($UID_OK,'dreg-ok-host','10.0.0.1','Linux','Debian 12','0.0.1','OK',now()),
              ($UID_DEACT,'dreg-deact-host','10.0.0.2','Linux','Debian 12','0.0.1','DEACT',now());" \
    || { echo "SKIP - could not seed the scratch database"; exit 0; }

# --- console.conf for the built-in server (layout/db.php reads dbuser/dbpass)
cat > "$SCRATCH/console.conf" <<EOF
dbuser = $DBUSER
dbpass = $DBPASS
EOF

# --- router: a test-only session seeder plus pass-through to the real
# --- console files. /__test_session starts a PHP session carrying the given
# --- AUTH.SESSION SID (and the CSRF token the endpoint's gate expects) and
# --- answers with the session id and token.
cat > "$SCRATCH/router.php" <<'PHP'
<?php
$uri = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
if ($uri === '/__test_session') {
    require getenv('CONSOLE_HTML') . '/layout/csrf.php';
    session_start();
    $_SESSION['SID'] = $_GET['sid'];
    luminum_csrf_token();
    header('Content-Type: application/json');
    echo json_encode(['session' => session_id(), 'csrf' => $_SESSION['CSRF']]);
    return true;
}
$file = getenv('CONSOLE_HTML') . $uri;
if ($uri !== '/' && is_file($file)) {
    if (substr($file, -4) === '.php') {
        chdir(dirname($file));
        require $file;
        return true;
    }
    return false;
}
http_response_code(404);
echo 'not found';
PHP

LUMINUM_CONSOLE_CONF="$SCRATCH/console.conf" \
LUMINUM_DB_SOCKET="$DBSOCK" \
CONSOLE_HTML="$REPO/server/console/html" \
php -S "127.0.0.1:$PORT" "$SCRATCH/router.php" > "$SCRATCH/php-server.log" 2>&1 &
PHP_PID=$!
web_up=1
for i in $(seq 1 20); do
    if (exec 3<>/dev/tcp/127.0.0.1/$PORT) 2>/dev/null; then exec 3>&- 3<&- 2>/dev/null; web_up=0; break; fi
    sleep 0.25
done
check "built-in server is listening on $PORT" "$web_up" "see $SCRATCH/php-server.log"
[ "$web_up" -eq 0 ] || exit 1

BASE="http://127.0.0.1:$PORT"
JAR_ADMIN="$SCRATCH/cookies-admin"
JAR_POWER="$SCRATCH/cookies-power"

# Seed the two PHP sessions (admin ROLE=1, power user ROLE=2).
ADMIN_JSON=$(curl -s -c "$JAR_ADMIN" "$BASE/__test_session?sid=$SID_ADMIN")
POWER_JSON=$(curl -s -c "$JAR_POWER" "$BASE/__test_session?sid=$SID_POWER")
ADMIN_CSRF=$(printf '%s' "$ADMIN_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin)["csrf"])' 2>/dev/null)
POWER_CSRF=$(printf '%s' "$POWER_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin)["csrf"])' 2>/dev/null)
check "admin PHP session seeded with a CSRF token" $([ -n "$ADMIN_CSRF" ]; echo $?) "got: $ADMIN_JSON"
check "power-user PHP session seeded with a CSRF token" $([ -n "$POWER_CSRF" ]; echo $?) "got: $POWER_JSON"

post() {
    # $1 = cookie jar, $2 = csrf header value (may be empty), $3 = JSON body
    curl -s -o "$SCRATCH/last.json" -w '%{http_code}' -b "$1" \
        -H "Content-Type: application/json" \
        ${2:+-H "X-CSRF-Token: $2"} \
        --data "$3" "$BASE/api/deregister.php"
}

# --- gate 1: the session gate (no PHP session cookie at all) ---------------
code=$(curl -s -o "$SCRATCH/last.json" -w '%{http_code}' \
    -H "Content-Type: application/json" --data "{\"target\": \"$UID_OK\"}" \
    "$BASE/api/deregister.php")
check "unauthenticated POST rejected (401)" $([ "$code" = "401" ]; echo $?) "got: $code $(cat "$SCRATCH/last.json")"

# --- gate 2: the CSRF gate ---------------------------------------------------
code=$(post "$JAR_ADMIN" "" "{\"target\": \"$UID_OK\"}")
check "POST without the CSRF token rejected (403)" $([ "$code" = "403" ]; echo $?) "got: $code $(cat "$SCRATCH/last.json")"
check "the CSRF rejection names the token" $(grep -q 'Invalid or missing CSRF token' "$SCRATCH/last.json"; echo $?)
code=$(post "$JAR_ADMIN" "deadbeef" "{\"target\": \"$UID_OK\"}")
check "POST with a foreign CSRF token rejected (403)" $([ "$code" = "403" ]; echo $?) "got: $code $(cat "$SCRATCH/last.json")"
# The power user's own valid token does not help: the role gate still fails,
# and with a different message than the CSRF gate's.
code=$(post "$JAR_POWER" "$POWER_CSRF" "{\"target\": \"$UID_OK\"}")
check "non-administrator rejected (403)" $([ "$code" = "403" ]; echo $?) "got: $code $(cat "$SCRATCH/last.json")"
check "the role rejection names the Administrator role" $(grep -q 'Administrator role required' "$SCRATCH/last.json"; echo $?)

# --- target validation --------------------------------------------------------
code=$(post "$JAR_ADMIN" "$ADMIN_CSRF" "{\"target\": \"980999\"}")
check "unknown client rejected (404)" $([ "$code" = "404" ]; echo $?) "got: $code $(cat "$SCRATCH/last.json")"
code=$(post "$JAR_ADMIN" "$ADMIN_CSRF" "{\"target\": \"abc\"}")
check "non-numeric target rejected (400)" $([ "$code" = "400" ]; echo $?) "got: $code $(cat "$SCRATCH/last.json")"
code=$(post "$JAR_ADMIN" "$ADMIN_CSRF" "{\"target\": \"1; drop table STATUS\"}")
check "injection-style target rejected (400)" $([ "$code" = "400" ]; echo $?) "got: $code $(cat "$SCRATCH/last.json")"
code=$(post "$JAR_ADMIN" "$ADMIN_CSRF" "{\"target\": \"$UID_DEACT\"}")
check "already-deactivated client accepted (200)" $([ "$code" = "200" ]; echo $?) "got: $code $(cat "$SCRATCH/last.json")"
python3 - "$SCRATCH/last.json" "$UID_DEACT" <<'EOF'
import json, sys
data = json.load(open(sys.argv[1]))
assert data == {"ok": True, "queued": True, "target": sys.argv[2]}, data
EOF
check "deactivated client answers ok/queued" $? "$(cat "$SCRATCH/last.json")"
check "a PENDING row was queued for the deactivated client" \
    $([ "$(dbq "select count(*) from CLIENTS.DEREGS where UID=$UID_DEACT and STATUS='PENDING';")" = "1" ]; echo $?)

# --- the happy path: one PENDING row is queued --------------------------------
code=$(post "$JAR_ADMIN" "$ADMIN_CSRF" "{\"target\": \"$UID_OK\"}")
check "valid request accepted (200)" $([ "$code" = "200" ]; echo $?) "got: $code $(cat "$SCRATCH/last.json")"
python3 - "$SCRATCH/last.json" "$UID_OK" <<'EOF'
import json, sys
data = json.load(open(sys.argv[1]))
assert data == {"ok": True, "queued": True, "target": sys.argv[2]}, data
EOF
check "response is ok/queued with the target" $? "$(cat "$SCRATCH/last.json")"
check "a PENDING row was queued in CLIENTS.DEREGS" \
    $([ "$(dbq "select count(*) from CLIENTS.DEREGS where UID=$UID_OK and STATUS='PENDING';")" = "1" ]; echo $?)

# --- idempotency: a repeat request does not duplicate the queue ---------------
code=$(post "$JAR_ADMIN" "$ADMIN_CSRF" "{\"target\": \"$UID_OK\"}")
check "repeat request accepted (200)" $([ "$code" = "200" ]; echo $?) "got: $code $(cat "$SCRATCH/last.json")"
python3 - "$SCRATCH/last.json" "$UID_OK" <<'EOF'
import json, sys
data = json.load(open(sys.argv[1]))
assert data == {"ok": True, "queued": False, "target": sys.argv[2]}, data
EOF
check "repeat answers queued=false" $? "$(cat "$SCRATCH/last.json")"
check "still exactly one PENDING row" \
    $([ "$(dbq "select count(*) from CLIENTS.DEREGS where UID=$UID_OK and STATUS='PENDING';")" = "1" ]; echo $?)

# --- method gate ----------------------------------------------------------------
code=$(curl -s -o "$SCRATCH/last.json" -w '%{http_code}' -b "$JAR_ADMIN" \
    -H "X-CSRF-Token: $ADMIN_CSRF" "$BASE/api/deregister.php")
check "GET rejected (405)" $([ "$code" = "405" ]; echo $?) "got: $code $(cat "$SCRATCH/last.json")"

echo "------------------------------------------------------------"
if [ "$FAILURES" -gt 0 ]; then
    echo "FAILED: $FAILURES check(s) failed"
    exit 1
fi
echo "All checks passed."
exit 0
