#!/bin/sh
#
# Luminum "Computer Name" Sensor (Linux)
# ======================================

short=$(hostname -s 2>/dev/null || hostname 2>/dev/null || uname -n)
fqdn=$(timeout 3 hostname -f 2>/dev/null)

case "$fqdn" in
	*.*) ;;
	*) fqdn=$(timeout 3 getent ahosts "$short" 2>/dev/null | awk 'NR==1 && $3 ~ /\./ {print $3}') ;;
esac

case "$fqdn" in
	*.*) [ "$fqdn" != localhost* ] && echo "$fqdn" || echo "$short" ;;
	*) echo "$short" ;;
esac
