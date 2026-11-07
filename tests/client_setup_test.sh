#!/usr/bin/env bash
# Client setup wizard test: server certificate provisioning and 0600
# enforcement on the configuration database.
#
# Phases:
#   1. wizard happy path: the certificate is validated, copied to
#      config/server.crt, and the config DB is created with mode 0600
#   2. wizard with an invalid certificate path: must fail before any
#      configuration is written
#   3. startup enforcement: a config DB left at 0644 is tightened to
#      0600 when the client starts
#
# Note: LUMINUM_HOME must live on an executable mount (/tmp is noexec).
# Usage: bash tests/client_setup_test.sh
set -u
export LUMINUM_HOME="$HOME/.lumsetup-test"
REPO=$(cd "$(dirname "$0")/.." && pwd)
CLIENT="$REPO/client/linux/target/debug/LuminumClient"
[ -x "$CLIENT" ] || { echo "SKIP - client binary not built at $CLIENT"; exit 0; }
[ -x "$(command -v openssl)" ] || { echo "SKIP - openssl not available"; exit 0; }

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

cfgval() {
    python3 - "$1" <<'EOF'
import os, sqlite3, sys
home = os.environ["LUMINUM_HOME"]
conn = sqlite3.connect(home + "/config/client.conf.db")
row = conn.execute("select VALUE from CONFIG where KEY=?", (sys.argv[1],)).fetchone()
print(row[0] if row else "")
EOF
}

CERTDIR="$HOME/.lumsetup-test-certs"
rm -rf "$LUMINUM_HOME" "$CERTDIR"
mkdir -p "$CERTDIR"
openssl req -x509 -newkey rsa:2048 -nodes -days 30 \
    -keyout "$CERTDIR/key.pem" -out "$CERTDIR/cert.pem" \
    -subj "/CN=setup.test" 2>/dev/null
CERT="$CERTDIR/cert.pem"

# --- Phase 1: wizard happy path ----------------------------------------------
mkdir -p "$LUMINUM_HOME/config"
printf 'setup.test\n\nsvrkey123\n%s\n' "$CERT" | "$CLIENT" -s \
    > "$LUMINUM_HOME/wizard.log" 2>&1
rc=$?
check "wizard: exits 0" $([ "$rc" -eq 0 ]; echo $?) "rc=$rc"
check "wizard: SHOST stored" $([ "$(cfgval SHOST)" = "setup.test" ]; echo $?)
check "wizard: SPORT defaults to 10465" $([ "$(cfgval SPORT)" = "10465" ]; echo $?)
check "wizard: SVRKEY stored" $([ "$(cfgval SVRKEY)" = "svrkey123" ]; echo $?)
CLPPRV=$(cfgval CLPPRV)
check "wizard: CLPPRV is 44-char base64" \
    $([ ${#CLPPRV} -eq 44 ]; echo $?) "len=${#CLPPRV}"
FPNT=$(cfgval FPNT)
check "wizard: FPNT is 64 lowercase hex" \
    $([ -n "$FPNT" ] && [ "$FPNT" = "$(echo "$FPNT" | tr 'A-F' 'a-f')" ] \
        && [ ${#FPNT} -eq 64 ]; echo $?) "fpnt=$FPNT"
check "wizard: server.crt copied into config" \
    $([ -f "$LUMINUM_HOME/config/server.crt" ] && cmp -s "$CERT" "$LUMINUM_HOME/config/server.crt"; echo $?)
MODE=$(stat -c %a "$LUMINUM_HOME/config/client.conf.db" 2>/dev/null)
check "wizard: config DB mode is 0600" $([ "$MODE" = "600" ]; echo $?) "mode=$MODE"

# --- Phase 2: invalid certificate path ---------------------------------------
rm -rf "$LUMINUM_HOME"
mkdir -p "$LUMINUM_HOME"
printf 'setup.test\n\nsvrkey123\n%s\n' "$CERTDIR/does-not-exist.pem" | "$CLIENT" -s \
    > "$LUMINUM_HOME/wizard2.log" 2>&1
rc=$?
check "bad cert: wizard fails" $([ "$rc" -ne 0 ]; echo $?) "rc=$rc"
check "bad cert: no config DB written" \
    $([ ! -f "$LUMINUM_HOME/config/client.conf.db" ]; echo $?)

# --- Phase 3: startup 0600 enforcement ----------------------------------------
rm -rf "$LUMINUM_HOME"
mkdir -p "$LUMINUM_HOME/config"
python3 - <<'EOF'
import os, sqlite3
home = os.environ["LUMINUM_HOME"]
conn = sqlite3.connect(home + "/config/client.conf.db")
conn.execute("create table if not exists CONFIG (KEY text not null, VALUE text not null)")
for k, v in [("SHOST", "127.0.0.1"), ("SPORT", "10465"), ("SVRKEY", "testkey"), ("UID", "999")]:
    conn.execute("insert into CONFIG (KEY,VALUE) values (?,?)", (k, v))
conn.commit(); conn.close()
os.chmod(home + "/config/client.conf.db", 0o644)
EOF
cp "$CERT" "$LUMINUM_HOME/config/server.crt"
"$CLIENT" > "$LUMINUM_HOME/client.log" 2>&1 &
PID=$!
sleep 2
kill $PID 2>/dev/null
wait $PID 2>/dev/null
MODE=$(stat -c %a "$LUMINUM_HOME/config/client.conf.db" 2>/dev/null)
check "startup: config DB tightened to 0600" $([ "$MODE" = "600" ]; echo $?) "mode=$MODE"

# --- cleanup ------------------------------------------------------------------
rm -rf "$LUMINUM_HOME" "$CERTDIR"

echo "------------------------------------------------------------"
if [ "$FAILURES" -gt 0 ]; then
    echo "FAILED: $FAILURES check(s) failed"
    exit 1
fi
echo "All checks passed."
exit 0
