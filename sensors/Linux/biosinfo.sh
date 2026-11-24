#!/bin/sh
#
# Luminum "BIOS Information" Sensor (Linux)
# =========================================

dmidecode -t 0 | awk '
	{ val = substr($0, index($0, ": ") + 2) }
	/^\tVendor:/        { vendor = val }
	/^\tVersion:/       { version = val }
	/^\tBIOS Revision:/ { revision = val }
	/^\tRelease Date:/  { releasedate = val }
	END { print vendor "|" version "|" revision "|" releasedate }
	'
