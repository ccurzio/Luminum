#!/bin/sh
#
# Luminum "Operating System" Sensor (Linux)
# =========================================

if [ -e "/etc/os-release" ]; then
	PNAME=`/usr/bin/grep PRETTY_NAME /etc/os-release | /usr/bin/sed -E 's/^PRETTY_NAME\s?=\s?//; s/"//g'`
	case "$PNAME" in
		*Debian*)
			FULLVER=`/usr/bin/grep DEBIAN_VERSION_FULL /etc/os-release | /usr/bin/sed -E 's/^DEBIAN_VERSION_FULL\s?=\s?//; s/[()]//g'`
			echo $PNAME | /usr/bin/sed -E "s/[0-9]+/$FULLVER/"
			;;
		*Slackware*)
			if [ -e "/etc/slackware-version" ]; then
				/usr/bin/cat /etc/slackware-version
			else
				FULLVER=`/usr/bin/grep VERSION_ID /etc/os-release | /usr/bin/sed -E 's/^VERSION_ID\s?=\s?//'`
				echo "Slackware $FULLVER"
			fi
			;;
			*)
				echo $PNAME
				;;
		esac
fi