#!/bin/bash
#
# Luminum "Serial Number" Sensor (macOS)
# ======================================

/usr/sbin/ioreg -c IOPlatformExpertDevice -d 2 | /usr/bin/awk -F'"' '/IOPlatformSerialNumber/ {print $4}'
