#!/usr/bin/env bash
# Client installer test: layout, generated scripts, wizard integration,
# idempotent re-run, start/stop cycle, missing-binary handling, the
# --binary override, and install-mode detection (fresh / upgrade /
# configure-in-place over a foreign install) - all against scratch
# install roots under $HOME (never /opt).
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
# The Lumy is optional for this test: the installer handles a package
# without Lumy binaries (warning and continuing), so the installer's core
# paths are testable without it. The Lumy install checks run only when the
# Lumy binary is built; otherwise the warning path is verified instead.
HAVE_LUMY=0
[ -x "$LUMY_BIN" ] && HAVE_LUMY=1

ROOT="$HOME/.lumclient-install-test"
ROOT2="$HOME/.lumclient-install-test-badcert"
ROOT3="$HOME/.lumclient-install-test-override"
ROOT4="$HOME/.lumclient-install-test-configure"
ROOT5="$HOME/.lumclient-install-test-configure2"
ROOT6="$HOME/.lumclient-install-test-foreign"
PROVROOT="$HOME/.lumclient-install-test-provision"
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
    rm -rf "$ROOT" "$ROOT2" "$ROOT3" "$ROOT4" "$ROOT5" "$ROOT6" "$PROVROOT" "$PKG" "$CERTDIR"
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
# The modules directory is always staged (even empty) so the installer's
# Lumy loop runs; without a built Lumy it exercises the "no Lumy binaries"
# warning path.
mkdir -p "$PKG/dist/modules/integrity" "$CERTDIR"
cp "$INSTALLER" "$PKG/install.sh"
cp "$CLIENT_BIN" "$PKG/dist/LuminumClient"
[ "$HAVE_LUMY" -eq 1 ] && cp "$LUMY_BIN" "$PKG/dist/modules/integrity/Lumy_Integrity"

openssl req -x509 -newkey rsa:2048 -nodes -days 30 \
    -keyout "$CERTDIR/key.pem" -out "$CERTDIR/cert.pem" \
    -subj "/CN=install.test" 2>/dev/null
CERT="$CERTDIR/cert.pem"
# Self-signed Ed25519 signing certificate for the provisioning file (the
# import path requires both the TLS and signing certs).
openssl req -x509 -newkey ed25519 -nodes -days 30 \
    -keyout "$CERTDIR/signing.key" -out "$CERTDIR/signing.crt" \
    -subj "/CN=install.test" 2>/dev/null
SIGNING="$CERTDIR/signing.crt"

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
check "install: no provisioning file -> wizard, not import" \
    $(! grep -q "Importing provisioning file" "$ROOT-install.log" 2>/dev/null; echo $?)
check "install: server.crt matches the provided certificate" \
    $([ -f "$ROOT/config/server.crt" ] && cmp -s "$CERT" "$ROOT/config/server.crt"; echo $?)
if [ "$HAVE_LUMY" -eq 1 ]; then
    check "install: Integrity Lumy installed" \
        $([ -x "$ROOT/modules/integrity/Lumy_Integrity" ]; echo $?)
else
    check "install: missing Lumy warned, not fatal" \
        $(grep -q "module integrity skipped" "$ROOT-install.log" 2>/dev/null; echo $?)
    check "install: no Lumy binary installed" \
        $([ ! -e "$ROOT/modules/integrity/Lumy_Integrity" ]; echo $?)
fi
check "install: installer marker written" $([ -f "$ROOT/.luminum-installer" ]; echo $?)
if [ "$UNIT_PRE" -eq 0 ]; then
    check "install: no unit written while systemd is offline" $([ ! -f "$UNIT" ]; echo $?)
else
    :
fi

# --- Phase 2: idempotent re-run (upgrade mode: marker present) ------------------------
bash "$PKG/install.sh" --install-root "$ROOT" --no-start --no-setup \
    > "$ROOT-rerun.log" 2>&1
rc=$?
check "re-run: exits 0" $([ "$rc" -eq 0 ]; echo $?) "rc=$rc; see $ROOT-rerun.log"
check "re-run: existing config preserved" $([ "$(cfgval SHOST "$ROOT")" = "install.test" ]; echo $?)
check "re-run: installer marker still present" $([ -f "$ROOT/.luminum-installer" ]; echo $?)

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

