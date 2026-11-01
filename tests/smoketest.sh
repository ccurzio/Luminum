#!/usr/bin/env bash
# Smoke test: Luminum Client + Integrity Lumy (Linux)
# Usage: bash smoketest.sh
# Runs the client against a throwaway LUMINUM_HOME with no server
# present (registration/check-in will fail gracefully), seeds the
# Integrity Lumy config with a watch path, triggers filesystem events,
# and dumps the IM log and out-queue.
# Note: LUMINUM_HOME must live on an executable mount (/tmp is noexec).
set -u
export LUMINUM_HOME="$HOME/.lumtest"
REPO=$(cd "$(dirname "$0")/.." && pwd)
rm -rf "$LUMINUM_HOME"
mkdir -p "$LUMINUM_HOME/config" "$LUMINUM_HOME/modules/integrity" "$LUMINUM_HOME/watch"

# Seed client config DB (UID preset so registration is skipped in the test)
python3 - <<'EOF'
import os, sqlite3
home = os.environ["LUMINUM_HOME"]
conn = sqlite3.connect(home + "/config/client.conf.db")
conn.execute("create table if not exists CONFIG (KEY text not null, VALUE text not null)")
for k, v in [("SHOST", "127.0.0.1"), ("SPORT", "10465"), ("SVRKEY", "testkey"), ("UID", "999")]:
    conn.execute("insert into CONFIG (KEY,VALUE) values (?,?)", (k, v))
conn.commit(); conn.close()

# Seed Integrity Lumy config DB with a watch path
conn = sqlite3.connect(home + "/modules/integrity/integrity.conf.db")
conn.execute("create table if not exists WATCH (PATH text not null)")
conn.execute("insert into WATCH (PATH) values (?)", (home + "/watch",))
conn.commit(); conn.close()
EOF

# Install the Lumy binary where the client's discovery expects it
cp "$REPO/client/modules/linux/Integrity/target/debug/Lumy_Integrity" \
   "$LUMINUM_HOME/modules/integrity/Lumy_Integrity"

# Start the client in debug mode
"$REPO/client/linux/target/debug/LuminumClient" -d > "$LUMINUM_HOME/client.log" 2>&1 &
CLIENT_PID=$!
sleep 3

# Trigger filesystem events in the watched directory
echo "integrity test" > "$LUMINUM_HOME/watch/testfile.txt"
sleep 1
echo "modified" >> "$LUMINUM_HOME/watch/testfile.txt"
sleep 1
mkdir -p "$LUMINUM_HOME/watch/subdir"
sleep 1
rm -f "$LUMINUM_HOME/watch/testfile.txt"
sleep 4   # allow debounce (2s) + event processing

echo "=== client.log ==="
cat "$LUMINUM_HOME/client.log"
echo
echo "=== IM log (imlogs.db) ==="
python3 - <<'EOF'
import os, sqlite3
home = os.environ["LUMINUM_HOME"]
conn = sqlite3.connect(home + "/modules/integrity/imlogs.db")
try:
    for row in conn.execute("select ID, DATE, TYPE, PATH, PERMS, OWNER, GRP, SIZE, CHANGE, ALERTED from EVENTS"):
        print(row)
except Exception as e:
    print("no events table:", e)
conn.close()
EOF
echo
echo "=== Out-queue (outqueue.db) ==="
python3 - <<'EOF'
import os, sqlite3
home = os.environ["LUMINUM_HOME"]
conn = sqlite3.connect(home + "/config/outqueue.db")
try:
    for row in conn.execute("select ID, TS, LUMY, ACTION, SENT, PAYLOAD from OUTQUEUE"):
        print(row)
except Exception as e:
    print("no outqueue table:", e)
conn.close()
EOF

kill $CLIENT_PID 2>/dev/null
wait $CLIENT_PID 2>/dev/null
echo "=== test complete ==="
