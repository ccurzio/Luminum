<?php
//
// Pure parsing/formatting helpers for the System Information page
// (system/sysinfo.php). Kept separate from the page so they can be
// unit-tested without a DB connection or session
// (tests/console_sysinfo_test.php).
//

// Parse the text of /proc/meminfo into the kB values the Memory tab
// displays. Fields the page does not use are ignored, and a missing
// field (or an empty/non-string result, e.g. shell_exec failing) reads
// as 0 so the page still renders.
//
function luminum_meminfo_parse($text) {
	$vals = ['MemTotal' => 0, 'MemFree' => 0, 'MemAvailable' => 0, 'SwapTotal' => 0, 'SwapFree' => 0];
	if (!is_string($text)) {
		return $vals;
	}
	foreach (preg_split('/\r\n|\n|\r/', $text) as $line) {
		if (preg_match('/^(\w+):\s+(\d+)\s+kB$/', $line, $m) && isset($vals[$m[1]])) {
			$vals[$m[1]] = (int)$m[2];
		}
	}
	return $vals;
}

// Format a kilobyte count the way the Memory tab displays it: whole KB
// below 1 MB, otherwise MB/GB/TB with one decimal (a trailing ".0" is
// dropped). Non-numeric and negative input clamps to 0.
//
function luminum_mem_kb_human($kb) {
	$kb = is_numeric($kb) ? (int)$kb : 0;
	if ($kb < 0) {
		$kb = 0;
	}
	$units = ['KB' => 1, 'MB' => 1024, 'GB' => 1024 * 1024, 'TB' => 1024 * 1024 * 1024];
	$unit = 'KB';
	foreach ($units as $name => $size) {
		if ($kb >= $size) {
			$unit = $name;
		}
	}
	if ($unit === 'KB') {
		return "$kb KB";
	}
	$str = rtrim(rtrim(number_format($kb / $units[$unit], 1, '.', ''), '0'), '.');
	return "$str $unit";
}

// Parse the output of `dmidecode -t memory` into one entry per memory
// slot. A block begins at a line reading exactly "Memory Device";
// everything else (the tool's header lines, other record types) is
// ignored. A slot whose Size is "No Module Installed" (or has no Size
// at all) is reported with installed = false. Returns [] for empty or
// unreadable output (dmidecode missing, not permitted to read the
// SMBIOS data, or a platform without it).
//
function luminum_mem_dmidecode_slots($text) {
	$slots = [];
	if (!is_string($text) || $text === '') {
		return $slots;
	}
	$want = ['Size', 'Form Factor', 'Locator', 'Bank Locator', 'Type', 'Speed', 'Manufacturer', 'Part Number'];
	$cur = null;
	foreach (preg_split('/\r\n|\n|\r/', $text) as $line) {
		$trim = trim($line);
		if ($trim === 'Memory Device') {
			$cur = ['installed' => false];
			foreach ($want as $field) {
				$cur[$field] = '';
			}
			$slots[] = $cur;
			continue;
		}
		if ($cur === null) {
			continue;
		}
		if (preg_match('/^([^:]+):\s*(.*)$/', $trim, $m) && in_array(trim($m[1]), $want, true)) {
			$cur[trim($m[1])] = trim($m[2]);
			$slots[count($slots) - 1] = $cur;
		}
	}
	foreach ($slots as $i => $slot) {
		$slots[$i]['installed'] = ($slot['Size'] !== '' && stripos($slot['Size'], 'No Module Installed') === false);
	}
	return $slots;
}

// Map a PCI class code (the /sys class file, e.g. "0x030000", or the bare
// hex "030000") to a Device Manager-style category name. The base class is
// the first two hex digits; two base classes get special treatment: USB
// host controllers (0c03) list under their own category, and wireless
// controllers (0d) join Network adapters, as Device Manager does.
//
function luminum_pci_class_category($class) {
	$class = strtolower(trim((string)$class));
	$class = preg_replace('/^0x/', '', $class);
	if (!preg_match('/^[0-9a-f]{6}$/', $class)) {
		return 'Other devices';
	}
	$base = substr($class, 0, 2);
	$sub = substr($class, 2, 2);
	if ($base === '0c' && $sub === '03') {
		return 'USB controllers';
	}
	$map = [
		'00' => 'Other devices',
		'01' => 'Storage controllers',
		'02' => 'Network adapters',
		'03' => 'Display adapters',
		'04' => 'Sound controllers',
		'05' => 'Memory controllers',
		'06' => 'System devices',
		'07' => 'Communication ports',
		'08' => 'System peripherals',
		'09' => 'Input device controllers',
		'0a' => 'Docking stations',
		'0b' => 'Computing devices',
		'0c' => 'Serial bus controllers',
		'0d' => 'Network adapters',
		'0e' => 'Processors',
		'0f' => 'I/O memory controllers',
		'10' => 'Encryption controllers',
		'11' => 'Signal processing controllers',
		'12' => 'Processing accelerators',
		'13' => 'Non-essential instrumentation',
		'ff' => 'Other devices',
	];
	return isset($map[$base]) ? $map[$base] : 'Other devices';
}

