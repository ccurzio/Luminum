#!/bin/bash
#
# Luminum "Uptime" Sensor (macOS)
# ===============================

/usr/bin/uptime | /usr/bin/awk '{
	if (match($0, /up +([0-9]+ days?, +)?[0-9]+:[0-9]+/)) {
		s = substr($0, RSTART, RLENGTH)
		sub(/^up +/, "", s)
		sub(/ days?/, " Days", s)
		gsub(/, +/, ", ", s)
		print s
		}
	else if (match($0, /up +([0-9]+ days?, +)?[0-9]+ mins?/)) {
		s = substr($0, RSTART, RLENGTH)
		sub(/^up +/, "", s)
		sub(/ days?/, " Days", s)
		sub(/ mins?/, " Minutes", s)
		gsub(/, +/, ", ", s)
		print s
		}
	else if (match($0, /up +[0-9]+ secs?/)) {
		s = substr($0, RSTART, RLENGTH)
		sub(/^up +/, "", s)
		sub(/ secs?/, " Seconds", s)
		print s
		}
	}'