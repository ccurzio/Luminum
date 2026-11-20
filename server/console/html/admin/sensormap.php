<?php
//
// Pure validation/mapping helpers for the sensor create form
// (admin/sensors.php). Kept separate from the page so they can be
// unit-tested without a DB connection or session
// (tests/console_sensor_test.php).
//

// The script types a sensor can use per platform. These must match what the
// clients actually execute: shell/perl/python on Linux and macOS, and
// powershell/vbscript/batch/python on Windows.
function luminum_sensor_os_types($os) {
	switch ($os) {
		case 'linux':   return ['shell', 'perl', 'python'];
		case 'macos':   return ['shell', 'perl', 'python'];
		case 'windows': return ['powershell', 'vbscript', 'batch', 'python'];
	}
	return [];
}

// The result types the create form offers (CONTENT.SENSORS.RTYPE).
function luminum_sensor_result_types() {
	return ['text', 'number', 'bool', 'ipaddress', 'datetime'];
}

// Split a stored TIMEOUT value ("30S"/"2M") back into the form's timeout
// number + unit select values (the validator joins them the same way).
// Returns null for anything that does not match the stored format.
function luminum_sensor_timeout_parts($timeout) {
	if (!is_string($timeout) || !preg_match('/^([1-9][0-9]{0,2})([SM])$/', $timeout, $m)) {
		return null;
	}
	return ['num' => $m[1], 'unit' => $m[2] === 'M' ? 'min' : 'sec'];
}

// Maximum sensor script size in bytes. A query delivers every sensor's full
// per-OS script set in one core/config command that must fit the 64 KiB MQTT
// payload cap, so a single script is capped at that size.
const LUMINUM_SENSOR_SCRIPT_MAX = 65536;

