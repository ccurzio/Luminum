#!/usr/bin/env bash
# Client installer test: layout, generated scripts, wizard integration,
# idempotent re-run, and a start/stop cycle - all against a scratch
# install root under $HOME (never /opt).
#
# The systemd unit path is only exercised when systemd is running and
# the test runs as root; otherwise the script-based control path is
# what gets verified.
#
# Usage: bash tests/client_install_test.sh
set -u
REPO=$(cd "$(dirname "$0")/.." && pwd)
INSTALLER="$REPO/client/linux/install.sh"
[ -f "$INSTALLER" ] || { echo "SKIP - installer not found at $INSTALLER"; exit 0; }
[ -x "$(command -v openssl)" ] || { echo "SKIP - openssl not available"; exit 0; }

ROOT="$HOME/.lumclient-install-test"
ROOT2="$HOME/.lumclient-install-test-badcert"
CERTDIR="$HOME/.lumclient-install-test-certs"
UNIT=/etc/systemd/system/luminum-client.service
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

UNIT_BAK="$HOME/.lumclient-install-test-unit.bak"
UNIT_PRE=0
[ -f "$UNIT" ] && { cp "$UNIT" "$UNIT_BAK"; UNIT_PRE=1; }
cleanup() {
    [ -x "$ROOT/bin/stop-client" ] && "$ROOT/bin/stop-client" >/dev/null 2>&1
    rm -rf "$ROOT" "$ROOT2" "$CERTDIR"
    if [ -f "$UNIT" ]; then
        # Restore the pre-test unit (the installer overwrote it with a
        # scratch-root unit), or remove the one the installer created.
        if [ "$UNIT_PRE" -eq 1 ] && [ -f "$UNIT_BAK" ]; then
            cp "$UNIT_BAK" "$UNIT"
        else
            rm -f "$UNIT"
        fi
        systemctl daemon-reload 2>/dev/null
    fi
    rm -f "$UNIT_BAK"
}
trap cleanup EXIT

cfgval() {
    python3 - "$1" "$2" <<'EOF'
import os, sqlite3, sys
try:
    conn = sqlite3.connect(sys.argv[2] + "/config/client.conf.db")
    row = conn.execute("select VALUE from CONFIG where KEY=?", (sys.argv[1],)).fetchone()
    print(row[0] if row else "")
except Exception:
    print("")
EOF
}

mkdir -p "$CERTDIR"
openssl req -x509 -newkey rsa:2048 -nodes -days 30 \
    -keyout "$CERTDIR/key.pem" -out "$CERTDIR/cert.pem" \
    -subj "/CN=install.test" 2>/dev/null
CERT="$CERTDIR/cert.pem"

# --- Phase 1: fresh install with wizard (piped answers), no start -------------
printf 'install.test\n\nsvrkey456\n%s\n' "$CERT" | \
    bash "$INSTALLER" --install-root "$ROOT" --no-start > "$ROOT-install.log" 2>&1
rc=$?
check "install: exits 0" $([ "$rc" -eq 0 ]; echo $?) "rc=$rc; see $ROOT-install.log"
check "install: client binary present" $([ -x "$ROOT/LuminumClient" ]; echo $?)
check "install: start-client script is 0700" \
    $([ "$(stat -c %a "$ROOT/bin/start-client" 2>/dev/null)" = "700" ]; echo $?)
check "install: stop-client script is 0700" \
    $([ "$(stat -c %a "$ROOT/bin/stop-client" 2>/dev/null)" = "700" ]; echo $?)
check "install: start script pins LUMINUM_HOME to install root" \
    $(grep -q "export LUMINUM_HOME=\"$ROOT\"" "$ROOT/bin/start-client" 2>/dev/null; echo $?)
check "install: config DB mode is 0600" \
    $([ "$(stat -c %a "$ROOT/config/client.conf.db" 2>/dev/null)" = "600" ]; echo $?)
check "install: wizard stored SHOST" $([ "$(cfgval SHOST "$ROOT")" = "install.test" ]; echo $?)
check "install: wizard stored SVRKEY" $([ "$(cfgval SVRKEY "$ROOT")" = "svrkey456" ]; echo $?)
check "install: server.crt matches the provided certificate" \
    $([ -f "$ROOT/config/server.crt" ] && cmp -s "$CERT" "$ROOT/config/server.crt"; echo $?)
check "install: Integrity Lumy installed" \
    $([ -x "$ROOT/modules/integrity/Lumy_Integrity" ]; echo $?)
if [ "$UNIT_PRE" -eq 0 ]; then
    check "install: no unit written while systemd is offline" $([ ! -f "$UNIT" ]; echo $?)
else
    WROTE_UNIT=1
fi

# --- Phase 2: idempotent re-run ---------------------------------------------------
bash "$INSTALLER" --install-root "$ROOT" --no-start --no-setup \
    > "$ROOT-rerun.log" 2>&1
rc=$?
check "re-run: exits 0" $([ "$rc" -eq 0 ]; echo $?) "rc=$rc; see $ROOT-rerun.log"
check "re-run: existing config preserved" $([ "$(cfgval SHOST "$ROOT")" = "install.test" ]; echo $?)

# --- Phase 3: start/stop cycle ------------------------------------------------------
"$ROOT/bin/start-client" > "$ROOT-start.log" 2>&1
check "start: script exits 0" $([ $? -eq 0 ]; echo $?) "see $ROOT-start.log"
sleep 1
PID=$(cat "$ROOT/run/client.pid" 2>/dev/null)
check "start: pid file written with live process" \
    $([ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; echo $?) "pid=$PID"
check "start: IPC port 10461 listening" \
    $((exec 3<>"/dev/tcp/127.0.0.1/10461") 2>/dev/null; echo $?)
"$ROOT/bin/stop-client" > "$ROOT-stop.log" 2>&1
sleep 1
check "stop: process gone" $([ -n "$PID" ] && ! kill -0 "$PID" 2>/dev/null; echo $?)
check "stop: pid file removed" $([ ! -f "$ROOT/run/client.pid" ]; echo $?)

# --- Phase 4: wizard failure leaves no config, install reports it -------------------
printf 'install.test\n\nsvrkey456\n%s\n' "$CERTDIR/does-not-exist.pem" | \
    bash "$INSTALLER" --install-root "$ROOT2" --no-start > "$ROOT2.log" 2>&1
rc=$?
check "bad cert: installer exits nonzero" $([ "$rc" -ne 0 ]; echo $?) "rc=$rc"
check "bad cert: no config DB written" $([ ! -f "$ROOT2/config/client.conf.db" ]; echo $?)
check "bad cert: binary still installed" $([ -x "$ROOT2/LuminumClient" ]; echo $?)

# --- cleanup ------------------------------------------------------------------------
rm -f "$ROOT-install.log" "$ROOT-rerun.log" "$ROOT-start.log" "$ROOT-stop.log" "$ROOT2.log"

echo "------------------------------------------------------------"
if [ "$FAILURES" -gt 0 ]; then
    echo "FAILED: $FAILURES check(s) failed"
    exit 1
fi
echo "All checks passed."
exit 0
