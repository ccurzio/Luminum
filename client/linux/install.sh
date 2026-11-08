#!/usr/bin/env bash
#
# Luminum Client (Linux) installer
# by Christopher R. Curzio (ccurzio@luminum.net)
#
# Installs the client and its Lumy modules into the install root
# (default /opt/Luminum/LuminumClient). The distribution ships the
# prebuilt binaries in dist/ next to this script:
#
#   dist/LuminumClient                 client binary
#   dist/modules/<lumy>/Lumy_*         Lumy module binaries
#
# The installed layout:
#
#   <root>/LuminumClient           client binary
#   <root>/.luminum-installer      marker: installed by this script
#   <root>/bin/start-client        start/stop scripts (non-systemd hosts)
#   <root>/bin/stop-client
#   <root>/config/                 client.conf.db, server.crt,
#                                  server-signing.crt (wizard)
#   <root>/logs/                   client-stdout.log
#   <root>/run/                    client.pid
#   <root>/modules/<lumy>/         Lumy module binaries
#
# Install modes, detected from the install root:
#   fresh      the install root does not exist; install everything
#   upgrade    the install root was created by this installer (marker
#              present); stop the client and replace the files
#   configure  the install root already holds an installation from
#              another source (e.g. a .deb or .rpm package); the
#              existing files are left untouched - the installer only
#              configures the client (wizard) and starts it
# An explicit --binary always installs the given binary over whatever
# is present.
#
# A luminum-client.service systemd unit is installed when systemd is
# usable (fresh/upgrade only); otherwise the bin/ scripts are the only
# control path. The generated scripts and unit export LUMINUM_HOME=<root>
# so non-default install roots work for the client and every Lumy.
#
# Usage: sudo bash install.sh [options]
#
#   --install-root P   installation directory (default /opt/Luminum/LuminumClient)
#   --binary P         client binary to install (default: dist/LuminumClient)
#   --no-setup         skip the configuration wizard
#   --no-start         install without starting the client
#
set -u

ROOT="/opt/Luminum/LuminumClient"
BINARG=""
DO_SETUP=1
DO_START=1

while [ $# -gt 0 ]; do
	case "$1" in
		--install-root) ROOT="${2:?--install-root requires a path}"; shift 2 ;;
		--binary)       BINARG="${2:?--binary requires a path}"; shift 2 ;;
		--no-setup)     DO_SETUP=0; shift ;;
		--no-start)     DO_START=0; shift ;;
		-h|--help)
			cat <<'USAGE'
Usage: sudo bash install.sh [options]

  --install-root P   installation directory (default /opt/Luminum/LuminumClient)
  --binary P         client binary to install (default: dist/LuminumClient)
  --no-setup         skip the configuration wizard
  --no-start         install without starting the client
USAGE
			exit 0 ;;
		*) echo "Unknown option: $1 (see --help)" >&2; exit 1 ;;
	esac
done

fail() { echo "ERROR: $*" >&2; exit 1; }

echo "Luminum Client (Linux) installer"
echo "by Christopher R. Curzio <ccurzio@luminum.net>"
echo

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

# The client (and every Lumy) resolve their install root from
# LUMINUM_HOME, falling back to /opt/Luminum/LuminumClient. Pin it so
# the wizard and any non-default install root land in $ROOT.
export LUMINUM_HOME="$ROOT"

