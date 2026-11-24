#!/bin/sh
#
# Luminum "IP Address" Sensor (Linux)
# ===================================

if command -v ip >/dev/null 2>&1; then
        ip -o addr show | awk '{ split($4, a, "/"); print a[1] }'
else
        ifconfig -a | awk '$1 == "inet" || $1 == "inet6" {
                a = ($2 == "addr:") ? $3 : $2
                sub(/^addr:/, "", a); sub(/\/.*/, "", a)
                print a
        }'
fi | grep -Ev '^(127\.|::1$)'
