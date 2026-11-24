#!/bin/bash
#
# Luminum "Manufacturer" Sensor (macOS)
# =====================================

ioreg -rd1 -c IOPlatformExpertDevice | awk -F'"' '/"manufacturer"/ {print $4; exit}'
