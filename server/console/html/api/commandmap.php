<?php
//
// Pure validation/mapping helpers for the command enqueue API
// (api/commands.php). Kept separate from the endpoint so they can be
// unit-tested without a DB connection or session.
//

// A command target is a numeric client ID (the COMMANDS.TARGET forms are
// a UID, "all", "os/{os}", and "grp/{name}"; the console producer
// currently enqueues per-UID commands only). Returns the normalized UID
// or null when the value is not a valid client ID.
function luminum_validate_target($target) {
	if (!is_string($target)) { return null; }
	if (!preg_match('/^[0-9]{1,10}$/', $target)) { return null; }
	return $target;
}

// A setgroups payload is an array of group names, each matching the
// ACL-safe charset Luminum::MQTT::gen_acl enforces. Returns a
// deduplicated, order-preserving list (an empty list is valid: it
// removes the client from all groups), or null when malformed.
function luminum_validate_groups($groups) {
	if (!is_array($groups)) { return null; }
	$out = [];
	foreach ($groups as $g) {
		if (!is_string($g) || !preg_match('/^[A-Za-z0-9_.\-]+$/', $g)) { return null; }
		if (strlen($g) > 64) { return null; }
		if (!in_array($g, $out, true)) { $out[] = $g; }
	}
	return $out;
}

// The DATA column payload for a setgroups command: the full replacement
// group list, as the client applies it.
function luminum_command_data($groups) {
	return json_encode(['groups' => array_values($groups)]);
}

// The CONTENT.SENSORS (type, script) column pair for a client platform
// value (STATUS.OSPLATFORM, case-insensitive). Returns null for platforms
// no sensor script can target.
function luminum_os_script_cols($os) {
	if (!is_string($os)) { return null; }
	switch (strtolower($os)) {
		case 'linux':   return ['LSTYPE', 'LSCRIPT'];
		case 'macos':   return ['MSTYPE', 'MSCRIPT'];
		case 'windows': return ['WSTYPE', 'WSCRIPT'];
	}
	return null;
}

// A query sensor list: a non-empty array (at most 25 entries) of
// {sid, params?} where sid is a positive integer sensor ID and params is
// an object of string values with [A-Za-z0-9_] names (the client injects
// them at ${name} points in the sensor script - protocol 7.3). Returns
// the normalized list (sid as int, params as an array, empty when absent)
// or null when malformed. Duplicate sids are rejected.
function luminum_validate_query_sensors($sensors) {
	if (!is_array($sensors) || count($sensors) === 0 || count($sensors) > 25) { return null; }
	$out = [];
	foreach ($sensors as $s) {
		if (!is_array($s)) { return null; }
		$sid = $s['sid'] ?? null;
		if (!is_int($sid) || $sid < 1) { return null; }
		if (in_array($sid, array_column($out, 'sid'), true)) { return null; }
		$params = [];
		if (isset($s['params']) && $s['params'] !== null) {
			if (!is_array($s['params'])) { return null; }
			foreach ($s['params'] as $k => $v) {
				if (!is_string($k) || !preg_match('/^[A-Za-z0-9_]{1,64}$/', $k)) { return null; }
				if (!is_string($v) || strlen($v) > 1024) { return null; }
				$params[$k] = $v;
			}
		}
		$out[] = ['sid' => $sid, 'params' => $params];
	}
	return $out;
}

// The DATA column payload for a query command (protocol 6.1). $sensors is
// the normalized list from luminum_validate_query_sensors; "params" is
// omitted for entries with none. $qid doubles as the outbox QID and the
// envelope id, so the answer's data.qid correlates it (7.3).
function luminum_query_command_data($qid, $sensors) {
	$list = [];
	foreach ($sensors as $s) {
		$entry = ['sid' => $s['sid']];
		if ($s['params'] !== []) { $entry['params'] = $s['params']; }
		$list[] = $entry;
	}
	return json_encode(['qid' => $qid, 'sensors' => $list]);
}

// The DATA column payload for the core/config command that delivers sensor
// definitions to a client (protocol 6.1, 7.3): the full per-OS script set
// for each sensor, as stored in CONTENT.SENSORS.
function luminum_sensor_config_data($defs) {
	return json_encode(['sensors' => $defs]);
}

// A UUID v4 for the outbox QID (the envelope message id, which the client
// deduplicates redelivered commands by - protocol 9.2).
function luminum_uuid4() {
	$bytes = random_bytes(16);
	$bytes[6] = chr((ord($bytes[6]) & 0x0f) | 0x40);
	$bytes[8] = chr((ord($bytes[8]) & 0x3f) | 0x80);
	return vsprintf('%s%s-%s-%s-%s-%s%s%s', str_split(bin2hex($bytes), 4));
}
