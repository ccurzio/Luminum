#!/usr/bin/env bash
#
# Luminum Client (macOS) uninstaller
# by Christopher R. Curzio (ccurzio@luminum.net)
#
# Removes the client completely, reversing everything install.sh does:
# stops and unregisters the com.luminum.client launchd daemon (deleting
# its plist in /Library/LaunchDaemons), stops any client process still
# running, and deletes the entire install root (binary, config, logs,
# modules, start/stop scripts).
#
# The install root is resolved in this order: an explicit --install-root,
# then the default /Library/Luminum/LuminumClient. The installer does not
# record a non-default root anywhere, so a custom root must be passed
# again here.
#
# Safety: the directory is only deleted if it looks like a Luminum client
# installation (it contains the .luminum-installer marker or the
# LuminumClient binary), and filesystem/system directories are never
# deleted. A launchd plist that points at a different install root is
# left in place.
#
# Usage: sudo bash uninstall.sh [options]
#
#   --install-root P   installation directory (default /Library/Luminum/LuminumClient)
#
set -u

ROOT="/Library/Luminum/LuminumClient"
LABEL="com.luminum.client"
PLIST="/Library/LaunchDaemons/${LABEL}.plist"

while [ $# -gt 0 ]; do
	case "$1" in
		--install-root) ROOT="${2:?--install-root requires a path}"; shift 2 ;;
		-h|--help)
			cat <<'USAGE'
Usage: sudo bash uninstall.sh [options]

  --install-root P   installation directory (default /Library/Luminum/LuminumClient)
USAGE
			exit 0 ;;
		*) echo "Unknown option: $1 (see --help)" >&2; exit 1 ;;
	esac
done

fail() { echo "ERROR: $*" >&2; exit 1; }

echo "Luminum Client (macOS) uninstaller"
echo "by Christopher R. Curzio <ccurzio@luminum.net>"
echo

# --- normalize and validate the install root -----------------------------------
case "$ROOT" in
	/*) : ;;
	*) fail "install root must be an absolute path: $ROOT" ;;
esac
case "$ROOT" in
	*/) ROOT="${ROOT%/}" ;;
esac
[ -n "$ROOT" ] || fail "install root is empty"

# --- safety: never delete a filesystem root or a system directory --------------
case "$ROOT" in
	"/"|"/Library"|"/Library/Luminum"|"/Users"|"$HOME")
		fail "refusing to delete a system directory: $ROOT" ;;
esac

# Non-root uninstalls are allowed only under $HOME (no /Library writes),
# mirroring the installer's rule.
if [ "$(id -u)" -ne 0 ]; then
	case "$ROOT" in
		"$HOME"/*) : ;;
		*) fail "must run as root to uninstall from $ROOT (use sudo, or run as the user who installed under \$HOME)" ;;
	esac
fi

echo "Install root: $ROOT"

# --- verify this is a Luminum client installation -------------------------------
if [ -d "$ROOT" ]; then
	if [ ! -f "$ROOT/.luminum-installer" ] && [ ! -x "$ROOT/LuminumClient" ]; then
		fail "$ROOT exists but is not a Luminum client installation (no .luminum-installer marker or LuminumClient binary); refusing to delete it"
	fi
fi

# --- stop and unregister the launchd service -------------------------------------
launchd_available() {
	[ -x /bin/launchctl ] || return 1
	[ "$(id -u)" -eq 0 ] || return 1
	return 0
}

if [ -f "$PLIST" ]; then
	if ! grep -qF "$ROOT" "$PLIST"; then
		echo "WARNING: $PLIST references a different install root; leaving it in place"
	else
		if launchd_available && launchctl list "$LABEL" >/dev/null 2>&1; then
			echo "Stopping service $LABEL..."
			launchctl unload "$PLIST" || echo "WARNING: launchctl unload $PLIST failed"
		fi
		rm -f "$PLIST" || fail "cannot remove $PLIST"
		echo "Removed $PLIST"
	fi
else
	echo "Service plist not present; skipping."
fi

# --- stop any client process still running ----------------------------------------
# (e.g. started via bin/start-client instead of launchd; the service is stopped
# first so launchd's KeepAlive cannot restart it)
if [ -f "$ROOT/run/client.pid" ]; then
	PID=$(cat "$ROOT/run/client.pid" 2>/dev/null)
	if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
		# A stale pid file may hold a recycled pid; only kill the client.
		COMM=$(ps -p "$PID" -o comm= 2>/dev/null)
		case "$COMM" in
			*LuminumClient)
				kill "$PID" 2>/dev/null && echo "Stopped client (PID $PID)" ;;
			*)
				echo "WARNING: PID $PID in client.pid is not the Luminum client ($COMM); not killing it" ;;
		esac
	fi
fi
pkill -x LuminumClient 2>/dev/null || true
sleep 1

# --- delete the install directory ---------------------------------------------------
if [ -d "$ROOT" ]; then
	echo "Deleting $ROOT ..."
	rm -rf "$ROOT" || fail "cannot delete $ROOT"
	echo "Deleted $ROOT"
else
	echo "Install directory not present; skipping."
fi

# Remove the parent directory only if it is now empty, so any other Luminum
# component's files are left untouched.
PARENT=$(dirname "$ROOT")
if [ -d "$PARENT" ] && [ -z "$(ls -A "$PARENT" 2>/dev/null)" ]; then
	rmdir "$PARENT" 2>/dev/null && echo "Removed now-empty $PARENT"
fi

echo
echo "Luminum Client uninstalled."
exit 0