// Validate the create-sensor POST (the form in admin/sensors.php).
// Returns ['ok' => true, 'sensor' => <normalized fields>] on success or
// ['ok' => false, 'err' => <code>] on the first failure. The codes are:
//   name, desc, timeout, rtype, cset, category, delimiter, os
// Database-backed checks (content set exists, category belongs to the set,
// duplicate name) are the caller's job - they need a connection.
//
// The normalized sensor array carries the exact values for the SENSORS
// insert: NAME, DESCRIPTION, CSET (int), CATEGORY (int|null), TIMEOUT
// ("30S"/"2M"), MSTYPE/MSCRIPT, LSTYPE/LSCRIPT, WSTYPE/WSCRIPT (null for
// disabled platforms), RTYPE, USECASE, CSPLIT, DELIMITER (null when
// unsplit), WITHPARAMS.
function luminum_validate_sensor_create($post) {
	$name = is_string($post['pkgname'] ?? null) ? trim($post['pkgname']) : '';
	if ($name === '' || strlen($name) > 128 || !preg_match('/^[A-Za-z0-9][A-Za-z0-9 _.\-]*$/', $name)) {
		return ['ok' => false, 'err' => 'name'];
	}
	$desc = is_string($post['pkgdesc'] ?? null) ? trim($post['pkgdesc']) : '';
	if ($desc === '' || strlen($desc) > 128 || !preg_match('/^[\x20-\x7e]+$/', $desc)) {
		return ['ok' => false, 'err' => 'desc'];
	}
	$tnum = is_string($post['timeout'] ?? null) ? $post['timeout'] : '';
	$tunit = is_string($post['tint'] ?? null) ? $post['tint'] : '';
	if (!preg_match('/^[1-9][0-9]{0,2}$/', $tnum) || !in_array($tunit, ['sec', 'min'], true)) {
		return ['ok' => false, 'err' => 'timeout'];
	}
	$timeout = $tnum . ($tunit === 'min' ? 'M' : 'S');
	$rtype = is_string($post['rtype'] ?? null) ? $post['rtype'] : '';
	if (!in_array($rtype, luminum_sensor_result_types(), true)) {
		return ['ok' => false, 'err' => 'rtype'];
	}
	$cset = is_string($post['contentset'] ?? null) ? $post['contentset'] : '';
	if (!preg_match('/^[1-9][0-9]*$/', $cset)) {
		return ['ok' => false, 'err' => 'cset'];
	}
	$category = null;
	$cat = is_string($post['category'] ?? null) ? $post['category'] : '';
	if ($cat !== '' && $cat !== 'none') {
		if (!preg_match('/^[1-9][0-9]*$/', $cat)) {
			return ['ok' => false, 'err' => 'category'];
		}
		$category = (int)$cat;
	}
	$usecase = isset($post['case']) ? 1 : 0;
	$csplit = isset($post['split']) ? 1 : 0;
	$delimiter = null;
	if ($csplit === 1) {
		$delim = is_string($post['delimeter'] ?? null) ? $post['delimeter'] : '';
		if (strlen($delim) !== 1) {
			return ['ok' => false, 'err' => 'delimiter'];
		}
		$delimiter = $delim;
	}
	$withparams = isset($post['useparams']) ? 1 : 0;

	// Per-platform scripts: an enabled platform must carry a valid type and
	// a non-empty script; a disabled platform stores NULL/NULL (the list
	// page derives its platform icons from the script columns).
	$os = [
		'linux'   => ['enabled' => isset($post['leselect']), 'type' => $post['lstype'] ?? null, 'script' => $post['lscript'] ?? null],
		'macos'   => ['enabled' => isset($post['meselect']), 'type' => $post['mstype'] ?? null, 'script' => $post['mscript'] ?? null],
		'windows' => ['enabled' => isset($post['weselect']), 'type' => $post['wstype'] ?? null, 'script' => $post['wscript'] ?? null],
	];
	$cols = ['MSTYPE', 'MSCRIPT', 'LSTYPE', 'LSCRIPT', 'WSTYPE', 'WSCRIPT'];
	$values = array_fill(0, count($cols), null);
	$enabled = 0;
	foreach ($os as $plat => $spec) {
		if (!$spec['enabled']) { continue; }
		$enabled++;
		$type = is_string($spec['type']) ? $spec['type'] : '';
		if (!in_array($type, luminum_sensor_os_types($plat), true)) {
			return ['ok' => false, 'err' => 'os'];
		}
		$script = is_string($spec['script']) ? $spec['script'] : '';
		// Normalize line endings before storing: the client runs the script
		// on the interpreter's stdin, and a stray \r (a script pasted from a
		// Windows editor) breaks shell scripts - "then\r" and "fi\r" are
		// syntax errors and a bare "\r" line is "command not found".
		$script = str_replace(["\r\n", "\r"], "\n", $script);
		if (trim($script) === '' || strlen($script) > LUMINUM_SENSOR_SCRIPT_MAX) {
			return ['ok' => false, 'err' => 'os'];
		}
		$base = array_search($plat === 'linux' ? 'LSTYPE' : ($plat === 'macos' ? 'MSTYPE' : 'WSTYPE'), $cols, true);
		$values[$base] = $type;
		$values[$base + 1] = $script;
	}
	if ($enabled === 0) {
		return ['ok' => false, 'err' => 'os'];
	}

	$sensor = [
		'NAME' => $name,
		'DESCRIPTION' => $desc,
		'CSET' => (int)$cset,
		'CATEGORY' => $category,
		'TIMEOUT' => $timeout,
		'RTYPE' => $rtype,
		'USECASE' => $usecase,
		'CSPLIT' => $csplit,
		'DELIMITER' => $delimiter,
		'WITHPARAMS' => $withparams,
	];
	foreach ($cols as $i => $col) {
		$sensor[$col] = $values[$i];
	}
	return ['ok' => true, 'sensor' => $sensor];
}

// The human-readable message for a validation error code (the ?err= value
// the POST handler redirects back to the form with; shown in the overlay
// popup on the create form).
function luminum_sensor_error_message($code) {
	$msgs = [
		'name' => 'The sensor name is invalid: it must be 1-128 characters, begin with a letter or number, and contain only letters, numbers, spaces, underscores, dashes, and dots.',
		'desc' => 'The description is required and must be 1-128 characters.',
		'timeout' => 'The timeout must be a number between 1 and 999.',
		'rtype' => 'The result type is invalid.',
		'cset' => 'A valid content set is required.',
		'category' => 'The selected category does not exist in the chosen content set.',
		'delimiter' => 'The column delimiter must be exactly one character.',
		'os' => 'Enable at least one platform, and provide a valid type and a non-empty script for every enabled platform.',
		'dupname' => 'A sensor with that name already exists.',
		'save' => 'Saving the sensor failed.',
	];
	return $msgs[$code] ?? 'The sensor could not be saved.';
}
