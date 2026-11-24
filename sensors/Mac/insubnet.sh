#!/bin/bash
#
# Luminum "In Subnet" Sensor (macOS)
# ==================================

NIB=(0000 0001 0010 0011 0100 0101 0110 0111 1000 1001 1010 1011 1100 1101 1110 1111)

v4_bits() {
	[[ $1 =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || return 1
	local i o b
	BITS=""
	for i in 1 2 3 4; do
		o=$(( 10#${BASH_REMATCH[i]} ))
		(( o <= 255 )) || return 1
		BITS+="${NIB[o >> 4]}${NIB[o & 15]}"
	done
	}

v6_bits() {
	local a=$1 g h c l r i
	local -a L=() R=() G=()
	[[ $a =~ ^[0-9a-fA-F:.]+$ ]] || return 1
	[[ $a == :* && $a != ::* ]] && return 1
	[[ $a == *: && $a != *:: ]] && return 1
	[[ $a == *::*::* ]] && return 1

	if [[ $a == *.* ]]; then
		v4_bits "${a##*:}" || return 1
		a="${a%:*}:$(printf '%x:%x' $((2#${BITS:0:16})) $((2#${BITS:16:16})))"
	fi

	if [[ $a == *::* ]]; then
		l=${a%%::*}; r=${a#*::}
		[[ -n $l ]] && IFS=: read -ra L <<< "$l"
		[[ -n $r ]] && IFS=: read -ra R <<< "$r"
		(( ${#L[@]} + ${#R[@]} <= 7 )) || return 1
		G=("${L[@]}")
		for (( i = ${#L[@]} + ${#R[@]}; i < 8; i++ )); do G+=(0); done
		G+=("${R[@]}")
	else
		IFS=: read -ra G <<< "$a"
		(( ${#G[@]} == 8 )) || return 1
	fi

	BITS=""
	for g in "${G[@]}"; do
		[[ $g =~ ^[0-9a-fA-F]{1,4}$ ]] || return 1
		h=$(printf '%04x' $((16#$g)))
		for (( i = 0; i < 4; i++ )); do
			c=${h:i:1}
			BITS+="${NIB[16#$c]}"
		done
	done
	}

to_bits() { if [[ $1 == *:* ]]; then v6_bits "$1"; else v4_bits "$1"; fi }

subnet="$1"
if [[ $subnet != */* ]]; then echo FALSE; exit 0; fi
net="${subnet%/*}"
prefix="${subnet#*/}"

if ! [[ $prefix =~ ^[0-9]{1,3}$ ]] || ! to_bits "$net"; then echo FALSE; exit 0; fi
prefix=$(( 10#$prefix ))
netbits=$BITS
(( prefix <= ${#netbits} )) || { echo FALSE; exit 0; }

while read -r addr; do
	to_bits "$addr" || continue
	(( ${#BITS} == ${#netbits} )) || continue
	if [[ ${BITS:0:prefix} == "${netbits:0:prefix}" ]]; then
		echo TRUE
		exit 0
	fi
done < <(ifconfig 2>/dev/null | awk '$1 == "inet" || $1 == "inet6" {sub(/%.*/, "", $2); print $2}')

echo FALSE
