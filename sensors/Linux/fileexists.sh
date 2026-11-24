#!/bin/sh
#
# Luminum "File Exists" Sensor (Linux)
# ====================================

if [ -f "${path}" ]; then
	echo "TRUE"
else
	echo "FALSE"
fi