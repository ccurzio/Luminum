#!/bin/sh
#
# Luminum "Is Virtual" Sensor (Linux)
# ===================================

if command -v systemd-detect-virt >/dev/null 2>&1; then
	if systemd-detect-virt --quiet; then
		echo "TRUE"
	else
		echo "FALSE"
	fi
fi

if grep -qiE 'hypervisor|vmware|kvm|qemu|virtualbox|xen|microsoft|parallels' \
/proc/cpuinfo 2>/dev/null || grep -qiE 'vmware|virtualbox|qemu|kvm|xen|microsoft|parallels|amazon|google' \
/sys/class/dmi/id/sys_vendor 2>/dev/null; then
	echo "TRUE"
fi

echo "FALSE"