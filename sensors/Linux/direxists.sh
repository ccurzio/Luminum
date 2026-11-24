#!/bin/sh
#
# Luminum "Directory Exists" Sensor (Linux)
# =========================================

if [ -d "${path}" ]; then
	echo "TRUE"
else
	echo "FALSE"
fi