#!/usr/bin/env bash
# luminum-config.pl test: drives the CLI configuration tool against its own
# isolated scratch MariaDB (a fresh datadir + socket, so the shared test
# instance is untouched) carrying a SYSTEM.CONFIG table. Verifies:
#   - get of a seeded value and of an unseeded key ("(not set)")
#   - set of a valid value, persisted to the DB
#   - set normalizes enum case (required -> Required)
#   - set of multiple KEY=VALUE pairs in one call
#   - set upserts a key the installer did not seed (PASSKEYS)
#   - duration validation (UTIMEOUT=30M)
#   - an out-of-range value is rejected (rc 1) and nothing is written
#   - a mixed valid+invalid set is all-or-nothing (the valid one is not written)
#   - an unknown key and a malformed pair are rejected
#   - get of multiple keys, list output, and --help
#
# Usage: bash tests/config_cli_test.sh
set -u
REPO=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT="$REPO/server/luminum-config.pl"

[ -x "$(command -v mariadbd)" ]           || { echo "SKIP - mariadbd not available"; exit 0; }
[ -x "$(command -v mariadb-install-db)" ] || { echo "SKIP - mariadb-install-db not available"; exit 0; }
[ -x "$(command -v mysql)" ]              || { echo "SKIP - mysql client not available"; exit 0; }
PERL_LIBS="$REPO/server/lib${PERL5LIB:+:$PERL5LIB}"
PERL5LIB="$PERL_LIBS" perl -e 'use DBI; use DBD::mysql;' 2>/dev/null \
    || { echo "SKIP - Perl DBI/DBD::mysql missing"; exit 0; }

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

# --- isolated scratch MariaDB -------------------------------------------------
DATADIR="$HOME/.lumconfig-test.$$"
SOCK="/tmp/lumconfig-test-$$"
MARIADBD_PID=""

cleanup() {
    [ -n "$MARIADBD_PID" ] && kill "$MARIADBD_PID" 2>/dev/null
    wait "$MARIADBD_PID" 2>/dev/null
    rm -rf "$DATADIR"
}
trap cleanup EXIT

mariadb-install-db --no-defaults --datadir="$DATADIR" --auth-root-authentication-method=normal >/dev/null 2>&1
mariadbd --no-defaults --datadir="$DATADIR" --socket="$SOCK" --skip-networking >/dev/null 2>&1 &
MARIADBD_PID=$!

for _ in $(seq 1 50); do
    [ -S "$SOCK" ] && break
    sleep 0.2
done
[ -S "$SOCK" ] || { echo "SKIP - scratch MariaDB did not start"; exit 0; }

m() { mysql --no-defaults --socket="$SOCK" -u root -N -e "$1" 2>/dev/null; }

# --- SYSTEM.CONFIG -------------------------------------------------------------
m "create database if not exists SYSTEM default character set utf8mb4"
m "create table if not exists SYSTEM.CONFIG (CKEY tinytext not null, CVAL tinytext not null)"
# Seed a subset of the installer's defaults; the rest stay unseeded on purpose
# so the upsert path (PASSKEYS) and the "(not set)" path (PNETCHECK) are tested.
m "insert into SYSTEM.CONFIG (CKEY,CVAL) values
   ('CHECKININT','5'),('MISSINGAFTER','90'),('TARGETCONF','Enabled'),
   ('TCONFTHRESHOLD','250'),('2FA','Optional'),('MINPASS','8'),
   ('UTIMEOUT','15M'),('SENREVS','5'),('PKGREVS','5'),('INVESTIGATE','Enabled'),
   ('ENDPOINTCOMM','mqtt'),('COMPLEXPASS','Disabled'),('CMDTIMEOUT','120'),('DEPLTIMEOUT','3600')"

# --- broker.conf pointing at the scratch DB -----------------------------------
CONF="$DATADIR/broker.conf"
cat > "$CONF" <<EOF
DBUSER = root
DBPASS =
DBSOCKET = $SOCK
EOF

run() { PERL5LIB="$PERL_LIBS" perl "$SCRIPT" --conf "$CONF" "$@"; }

# --- get -----------------------------------------------------------------------
out=$(run get CHECKININT)
check "get seeded value" $([ "$out" = "CHECKININT = 5" ] && echo 0 || echo 1) "$out"

out=$(run get PNETCHECK)
check "get unseeded key shows (not set)" $([ "$out" = "PNETCHECK = (not set)" ] && echo 0 || echo 1) "$out"

