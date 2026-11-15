#!/usr/bin/env bash
# macOS client uninstaller test: happy-path removal (install layout
# deleted, pid-file process stopped, idempotent re-run), the
# system-directory and non-Luminum-directory safety refusals, and the
# launchd plist handling (matching-root plist removed, foreign-root
# plist left in place) - all against scratch install roots under $HOME.
#
# The uninstaller is plain bash; its launchctl calls are guarded by the
# presence of /bin/launchctl, so the script's logic is verifiable on any
# Unix host. The plist scenarios run only when /Library/LaunchDaemons
# can be written (root), with any pre-existing plist backed up and
# restored.
#
# Usage: bash tests/client_macos_uninstall_test.sh
set -u
REPO=$(cd "$(dirname "$0")/.." && pwd)
UNINSTALLER="$REPO/client/macos/uninstall.sh"
[ -f "$UNINSTALLER" ] || { echo "SKIP - uninstaller not found at $UNINSTALLER"; exit 0; }

ROOT="$HOME/.lummacos-uninstall-test"
ROOT2="$HOME/.lummacos-uninstall-test-foreign"
ROOT3="$HOME/.lummacos-uninstall-test-plist"
PLIST=/Library/LaunchDaemons/com.luminum.client.plist
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

PLIST_BAK="$HOME/.lummacos-uninstall-test-plist.bak"
PLIST_PRE=0
[ -f "$PLIST" ] && { cp "$PLIST" "$PLIST_BAK"; PLIST_PRE=1; }
PLISTDIR_PRE=0
[ -d /Library/LaunchDaemons ] && PLISTDIR_PRE=1
cleanup() {
    rm -rf "$ROOT" "$ROOT2" "$ROOT3"
    if [ "$PLIST_PRE" -eq 1 ] && [ -f "$PLIST_BAK" ]; then
        cp "$PLIST_BAK" "$PLIST"
    else
        rm -f "$PLIST"
    fi
    rm -f "$PLIST_BAK"
    # Remove the directories the test created (never present on macOS).
    if [ "$PLISTDIR_PRE" -eq 0 ]; then
        rmdir /Library/LaunchDaemons /Library 2>/dev/null
    fi
}
trap cleanup EXIT

# make_install ROOT - fake install layout: marker, an executable named
# LuminumClient (a copy of /bin/sleep so pkill -x can match it), and the
# config/logs/run/modules directories.
make_install() {
    mkdir -p "$1/bin" "$1/config" "$1/logs" "$1/run" "$1/modules"
    cp "$(command -v sleep)" "$1/LuminumClient"
    echo "installed by install.sh on test" > "$1/.luminum-installer"
    echo "cfg" > "$1/config/client.conf.db"
}

run_uninstall() {
    bash "$UNINSTALLER" --install-root "$1"
}

# --- 1. happy path: layout deleted, pid-file process stopped --------------------
make_install "$ROOT"
"$ROOT/LuminumClient" 300 &
FAKEPID=$!
echo "$FAKEPID" > "$ROOT/run/client.pid"
sleep 0.2
OUT=$(run_uninstall "$ROOT" 2>&1); RC=$?
wait "$FAKEPID" 2>/dev/null
check "uninstall exits 0" $([ "$RC" -eq 0 ] && echo 0 || echo 1) "rc=$RC"
check "install root deleted" $([ ! -d "$ROOT" ] && echo 0 || echo 1)
check "client process stopped" $(! kill -0 "$FAKEPID" 2>/dev/null && echo 0 || echo 1)
check "reports pid stop" $(echo "$OUT" | grep -q "Stopped client (PID $FAKEPID)" && echo 0 || echo 1)
check "announces uninstalled" $(echo "$OUT" | grep -q "Luminum Client uninstalled." && echo 0 || echo 1)

# --- 2. idempotent re-run ---------------------------------------------------------
OUT=$(run_uninstall "$ROOT" 2>&1); RC=$?
check "re-run exits 0" $([ "$RC" -eq 0 ] && echo 0 || echo 1) "rc=$RC"
check "re-run reports missing directory" $(echo "$OUT" | grep -q "Install directory not present" && echo 0 || echo 1)

# --- 3. safety: system directories are refused ------------------------------------
OUT=$(bash "$UNINSTALLER" --install-root /Library 2>&1); RC=$?
check "refuses /Library" $([ "$RC" -ne 0 ] && echo "$OUT" | grep -q "refusing to delete a system directory" && echo 0 || echo 1) "rc=$RC"
OUT=$(bash "$UNINSTALLER" --install-root / 2>&1); RC=$?
check "refuses /" $([ "$RC" -ne 0 ] && echo 0 || echo 1) "rc=$RC"

# --- 4. safety: a non-Luminum directory is refused ---------------------------------
mkdir -p "$ROOT2"
echo x > "$ROOT2/unrelated"
OUT=$(run_uninstall "$ROOT2" 2>&1); RC=$?
check "refuses foreign directory" $([ "$RC" -ne 0 ] && echo "$OUT" | grep -q "not a Luminum client installation" && echo 0 || echo 1) "rc=$RC"
check "foreign directory untouched" $([ -f "$ROOT2/unrelated" ] && echo 0 || echo 1)
rm -rf "$ROOT2"

# --- 5. launchd plist handling (only when /Library/LaunchDaemons is writable) -----
if [ "$(id -u)" -eq 0 ] && mkdir -p /Library/LaunchDaemons 2>/dev/null; then
	# A plist pointing at the install root is removed with the install.
	make_install "$ROOT3"
	cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>com.luminum.client</string>
	<key>ProgramArguments</key>
	<array>
		<string>$ROOT3/LuminumClient</string>
	</array>
</dict>
</plist>
EOF
	OUT=$(run_uninstall "$ROOT3" 2>&1); RC=$?
	check "matching-root plist removed" $([ "$RC" -eq 0 ] && [ ! -f "$PLIST" ] && echo 0 || echo 1) "rc=$RC"
	check "reports plist removal" $(echo "$OUT" | grep -q "Removed $PLIST" && echo 0 || echo 1)

	# A plist pointing at a different root is left in place.
	make_install "$ROOT3"
	cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>com.luminum.client</string>
	<key>ProgramArguments</key>
	<array>
		<string>/somewhere/else/LuminumClient</string>
	</array>
</dict>
</plist>
EOF
	OUT=$(run_uninstall "$ROOT3" 2>&1); RC=$?
	check "foreign-root plist left in place" $([ "$RC" -eq 0 ] && [ -f "$PLIST" ] && echo 0 || echo 1) "rc=$RC"
	check "warns about foreign plist" $(echo "$OUT" | grep -q "WARNING: $PLIST references a different install root" && echo 0 || echo 1)
	rm -f "$PLIST"
else
	echo "skip - plist scenarios (not root or /Library/LaunchDaemons not writable)"
fi

echo
if [ "$FAILURES" -eq 0 ]; then
	echo "All macOS uninstaller tests passed."
	exit 0
else
	echo "$FAILURES test(s) FAILED."
	exit 1
fi