# --- Phase 7: configure mode over a foreign, already-configured install -------------------
# Simulates a .deb/.rpm install: layout present, no installer marker.
mkdir -p "$ROOT4/bin" "$ROOT4/config" "$ROOT4/logs" "$ROOT4/run"
printf '#!/bin/sh\nexit 97\n' > "$ROOT4/LuminumClient"
chmod 0755 "$ROOT4/LuminumClient"
python3 - "$ROOT4" <<'EOF'
import sqlite3, sys
conn = sqlite3.connect(sys.argv[1] + "/config/client.conf.db")
conn.execute("create table if not exists CONFIG (KEY text not null, VALUE text not null)")
conn.execute("insert into CONFIG (KEY,VALUE) values ('SHOST','pkg.example')")
conn.commit()
EOF
chmod 0600 "$ROOT4/config/client.conf.db"
STUB_SUM=$(sha256sum "$ROOT4/LuminumClient" | cut -d' ' -f1)
bash "$PKG/install.sh" --install-root "$ROOT4" --no-start > "$ROOT4.log" 2>&1
rc=$?
check "configure: exits 0" $([ "$rc" -eq 0 ]; echo $?) "rc=$rc; see $ROOT4.log"
check "configure: reports the existing installation" \
    $(grep -q "Existing installation found" "$ROOT4.log" 2>/dev/null; echo $?)
check "configure: existing binary untouched" \
    $([ "$(sha256sum "$ROOT4/LuminumClient" | cut -d' ' -f1)" = "$STUB_SUM" ]; echo $?)
check "configure: no installer marker created" $([ ! -f "$ROOT4/.luminum-installer" ]; echo $?)
check "configure: existing config preserved" $([ "$(cfgval SHOST "$ROOT4")" = "pkg.example" ]; echo $?)
check "configure: no start/stop scripts written" \
    $([ ! -f "$ROOT4/bin/start-client" ]; echo $?)

# --- Phase 8: configure mode over a foreign, unconfigured install -------------------------
mkdir -p "$ROOT5"
cp "$CLIENT_BIN" "$ROOT5/LuminumClient"
chmod 0755 "$ROOT5/LuminumClient"
REAL_SUM=$(sha256sum "$ROOT5/LuminumClient" | cut -d' ' -f1)
printf 'install.test\n\nsvrkey456\n%s\n' "$CERT" | \
    bash "$PKG/install.sh" --install-root "$ROOT5" --no-start > "$ROOT5.log" 2>&1
rc=$?
check "configure (unconfigured): exits 0" $([ "$rc" -eq 0 ]; echo $?) "rc=$rc; see $ROOT5.log"
check "configure (unconfigured): wizard ran against the existing binary" \
    $([ "$(cfgval SHOST "$ROOT5")" = "install.test" ]; echo $?)
check "configure (unconfigured): existing binary untouched" \
    $([ "$(sha256sum "$ROOT5/LuminumClient" | cut -d' ' -f1)" = "$REAL_SUM" ]; echo $?)
check "configure (unconfigured): no installer marker created" \
    $([ ! -f "$ROOT5/.luminum-installer" ]; echo $?)

# --- Phase 9: foreign directory that is not a client install fails cleanly -----------------
mkdir -p "$ROOT6"
bash "$PKG/install.sh" --install-root "$ROOT6" --no-start > "$ROOT6.log" 2>&1
rc=$?
check "foreign dir: installer exits nonzero" $([ "$rc" -ne 0 ]; echo $?) "rc=$rc"
check "foreign dir: error names the problem" \
    $(grep -q "not a Luminum client installation" "$ROOT6.log" 2>/dev/null; echo $?)
check "foreign dir: nothing written" $([ -z "$(ls -A "$ROOT6")" ]; echo $?)

# --- Phase 10: explicit --binary over a foreign install is a deliberate replacement --------
OVERRIDE2="$HOME/.lumclient-override-bin2"
cp "$CLIENT_BIN" "$OVERRIDE2"
bash "$PKG/install.sh" --install-root "$ROOT4" --binary "$OVERRIDE2" --no-start --no-setup \
    > "$ROOT4-override.log" 2>&1
rc=$?
check "--binary over foreign install: exits 0" $([ "$rc" -eq 0 ]; echo $?) "rc=$rc; see $ROOT4-override.log"
check "--binary over foreign install: binary replaced" \
    $([ -x "$ROOT4/LuminumClient" ] && cmp -s "$OVERRIDE2" "$ROOT4/LuminumClient"; echo $?)
check "--binary over foreign install: marker now written" \
    $([ -f "$ROOT4/.luminum-installer" ]; echo $?)
rm -f "$OVERRIDE2"

# --- Phase 11: provisioning-driven install (config.ini auto-discovered in dist/) ----
# A valid config.ini staged in the package's dist/ is imported
# non-interactively (no piped wizard input) and seeds the config DB from the
# file. This is the out-of-band path the wizard is a fallback for.
python3 - "$PKG/dist/config.ini" "prov.install.test" "10465" "svrkeyprov456" "$CERT" "$SIGNING" <<'EOF'
import json, sys
out, host, port, key, scert, gcert = sys.argv[1:7]
def read(p):
    try:
        return open(p).read()
    except Exception:
        return ""