// Map a PCI vendor ID (the /sys vendor file, e.g. "0x8086") to a vendor
// name. The map covers the common server/workstation vendors; anything
// unknown reports its raw ID.
//
function luminum_pci_vendor_name($vendor) {
	$vendor = strtolower(trim((string)$vendor));
	$vendor = preg_replace('/^0x/', '', $vendor);
	if (!preg_match('/^[0-9a-f]{4}$/', $vendor)) {
		return 'Unknown vendor';
	}
	$map = [
		'0409' => 'Lenovo',
		'043d' => 'NEC',
		'0457' => 'Kyocera',
		'046d' => 'Logitech',
		'0489' => 'MediaTek',
		'05e3' => 'GenesysLogic',
		'0b05' => 'ASUS',
		'0bda' => 'Realtek',
		'10ec' => 'Realtek',
		'1002' => 'Advanced Micro Devices',
		'1022' => 'Advanced Micro Devices',
		'103c' => 'HP',
		'1043' => 'ASUSTeK',
		'10de' => 'NVIDIA',
		'11ac' => 'Apple',
		'13b1' => 'Cisco',
		'14c3' => 'MediaTek',
		'14e4' => 'Broadcom',
		'155d' => 'Gigabyte',
		'15ad' => 'VMware',
		'17aa' => 'Lenovo',
		'1912' => 'Red Hat',
		'1a0b' => 'Cable Matters',
		'1af4' => 'Red Hat',
		'1b21' => 'Qualcomm',
		'1b36' => 'Microsoft',
		'1d0d' => 'Dell',
		'8086' => 'Intel',
		'8087' => 'Intel',
	];
	return isset($map[$vendor]) ? $map[$vendor] : 'Vendor 0x' . $vendor;
}

// Build the Devices tab tree (Device Manager-style categories) from the
// raw enumeration output. $pcitext is one line per PCI device:
// address|class|vendor|device|driver (driver may be empty); $ubstext is
// one line per USB device: busid|vid|pid|manufacturer|product (the last
// two may be empty). Lines that do not match are skipped. Returns an
// ordered list: category name => list of ['label' => ..., 'detail' => ...].
// Fixed categories come first in a logical order, the remaining PCI
// categories follow alphabetically, and "Other devices" is last.
//
function luminum_devices_build($pcitext, $ubstext, $cpumodel, $cpucores) {
	$tree = [];
	$add = function ($cat, $label, $detail) use (&$tree) {
		if (!isset($tree[$cat])) {
			$tree[$cat] = [];
		}
		$tree[$cat][] = ['label' => $label, 'detail' => $detail];
	};

	if (is_string($cpumodel) && trim($cpumodel) !== '') {
		$label = trim($cpumodel);
		$cores = is_numeric($cpucores) ? (int)$cpucores : 0;
		if ($cores > 0) {
			$label .= " ($cores " . ($cores === 1 ? 'core' : 'cores') . ")";
		}
		$add('Processors', $label, '');
	}

	foreach (preg_split('/\r\n|\n|\r/', (string)$pcitext) as $line) {
		$parts = explode('|', trim($line));
		if (count($parts) < 4) {
			continue;
		}
		list($addr, $class, $vendor, $device) = $parts;
		$driver = isset($parts[4]) ? trim($parts[4]) : '';
		if (!preg_match('/^[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{1,2}\.[0-9a-f]$/', $addr)) {
			continue;
		}
		$label = luminum_pci_vendor_name($vendor) . ' 0x' . preg_replace('/^0x/i', '', trim($vendor)) . ':0x' . preg_replace('/^0x/i', '', trim($device));
		$detail = $addr . ($driver !== '' ? ' - driver: ' . $driver : '');
		$add(luminum_pci_class_category($class), $label, $detail);
	}

	foreach (preg_split('/\r\n|\n|\r/', (string)$ubstext) as $line) {
		$parts = explode('|', trim($line));
		if (count($parts) < 4) {
			continue;
		}
		list($busid, $vid, $pid, $mfr, $prod) = array_pad($parts, 5, '');
		$mfr = trim($mfr);
		$prod = trim($prod);
		if ($mfr !== '' && $prod !== '') {
			$label = $mfr . ' ' . $prod;
		} else if ($prod !== '') {
			$label = $prod;
		} else {
			$label = 'USB device 0x' . $vid . ':0x' . $pid;
		}
		$add('USB devices', $label, '0x' . $vid . ':0x' . $pid . ' - bus ' . $busid);
	}

	$fixed = ['Processors', 'Display adapters', 'Network adapters', 'Sound controllers', 'USB controllers', 'USB devices', 'Storage controllers', 'System devices'];
	$ordered = [];
	foreach ($fixed as $cat) {
		if (isset($tree[$cat])) {
			$ordered[$cat] = $tree[$cat];
			unset($tree[$cat]);
		}
	}
	ksort($tree);
	foreach ($tree as $cat => $devs) {
		if ($cat === 'Other devices') {
			continue;
		}
		$ordered[$cat] = $devs;
		unset($tree[$cat]);
	}
	if (isset($tree['Other devices'])) {
		$ordered['Other devices'] = $tree['Other devices'];
	}
	return $ordered;
}
