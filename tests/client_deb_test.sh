#!/usr/bin/env bash
# .deb packaging test: builds the luminum-client .deb via mkdeb.sh and verifies
# the package structure WITHOUT installing it (dpkg -i requires root, which this
# environment does not have, so a live install is out of scope here). Checks:
#   - the .deb builds
#   - control fields (Package, Architecture, Depends, Description)
#   - payload: the client binary, start/stop scripts, systemd unit, and the
#     runtime dirs are present with root/root ownership and the right perms
#   - the extracted binary is the Luminum client (runs --help)
#   - the start/stop scripts and unit pin LUMINUM_HOME / ExecStart to the
#     install root
#   - the maintainer scripts (postinst/prerm/postrm) are present, executable,
#     and syntactically valid; postinst carries the config.ini import and the
#     configure/start decision, prerm stops the service
#
# Usage: bash tests/client_deb_test.sh
set -u
REPO=$(cd "$(dirname "$0")/.." && pwd)
MKDEB="$REPO/client/linux/mkdeb.sh"

[ -x "$MKDEB" ] || { echo "SKIP - mkdeb.sh not found"; exit 0; }
command -v dpkg-deb >/dev/null 2>&1 || { echo "SKIP - dpkg-deb not available"; exit 0; }

RUN="$HOME/.lumdeb-test.$$"
DEB="$RUN/luminum-client.deb"
EXTRACT="$RUN/extract"
CTRL="$RUN/ctrl"
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

cleanup() {
	if [ "$FAILURES" -gt 0 ]; then
		echo "Artifacts left in $RUN for inspection."
	else
		rm -rf "$RUN"
	fi
}
trap cleanup EXIT

mkdir -p "$RUN" || exit 1

# --- build the .deb ------------------------------------------------------------
bash "$MKDEB" --out "$DEB" > "$RUN/mkdeb.log" 2>&1
check "mkdeb.sh built the .deb" $([ -s "$DEB" ]; echo $?) "see $RUN/mkdeb.log"
[ -s "$DEB" ] || exit 1

# --- control fields -------------------------------------------------------------
INFO=$(dpkg-deb --info "$DEB" 2>/dev/null)
check "control: Package is luminum-client" \
	$(printf '%s\n' "$INFO" | grep -q '^ Package: luminum-client$'; echo $?)
check "control: Architecture is amd64" \
	$(printf '%s\n' "$INFO" | grep -q '^ Architecture: amd64$'; echo $?)
check "control: Depends lists the shared libraries" \
	$(printf '%s\n' "$INFO" | grep '^ Depends:' | grep -q 'libc6' \
		&& printf '%s\n' "$INFO" | grep '^ Depends:' | grep -q 'libssl3'; echo $?)
check "control: Description present" \
	$(printf '%s\n' "$INFO" | grep -q '^ Description: Luminum endpoint client'; echo $?)

# --- payload (dpkg-deb --contents) ----------------------------------------------
CONTENTS=$(dpkg-deb --contents "$DEB" 2>/dev/null)
check "payload: client binary present, 0755, root/root" \
	$(printf '%s\n' "$CONTENTS" | grep -Eq '^-rwxr-xr-x root/root .* ./opt/Luminum/LuminumClient/LuminumClient$'; echo $?)
check "payload: start-client present, 0700, root/root" \
	$(printf '%s\n' "$CONTENTS" | grep -Eq '^-rwx------ root/root .* ./opt/Luminum/LuminumClient/bin/start-client$'; echo $?)
check "payload: stop-client present, 0700, root/root" \
	$(printf '%s\n' "$CONTENTS" | grep -Eq '^-rwx------ root/root .* ./opt/Luminum/LuminumClient/bin/stop-client$'; echo $?)
check "payload: systemd unit present, 0644, root/root" \
	$(printf '%s\n' "$CONTENTS" | grep -Eq '^-rw-r--r-- root/root .* ./etc/systemd/system/luminum-client.service$'; echo $?)
for d in config logs run modules; do
	check "payload: $d/ directory present" \
		$(printf '%s\n' "$CONTENTS" | grep -Eq "^drwxr-xr-x root/root .* ./opt/Luminum/LuminumClient/$d/$"; echo $?)
done

# --- extracted payload ----------------------------------------------------------
mkdir -p "$EXTRACT"
dpkg-deb --extract "$DEB" "$EXTRACT" 2>/dev/null
BIN="$EXTRACT/opt/Luminum/LuminumClient/LuminumClient"
check "extract: client binary is executable" $([ -x "$BIN" ]; echo $?)
# The extracted binary must be the Luminum client (runs and identifies itself).
LUMINUM_HOME="$RUN/home" "$BIN" --help > "$RUN/help.txt" 2>&1
check "extract: binary runs --help (exit 0)" $([ $? -eq 0 ]; echo $?)
check "extract: --help identifies the Luminum client" \
	$(grep -q 'Luminum Client' "$RUN/help.txt"; echo $?)
# start/stop scripts pin LUMINUM_HOME to the install root.
check "extract: start-client pins LUMINUM_HOME" \
	$(grep -q 'LUMINUM_HOME="/opt/Luminum/LuminumClient"' "$EXTRACT/opt/Luminum/LuminumClient/bin/start-client"; echo $?)
check "extract: stop-client references the pid file" \
	$(grep -q '/opt/Luminum/LuminumClient/run/client.pid' "$EXTRACT/opt/Luminum/LuminumClient/bin/stop-client"; echo $?)
# the systemd unit points ExecStart at the installed binary and sets LUMINUM_HOME.
check "extract: unit ExecStart points at the installed binary" \
	$(grep -q '^ExecStart=/opt/Luminum/LuminumClient/LuminumClient$' "$EXTRACT/etc/systemd/system/luminum-client.service"; echo $?)
check "extract: unit sets LUMINUM_HOME" \
	$(grep -q '^Environment=LUMINUM_HOME="/opt/Luminum/LuminumClient"$' "$EXTRACT/etc/systemd/system/luminum-client.service"; echo $?)

# --- maintainer scripts (control.tar) -------------------------------------------
mkdir -p "$CTRL"
dpkg-deb --ctrl-tarfile "$DEB" 2>/dev/null | tar -x -C "$CTRL"
for s in postinst prerm postrm; do
	check "control.tar: $s present" $([ -f "$CTRL/$s" ]; echo $?)
	check "control.tar: $s is executable" $([ -x "$CTRL/$s" ]; echo $?)
	check "control.tar: $s passes sh -n" $(sh -n "$CTRL/$s" 2>/dev/null; echo $?)
done
# postinst carries the provisioning import and the configure/start decision.
check "postinst: imports config.ini when present" \
	$(grep -q -- '--import' "$CTRL/postinst" && grep -q 'config.ini' "$CTRL/postinst"; echo $?)
check "postinst: starts the service only when configured" \
	$(grep -q 'client.conf.db' "$CTRL/postinst" && grep -q 'systemctl start luminum-client' "$CTRL/postinst"; echo $?)
check "prerm: stops the service" \
	$(grep -q 'systemctl stop luminum-client' "$CTRL/prerm"; echo $?)

echo "------------------------------------------------------------"
if [ "$FAILURES" -gt 0 ]; then
	echo "FAILED: $FAILURES check(s) failed"
	echo "Artifacts left in $RUN for inspection (mkdeb.log)."
	exit 1
fi
echo "All checks passed."
exit 0
