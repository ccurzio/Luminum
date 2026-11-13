#!/usr/bin/env bash
# Client provisioning import test: the out-of-band config.ini import path
# (LuminumClient --import) that replaces the interactive wizard.
#
# Phases:
#   1. import happy path: a valid config.ini seeds the config DB
#      (SHOST/SPORT/SVRKEY + a fresh CLPPRV/CLPPUB/FPNT) and writes both
#      certificates, with the DB secured to 0600
#   2. invalid JSON: must fail before any configuration is written
#   3. missing/invalid signing certificate: must fail, no config written
#   4. unsupported version: must fail, no config written
#   5. non-alphanumeric server key: must fail, no config written
#   6. existing configuration: the import aborts and leaves the existing
#      config untouched
#
# Note: LUMINUM_HOME must live on an executable mount (/tmp is noexec).
# Usage: bash tests/client_provision_test.sh
set -u
export LUMINUM_HOME="$HOME/.lumprovision-test"
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
try:
    conn = sqlite3.connect(home + "/config/client.conf.db")
    row = conn.execute("select VALUE from CONFIG where KEY=?", (sys.argv[1],)).fetchone()
    print(row[0] if row else "")
except Exception:
    print("")
EOF
}

CERTDIR="$HOME/.lumprovision-test-certs"
rm -rf "$LUMINUM_HOME" "$CERTDIR"
mkdir -p "$CERTDIR"
openssl req -x509 -newkey rsa:2048 -nodes -days 30 \
    -keyout "$CERTDIR/key.pem" -out "$CERTDIR/cert.pem" \
    -subj "/CN=provision.test" 2>/dev/null
CERT="$CERTDIR/cert.pem"
openssl req -x509 -newkey ed25519 -nodes -days 30 \
    -keyout "$CERTDIR/signing.key" -out "$CERTDIR/signing.crt" \
    -subj "/CN=provision.test" 2>/dev/null
SIGNING="$CERTDIR/signing.crt"

# Write a provisioning file from the two certs. $1 = output path,
# $2 = host, $3 = port, $4 = key, $5 = server cert path, $6 = signing cert path.
mkprov() {
    python3 - "$1" "$2" "$3" "$4" "$5" "$6" <<'EOF'
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
}

PROV="$LUMINUM_HOME/config.ini"
mkdir -p "$LUMINUM_HOME"

