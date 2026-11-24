#!/bin/bash
#
# Luminum "File Exists" Sensor (macOS)
# ====================================

if [[ -f "$1" ]]; then
	echo "TRUE"
else
	echo "FALSE"
fi
