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
