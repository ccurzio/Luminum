#!/bin/sh
#
# Luminum "Is Virtual" Sensor (macOS)
# ===================================

PATH=/usr/bin:/bin:/usr/sbin:/sbin

is_vm() {
	[ "$(sysctl -n kern.hv_vmm_present 2>/dev/null)" = "1" ] && return 0

	if [ "$(sysctl -n sysctl.proc_translated 2>/dev/null)" != "1" ]; then
		sysctl -n machdep.cpu.features 2>/dev/null | grep -qw VMM && return 0
	fi

	sysctl -n hw.model 2>/dev/null | grep -qiE 'vmware|virtual|parallels|qemu' && return 0

	ioreg -rd1 -c IOPlatformExpertDevice 2>/dev/null \
		| grep -iE '"(manufacturer|model|product-name)"' \
		| grep -qiE 'vmware|virtualbox|innotek|parallels|qemu|virtual' && return 0

	ioreg -rc IOPCIDevice 2>/dev/null \
		| grep -qiE '"vendor-id" = <(ee800000|ad150000|b81a0000|f41a0000)>' && return 0

	return 1
	}

if is_vm; then
	echo "TRUE"
else
	echo "FALSE"
fi

exit 0