# --- set: valid single ----------------------------------------------------------
out=$(run set CHECKININT=10)
check "set valid single" $([ "$out" = "set CHECKININT = 10" ] && echo 0 || echo 1) "$out"
val=$(m "select CVAL from SYSTEM.CONFIG where CKEY='CHECKININT'")
check "set persisted to DB" $([ "$val" = "10" ] && echo 0 || echo 1) "$val"

# --- set: enum case normalized --------------------------------------------------
run set 2FA=required >/dev/null
val=$(m "select CVAL from SYSTEM.CONFIG where CKEY='2FA'")
check "set normalizes enum case" $([ "$val" = "Required" ] && echo 0 || echo 1) "$val"

# --- set: multiple --------------------------------------------------------------
run set MISSINGAFTER=60 TCONFTHRESHOLD=100 >/dev/null
val1=$(m "select CVAL from SYSTEM.CONFIG where CKEY='MISSINGAFTER'")
val2=$(m "select CVAL from SYSTEM.CONFIG where CKEY='TCONFTHRESHOLD'")
check "set multiple pairs" $([ "$val1" = "60" ] && [ "$val2" = "100" ] && echo 0 || echo 1) "$val1/$val2"

# --- set: upsert of an unseeded key ---------------------------------------------
run set PASSKEYS=Enabled >/dev/null
val=$(m "select CVAL from SYSTEM.CONFIG where CKEY='PASSKEYS'")
check "set inserts unseeded key" $([ "$val" = "Enabled" ] && echo 0 || echo 1) "$val"

# --- set: duration --------------------------------------------------------------
run set UTIMEOUT=30M >/dev/null
val=$(m "select CVAL from SYSTEM.CONFIG where CKEY='UTIMEOUT'")
check "set duration value" $([ "$val" = "30M" ] && echo 0 || echo 1) "$val"

# --- set: out-of-range rejected, nothing written --------------------------------
before=$(m "select CVAL from SYSTEM.CONFIG where CKEY='MINPASS'")
out=$(run set MINPASS=4 2>&1); rc=$?
check "set below-min rejected rc=1" $([ $rc -eq 1 ] && echo 0 || echo 1) "rc=$rc"
check "set below-min error message" $(printf '%s' "$out" | grep -q "8 or more" && echo 0 || echo 1) "$out"
after=$(m "select CVAL from SYSTEM.CONFIG where CKEY='MINPASS'")
check "set below-min wrote nothing" $([ "$before" = "$after" ] && echo 0 || echo 1) "$before->$after"

# --- set: all-or-nothing (valid + invalid) --------------------------------------
out=$(run set CHECKININT=7 MINPASS=3 2>&1); rc=$?
check "set mixed rejected rc=1" $([ $rc -eq 1 ] && echo 0 || echo 1) "rc=$rc"
val=$(m "select CVAL from SYSTEM.CONFIG where CKEY='CHECKININT'")
check "set mixed wrote nothing" $([ "$val" = "10" ] && echo 0 || echo 1) "$val"

# --- set: unknown key rejected --------------------------------------------------
out=$(run set BOGUS=1 2>&1); rc=$?
check "set unknown key rejected rc=1" $([ $rc -eq 1 ] && echo 0 || echo 1) "rc=$rc"
check "set unknown key message" $(printf '%s' "$out" | grep -q "unknown setting 'BOGUS'" && echo 0 || echo 1) "$out"

# --- set: malformed pair rejected -----------------------------------------------
out=$(run set NOEQUALS 2>&1); rc=$?
check "set malformed pair rejected rc=1" $([ $rc -eq 1 ] && echo 0 || echo 1) "rc=$rc"

# --- get: multiple --------------------------------------------------------------
out=$(run get CHECKININT MISSINGAFTER)
check "get multiple keys" $(printf '%s' "$out" | grep -q "CHECKININT = 10" && printf '%s' "$out" | grep -q "MISSINGAFTER = 60" && echo 0 || echo 1) "$out"

# --- list -----------------------------------------------------------------------
out=$(run list)
check "list lists a key" $(printf '%s' "$out" | grep -q "CHECKININT" && echo 0 || echo 1)
check "list shows valid range" $(printf '%s' "$out" | grep -q "int >= 1" && echo 0 || echo 1)
check "list shows current value" $(printf '%s' "$out" | grep "CHECKININT" | grep -q "10" && echo 0 || echo 1)

# --- help -----------------------------------------------------------------------
out=$(run --help)
check "help shows usage" $(printf '%s' "$out" | grep -q "luminum-config.pl set" && echo 0 || echo 1)

echo "------------------------------------------------------------"
if [ "$FAILURES" -gt 0 ]; then
    echo "FAILED: $FAILURES check(s) failed"
    exit 1
fi
echo "All checks passed."
exit 0