doc = {
    "v": "1.0",
    "server": {"host": host, "port": int(port), "key": key},
    "certificates": {"server": read(scert), "signing": read(gcert)},
}
open(out, "w").write(json.dumps(doc, indent=2))
EOF
bash "$PKG/install.sh" --install-root "$PROVROOT" --no-start > "$PROVROOT.log" 2>&1
rc=$?
check "provision: exits 0 without wizard input" $([ "$rc" -eq 0 ]; echo $?) "rc=$rc; see $PROVROOT.log"
check "provision: import path taken" \
    $(grep -q "Importing provisioning file" "$PROVROOT.log" 2>/dev/null; echo $?)
check "provision: SHOST from the file" $([ "$(cfgval SHOST "$PROVROOT")" = "prov.install.test" ]; echo $?)
check "provision: SVRKEY from the file" $([ "$(cfgval SVRKEY "$PROVROOT")" = "svrkeyprov456" ]; echo $?)
check "provision: SPORT from the file" $([ "$(cfgval SPORT "$PROVROOT")" = "10465" ]; echo $?)
check "provision: server.crt from the file" \
    $([ -f "$PROVROOT/config/server.crt" ] && cmp -s "$CERT" "$PROVROOT/config/server.crt"; echo $?)
check "provision: server-signing.crt from the file" \
    $([ -f "$PROVROOT/config/server-signing.crt" ] && cmp -s "$SIGNING" "$PROVROOT/config/server-signing.crt"; echo $?)
check "provision: config DB mode is 0600" \
    $([ "$(stat -c %a "$PROVROOT/config/client.conf.db" 2>/dev/null)" = "600" ]; echo $?)
# Remove the staged file so it cannot leak into any later phase.
rm -f "$PKG/dist/config.ini"

# --- Phase 12: explicit --provision overrides auto-discovery -------------------------
# Both dist/config.ini (auto) and an explicit file are present; the explicit
# --provision path must win. Fresh root so the config-DB guard does not abort.
rm -rf "$PROVROOT"
python3 - "$PKG/dist/config.ini" "auto.install.test" "10465" "svrkeyauto" "$CERT" "$SIGNING" <<'EOF'
import json, sys
out, host, port, key, scert, gcert = sys.argv[1:7]
def read(p):
    try:
        return open(p).read()
    except Exception:
        return ""
doc = {
    "v": "1.0",
    "server": {"host": host, "port": int(port), "key": key},
    "certificates": {"server": read(scert), "signing": read(gcert)},
}
open(out, "w").write(json.dumps(doc, indent=2))
EOF
python3 - "$PKG/explicit.ini" "explicit.install.test" "10465" "svrkeyexplicit" "$CERT" "$SIGNING" <<'EOF'
import json, sys
out, host, port, key, scert, gcert = sys.argv[1:7]
def read(p):
    try:
        return open(p).read()
    except Exception:
        return ""
doc = {
    "v": "1.0",
    "server": {"host": host, "port": int(port), "key": key},
    "certificates": {"server": read(scert), "signing": read(gcert)},
}
open(out, "w").write(json.dumps(doc, indent=2))
EOF
bash "$PKG/install.sh" --install-root "$PROVROOT" --no-start --provision "$PKG/explicit.ini" \
    > "$PROVROOT-explicit.log" 2>&1
rc=$?
check "--provision: exits 0" $([ "$rc" -eq 0 ]; echo $?) "rc=$rc; see $PROVROOT-explicit.log"
check "--provision: explicit file's SHOST wins over auto-discovery" \
    $([ "$(cfgval SHOST "$PROVROOT")" = "explicit.install.test" ]; echo $?)
check "--provision: explicit file's SVRKEY wins" \
    $([ "$(cfgval SVRKEY "$PROVROOT")" = "svrkeyexplicit" ]; echo $?)
rm -f "$PKG/dist/config.ini" "$PKG/explicit.ini"

# --- cleanup ---------------------------------------------------------------------------------
rm -f "$ROOT-install.log" "$ROOT-rerun.log" "$ROOT-start.log" "$ROOT-stop.log" \
      "$ROOT2.log" "$ROOT3.log" "$ROOT3-override.log" \
      "$ROOT4.log" "$ROOT4-override.log" "$ROOT5.log" "$ROOT6.log" \
      "$PROVROOT.log" "$PROVROOT-explicit.log"

echo "------------------------------------------------------------"
if [ "$FAILURES" -gt 0 ]; then
    echo "FAILED: $FAILURES check(s) failed"
    exit 1
fi
echo "All checks passed."
exit 0
