#!/bin/sh
#
# Luminum "Last Logged In User" Sensor (Linux)
# ============================================

records=$(last -w | awk 'NF && $1 != "reboot" && $1 != "shutdown" && $2 != "begins"')
user=$(printf '%s\n' "$records" | awk '/still logged in/ {print $1; exit}')
[ -z "$user" ] && user=$(printf '%s\n' "$records" | awk 'NR == 1 {print $1}')
echo "$user"