# Non-root installs are allowed only under $HOME (no /etc writes).
if [ "$(id -u)" -ne 0 ]; then
	case "$ROOT" in
		"$HOME"/*) : ;;
		*) fail "must run as root to install to $ROOT (use sudo, or --install-root under \$HOME)" ;;
	esac
fi

systemd_available() {
	[ -x /usr/bin/systemctl ] || return 1
	case "$(systemctl is-system-running 2>/dev/null)" in
		running|degraded) return 0 ;;
	esac
	return 1
}

# --- install mode --------------------------------------------------------------------
MARKER="$ROOT/.luminum-installer"
if [ ! -d "$ROOT" ]; then
	MODE=fresh
elif [ -f "$MARKER" ]; then
	MODE=upgrade
elif [ -x "$ROOT/LuminumClient" ]; then
	MODE=configure
else
	fail "$ROOT exists but is not a Luminum client installation (no LuminumClient binary); remove it or choose another --install-root"
fi
# An explicit --binary is a deliberate replacement.
if [ "$MODE" = "configure" ] && [ -n "$BINARG" ]; then
	MODE=upgrade
fi

if [ "$MODE" = "configure" ]; then
	echo "Existing installation found at $ROOT; configuring in place (no files will be replaced)."
else
	# Stop a client left over from a previous install so ports and the
	# binary are free (idempotent re-runs).
	if [ -x "$ROOT/bin/stop-client" ]; then
		"$ROOT/bin/stop-client" >/dev/null 2>&1 || true
	fi

	# --- obtain the client binary ------------------------------------------------
	if [ -n "$BINARG" ]; then
		CLIENT_BIN="$BINARG"
	else
		CLIENT_BIN="$SCRIPT_DIR/dist/LuminumClient"
	fi
	[ -x "$CLIENT_BIN" ] || \
		fail "missing binary: $CLIENT_BIN (the distribution must include the prebuilt LuminumClient binary in dist/)"

	# --- install layout -------------------------------------------------------------
	mkdir -p "$ROOT/bin" "$ROOT/config" "$ROOT/logs" "$ROOT/run" "$ROOT/modules" || \
		fail "cannot create directories under $ROOT"
	install -m 0755 "$CLIENT_BIN" "$ROOT/LuminumClient" || fail "cannot install client binary"

	# --- Lumy modules -------------------------------------------------------------------
	# Each directory under dist/modules/ mirrors its installed location:
	# dist/modules/<lumy>/Lumy_* -> <root>/modules/<lumy>/Lumy_*.
	MODDIST="$SCRIPT_DIR/dist/modules"
	if [ -d "$MODDIST" ]; then
		for mdir in "$MODDIST"/*/; do
			[ -d "$mdir" ] || continue
			mname=$(basename "$mdir")
			installed=0
			for f in "$mdir"*; do
				[ -f "$f" ] && [ -x "$f" ] || continue
				mkdir -p "$ROOT/modules/$mname" || fail "cannot create $ROOT/modules/$mname"
				install -m 0755 "$f" "$ROOT/modules/$mname/" || fail "cannot install $f"
				installed=1
			done
			if [ "$installed" -eq 0 ]; then
				echo "WARNING: no Lumy binaries in $mdir; module $mname skipped"
			fi
		done
	fi

	# --- start/stop scripts --------------------------------------------------------------------
	cat > "$ROOT/bin/start-client" <<EOF
#!/bin/sh
# Luminum client start script (generated by install)
export LUMINUM_HOME="$ROOT"
cd "$ROOT"
nohup ./LuminumClient >> "$ROOT/logs/client-stdout.log" 2>&1 &
echo \$! > "$ROOT/run/client.pid"
echo "Luminum client started (PID \$(cat "$ROOT/run/client.pid"))"
EOF
	cat > "$ROOT/bin/stop-client" <<EOF
#!/bin/sh
# Luminum client stop script (generated by install)
if [ -f "$ROOT/run/client.pid" ]; then
	PID=\$(cat "$ROOT/run/client.pid")
	kill "\$PID" 2>/dev/null && echo "Luminum client stopped (PID \$PID)"
	rm -f "$ROOT/run/client.pid"
else
	echo "Luminum client is not running (no pid file)"
