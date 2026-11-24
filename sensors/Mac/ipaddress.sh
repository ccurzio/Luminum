#!/bin/sh
#
# Luminum "IP Address" Sensor (macOS)
# ===================================

/sbin/ifconfig | /usr/bin/awk '$1 == "inet" || $1 == "inet6" { print $2 }' | /usr/bin/grep -Ev '^(127\.|::1$|fe80::1%lo0$)' | /usr/bin/sed 's/%.*//'
