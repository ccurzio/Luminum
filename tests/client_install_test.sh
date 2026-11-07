#!/usr/bin/env bash
# Client installer test: layout, generated scripts, wizard integration,
# idempotent re-run, start/stop cycle, missing-binary handling, and the
# --binary override - all against scratch install roots under $HOME
# (never /opt).
#
# The installer expects the prebuilt binaries in a dist/ directory next
# to itself, so the test stages a throwaway package (install.sh + dist/)
# under $HOME and runs the installer from there, exactly as a
# production deployment would.
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

CLIENT_BIN="$REPO/client/linux/target/debug/LuminumClient"
LUMY_BIN="$REPO/client/modules/linux/Integrity/target/debug/Lumy_Integrity"
[ -x "$CLIENT_BIN" ] || { echo "SKIP - client binary not built at $CLIENT_BIN"; exit 0; }
[ -x "$LUMY_BIN" ] || { echo "SKIP - Integrity Lumy not built at $LUMY_BIN"; exit 0; }

ROOT="$HOME/.lumclient-install-test"
ROOT2="$HOME/.lumclient-install-test-badcert"
ROOT3="$HOME/.lumclient-install-test-override"
PKG="$HOME/.lumclient-pkg-test"
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
    rm -rf "$ROOT" "$ROOT2" "$ROOT3" "$PKG" "$CERTDIR"
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

# --- stage a throwaway distribution package --------------------------------------
mkdir -p "$PKG/dist/modules/integrity" "$CERTDIR"
cp "$INSTALLER" "$PKG/install.sh"
cp "$CLIENT_BIN" "$PKG/dist/LuminumClient"
cp "$LUMY_BIN" "$PKG/dist/modules/integrity/Lumy_Integrity"

openssl req -x509 -newkey rsa:2048 -nodes -days 30 \
    -keyout "$CERTDIR/key.pem" -out "$CERTDIR/cert.pem" \
    -subj "/CN=install.test" 2>/dev/null
CERT="$CERTDIR/cert.pem"

# --- Phase 1: fresh install with wizard (piped answers), no start -----------------
printf 'install.test\n\nsvrkey456\n%s\n' "$CERT" | \
    bash "$PKG/install.sh" --install-root "$ROOT" --no-start > "$ROOT-install.log" 2>&1
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
    :
fi

# --- Phase 2: idempotent re-run ------------------------------------------------------
bash "$PKG/install.sh" --install-root "$ROOT" --no-start --no-setup \
    > "$ROOT-rerun.log" 2>&1
rc=$?
check "re-run: exits 0" $([ "$rc" -eq 0 ]; echo $?) "rc=$rc; see $ROOT-rerun.log"
check "re-run: existing config preserved" $([ "$(cfgval SHOST "$ROOT")" = "install.test" ]; echo $?)

# --- Phase 3: start/stop cycle ---------------------------------------------------------
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

# --- Phase 4: wizard failure leaves no config, install reports it ----------------------
printf 'install.test\n\nsvrkey456\n%s\n' "$CERTDIR/does-not-exist.pem" | \
    bash "$PKG/install.sh" --install-root "$ROOT2" --no-start > "$ROOT2.log" 2>&1
rc=$?
check "bad cert: installer exits nonzero" $([ "$rc" -ne 0 ]; echo $?) "rc=$rc"
check "bad cert: no config DB written" $([ ! -f "$ROOT2/config/client.conf.db" ]; echo $?)
check "bad cert: binary still installed" $([ -x "$ROOT2/LuminumClient" ]; echo $?)

# --- Phase 5: missing binary fails cleanly ----------------------------------------------
rm -f "$PKG/dist/LuminumClient"
bash "$PKG/install.sh" --install-root "$ROOT3" --no-start > "$ROOT3.log" 2>&1
rc=$?
check "missing binary: installer exits nonzero" $([ "$rc" -ne 0 ]; echo $?) "rc=$rc"
check "missing binary: error names the missing binary" \
    $(grep -q "missing binary: $PKG/dist/LuminumClient" "$ROOT3.log" 2>/dev/null; echo $?)
if grep -qi "build" "$ROOT3.log" 2>/dev/null; then ok=1; else ok=0; fi
check "missing binary: no mention of building" $ok
cp "$CLIENT_BIN" "$PKG/dist/LuminumClient"

# --- Phase 6: --binary override ------------------------------------------------------------
OVERRIDE="$HOME/.lumclient-override-bin"
cp "$CLIENT_BIN" "$OVERRIDE"
printf 'install.test\n\nsvrkey456\n%s\n' "$CERT" | \
    bash "$PKG/install.sh" --install-root "$ROOT3" --binary "$OVERRIDE" --no-start \
    > "$ROOT3-override.log" 2>&1
rc=$?
check "--binary: exits 0" $([ "$rc" -eq 0 ]; echo $?) "rc=$rc; see $ROOT3-override.log"
check "--binary: provided binary installed" \
    $([ -x "$ROOT3/LuminumClient" ] && cmp -s "$OVERRIDE" "$ROOT3/LuminumClient"; echo $?)
rm -f "$OVERRIDE"

# --- cleanup ---------------------------------------------------------------------------------
rm -f "$ROOT-install.log" "$ROOT-rerun.log" "$ROOT-start.log" "$ROOT-stop.log" \
      "$ROOT2.log" "$ROOT3.log" "$ROOT3-override.log"

echo "------------------------------------------------------------"
if [ "$FAILURES" -gt 0 ]; then
    echo "FAILED: $FAILURES check(s) failed"
    exit 1
fi
echo "All checks passed."
exit 0