fi
EOF
	chmod 0700 "$ROOT/bin/start-client" "$ROOT/bin/stop-client" || fail "cannot write bin/ scripts"

	# This root was created by this installer; future runs upgrade it
	# instead of treating it as a foreign installation.
	echo "installed by install.sh on $(date -u '+%Y-%m-%d %H:%M:%S UTC')" > "$MARKER" || \
		fail "cannot write $MARKER"

	# --- systemd unit (when usable) -------------------------------------------------------------
	UNIT=/etc/systemd/system/luminum-client.service
	if [ "$(id -u)" -eq 0 ] && systemd_available; then
		cat > "$UNIT" <<EOF
# Luminum client service (generated by install)
[Unit]
Description=Luminum Client
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment=LUMINUM_HOME="$ROOT"
WorkingDirectory=$ROOT
ExecStart=$ROOT/LuminumClient
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
		chmod 0644 "$UNIT" || fail "cannot write $UNIT"
		systemctl daemon-reload || fail "systemctl daemon-reload failed"
		echo "Installed $UNIT"
	else
		echo "systemd not usable; bin/start-client and bin/stop-client are the control path"
	fi
fi

# --- configuration wizard ----------------------------------------------------------------------
if [ ! -f "$ROOT/config/client.conf.db" ] && [ "$DO_SETUP" -eq 1 ]; then
	echo
	"$ROOT/LuminumClient" -s || {
		echo
		echo "Configuration wizard failed; re-run '$ROOT/LuminumClient -s' and start the client manually."
		exit 1
	}
fi

# --- start ------------------------------------------------------------------------------------------
port_in_use() {
	(exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null && return 0
	return 1
}

if [ "$DO_START" -eq 1 ]; then
	if [ ! -f "$ROOT/config/client.conf.db" ]; then
		echo "Client is not configured; skipping start (run '$ROOT/LuminumClient -s' first)."
	elif port_in_use 10461; then
		if [ "$MODE" = "configure" ]; then
			echo "Client is already running; nothing to start."
		else
			fail "port 10461 is already in use - a client from a previous install is probably still running; stop it ($ROOT/bin/stop-client) and re-run"
		fi
	else
		started_via_unit=0
		if [ -x "$ROOT/bin/start-client" ]; then
			"$ROOT/bin/start-client" || fail "client start failed"
		elif [ "$(id -u)" -eq 0 ] && [ -f /etc/systemd/system/luminum-client.service ] && systemd_available; then
			systemctl start luminum-client || fail "client start failed"
			started_via_unit=1
		else
			fail "no control path found at $ROOT (no bin/start-client and no systemd unit)"
		fi
		if [ "$started_via_unit" -eq 1 ]; then
			sleep 1
			systemctl is-active luminum-client 2>/dev/null | grep -q '^active' || {
				echo "ERROR: luminum-client service is not active after start"
				systemctl status luminum-client --no-pager 2>/dev/null | head -n 15
				exit 1
			}
		else
			# Watch the client for a few seconds: a bind failure can take a
			# moment after start to kill the process, and we fail fast if it
			# dies early.
			state=pending
			for _ in 1 2 3 4 5; do
				if [ -f "$ROOT/run/client.pid" ]; then
					pid=$(cat "$ROOT/run/client.pid")
					if kill -0 "$pid" 2>/dev/null; then state=up; break; fi
					state=dead; break
				fi
				sleep 1
			done
			if [ "$state" != "up" ]; then
				echo "ERROR: client process died during startup"
				tail -n 15 "$ROOT/logs/client-stdout.log" 2>/dev/null
				exit 1
			fi
		fi
	fi
fi

echo
if [ "$MODE" = "configure" ]; then
	echo "Luminum Client configured (existing installation):"
else
	echo "Luminum Client installed:"
fi
echo "  Install root:  $ROOT"
echo "  Start:         $ROOT/bin/start-client"
echo "  Stop:          $ROOT/bin/stop-client"
[ -f /etc/systemd/system/luminum-client.service ] && [ "$(id -u)" -eq 0 ] && \
	echo "  Service unit:  /etc/systemd/system/luminum-client.service"
echo "  Configure:     $ROOT/LuminumClient -s"
exit 0