# --- Phase 1: import happy path ------------------------------------------------
mkprov "$PROV" "prov.test" "10465" "svrkeyprov123" "$CERT" "$SIGNING"
"$CLIENT" --import "$PROV" > "$LUMINUM_HOME/import.log" 2>&1
rc=$?
check "import: exits 0" $([ "$rc" -eq 0 ]; echo $?) "rc=$rc; see import.log"
check "import: SHOST stored" $([ "$(cfgval SHOST)" = "prov.test" ]; echo $?)
check "import: SPORT stored" $([ "$(cfgval SPORT)" = "10465" ]; echo $?)
check "import: SVRKEY stored" $([ "$(cfgval SVRKEY)" = "svrkeyprov123" ]; echo $?)
CLPPRV=$(cfgval CLPPRV)
check "import: CLPPRV is 44-char base64" $([ ${#CLPPRV} -eq 44 ]; echo $?) "len=${#CLPPRV}"
FPNT=$(cfgval FPNT)
check "import: FPNT is 64 lowercase hex" \
    $([ -n "$FPNT" ] && [ "$FPNT" = "$(echo "$FPNT" | tr 'A-F' 'a-f')" ] \
        && [ ${#FPNT} -eq 64 ]; echo $?) "fpnt=$FPNT"
check "import: server.crt written from the file" \
    $([ -f "$LUMINUM_HOME/config/server.crt" ] && cmp -s "$CERT" "$LUMINUM_HOME/config/server.crt"; echo $?)
check "import: server-signing.crt written from the file" \
    $([ -f "$LUMINUM_HOME/config/server-signing.crt" ] && cmp -s "$SIGNING" "$LUMINUM_HOME/config/server-signing.crt"; echo $?)
MODE=$(stat -c %a "$LUMINUM_HOME/config/client.conf.db" 2>/dev/null)
check "import: config DB mode is 0600" $([ "$MODE" = "600" ]; echo $?) "mode=$MODE"

# --- Phase 2: invalid JSON -----------------------------------------------------
rm -rf "$LUMINUM_HOME"; mkdir -p "$LUMINUM_HOME"
echo 'this is not json' > "$LUMINUM_HOME/bad.ini"
"$CLIENT" --import "$LUMINUM_HOME/bad.ini" > "$LUMINUM_HOME/bad.log" 2>&1
rc=$?
check "bad json: import fails" $([ "$rc" -ne 0 ]; echo $?) "rc=$rc"
check "bad json: no config DB written" $([ ! -f "$LUMINUM_HOME/config/client.conf.db" ]; echo $?)

# --- Phase 3: missing signing certificate --------------------------------------
rm -rf "$LUMINUM_HOME"; mkdir -p "$LUMINUM_HOME"
# signing cert points at a nonexistent file -> empty -> rejected
mkprov "$LUMINUM_HOME/nosign.ini" "prov.test" "10465" "svrkeyprov123" "$CERT" "$CERTDIR/nope.crt"
"$CLIENT" --import "$LUMINUM_HOME/nosign.ini" > "$LUMINUM_HOME/nosign.log" 2>&1
rc=$?
check "no signing cert: import fails" $([ "$rc" -ne 0 ]; echo $?) "rc=$rc"
check "no signing cert: no config DB written" $([ ! -f "$LUMINUM_HOME/config/client.conf.db" ]; echo $?)

# --- Phase 4: unsupported version -----------------------------------------------
rm -rf "$LUMINUM_HOME"; mkdir -p "$LUMINUM_HOME"
mkprov "$LUMINUM_HOME/badv.ini" "prov.test" "10465" "svrkeyprov123" "$CERT" "$SIGNING"
python3 - "$LUMINUM_HOME/badv.ini" <<'EOF'
import json, sys
p = sys.argv[1]
d = json.load(open(p)); d["v"] = "2.0"; json.dump(d, open(p, "w"))
EOF
"$CLIENT" --import "$LUMINUM_HOME/badv.ini" > "$LUMINUM_HOME/badv.log" 2>&1
rc=$?
check "bad version: import fails" $([ "$rc" -ne 0 ]; echo $?) "rc=$rc"
check "bad version: no config DB written" $([ ! -f "$LUMINUM_HOME/config/client.conf.db" ]; echo $?)

# --- Phase 5: non-alphanumeric server key ---------------------------------------
rm -rf "$LUMINUM_HOME"; mkdir -p "$LUMINUM_HOME"
mkprov "$LUMINUM_HOME/badkey.ini" "prov.test" "10465" "bad-key!" "$CERT" "$SIGNING"
"$CLIENT" --import "$LUMINUM_HOME/badkey.ini" > "$LUMINUM_HOME/badkey.log" 2>&1
rc=$?
check "bad key: import fails" $([ "$rc" -ne 0 ]; echo $?) "rc=$rc"
check "bad key: no config DB written" $([ ! -f "$LUMINUM_HOME/config/client.conf.db" ]; echo $?)

# --- Phase 6: existing configuration guard --------------------------------------
rm -rf "$LUMINUM_HOME"; mkdir -p "$LUMINUM_HOME/config"
python3 - <<'EOF'
import os, sqlite3
home = os.environ["LUMINUM_HOME"]
conn = sqlite3.connect(home + "/config/client.conf.db")
conn.execute("create table if not exists CONFIG (KEY text not null, VALUE text not null)")
conn.execute("insert into CONFIG (KEY,VALUE) values ('SHOST','existing.test')")
conn.commit(); conn.close()
EOF
mkprov "$LUMINUM_HOME/prov2.ini" "prov.test" "10465" "svrkeyprov123" "$CERT" "$SIGNING"
"$CLIENT" --import "$LUMINUM_HOME/prov2.ini" > "$LUMINUM_HOME/guard.log" 2>&1
rc=$?
check "existing config: import aborts" $([ "$rc" -ne 0 ]; echo $?) "rc=$rc"
check "existing config: SHOST unchanged" $([ "$(cfgval SHOST)" = "existing.test" ]; echo $?)
check "existing config: no SVRKEY overwritten" $([ -z "$(cfgval SVRKEY)" ]; echo $?)

# --- cleanup --------------------------------------------------------------------
rm -rf "$LUMINUM_HOME" "$CERTDIR"

echo "------------------------------------------------------------"
if [ "$FAILURES" -gt 0 ]; then
    echo "FAILED: $FAILURES check(s) failed"
    exit 1
fi
echo "All checks passed."
exit 0
