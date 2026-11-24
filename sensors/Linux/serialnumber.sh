#!/bin/sh
#
# Luminum "Serial Number" Sensor (Linux)
# ======================================

if [ -r /sys/class/dmi/id/product_serial ]; then
	serial=$(cat /sys/class/dmi/id/product_serial)
else
	serial=$(dmidecode -s system-serial-number 2>/dev/null)
fi

serial=$(printf '%s' "$serial" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

case "$(printf '%s' "$serial" | tr '[:upper:]' '[:lower:]')" in ""|"system serial number"|"to be filled by o.e.m."|"default string"|"not specified"|"not applicable"|"none"|"0"|"123456789"|"0123456789")
	echo "Unavailable" ;;
	*)
	echo "$serial" ;;
esac
