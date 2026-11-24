#!/bin/bash
#
# Luminum "Computer Name" Sensor (macOS)
# ======================================

is_fqdn() {
	[[ "$1" == *.* && "$1" != localhost* && "$1" != *.local ]]
	}

short=$(scutil --get LocalHostName 2>/dev/null || hostname -s)

fqdn=$(scutil --get HostName 2>/dev/null)

is_fqdn "$fqdn" || fqdn=$(hostname 2>/dev/null)

if ! is_fqdn "$fqdn"; then
	iface=$(route -n get default 2>/dev/null | awk '/interface:/ {print $2}')
	ip=$([ -n "$iface" ] && ipconfig getifaddr "$iface" 2>/dev/null)
	if [ -n "$ip" ]; then
		fqdn=$(dscacheutil -q host -a ip_address "$ip" 2>/dev/null | awk '/^name:/ {print $2; exit}')
	fi
fi

if is_fqdn "$fqdn"; then
	echo "${fqdn%.}"
else
	echo "$short"
fi
