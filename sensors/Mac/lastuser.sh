#!/bin/bash
#
# Luminum "Last Logged In User" Sensor (macOS)
# ============================================

records=$(/usr/bin/last | /usr/bin/awk 'NF && $1 != "reboot" && $1 != "shutdown" && $2 != "begins"')
user=$(/usr/bin/awk '/still logged in/ {print $1; exit}' <<<"$records")
[[ -z $user ]] && user=$(/usr/bin/awk 'NR == 1 {print $1}' <<<"$records")
echo "$user"
