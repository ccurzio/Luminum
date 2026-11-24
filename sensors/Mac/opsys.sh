#!/bin/bash
#
# Luminum "Operating System" Sensor (macOS)
# =========================================

/usr/bin/sw_vers | /usr/bin/awk -F '\t+' '/ProductName/ {name=$2} /ProductVersion/ {version=$2} /BuildVersion/ {build=$2} END {print name, version, "(" build ")"}'
