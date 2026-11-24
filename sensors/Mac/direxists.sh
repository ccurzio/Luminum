#!/bin/bash
#
# Luminum "Directory Exists" Sensor (macOS)
# =========================================

if [[ -d "$1" ]]; then
	echo "TRUE"
else
	echo "FALSE"
fi
