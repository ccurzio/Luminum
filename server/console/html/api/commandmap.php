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

// The DATA column payload for a query command (protocol 6.1, 7.3).
// $sensors is the normalized list from luminum_validate_query_sensors;
// "params" is omitted for entries with none. $conditions is the resolved
// condition tree (null when the query has none - the field is then omitted).
// $qid doubles as the outbox QID and the envelope id, so the answer's
// data.qid correlates it (7.3).
function luminum_query_command_data($qid, $sensors, $conditions = null) {
	$list = [];
	foreach ($sensors as $s) {
		$entry = ['sid' => $s['sid']];
		if ($s['params'] !== []) { $entry['params'] = $s['params']; }
		$list[] = $entry;
	}
	$data = ['qid' => $qid, 'sensors' => $list];
	if ($conditions !== null) { $data['conditions'] = $conditions; }
	return json_encode($data);
}

// The comparison operators a query condition leaf may use (protocol 7.3).
function luminum_query_ops() {
	return ['==', '!=', '=~', '!~', '>', '>=', '<', '<='];
}

// A query condition tree (protocol 7.3): a leaf is {sid, op, value, params?}
// (sid a positive int, op one of luminum_query_ops(), value a string of at
// most 1024 chars, params an object of string values like a sensor's); an
// internal node is {logic, left, right} with logic AND/OR and both children
// valid nodes. At most 25 leaves, depth at most 8. Returns the normalized
// tree (sid as int, params as an array, omitted when empty) or null when
// malformed.
function luminum_validate_query_conditions($node, $depth = 0, &$leaves = 0) {
	if (!is_array($node)) { return null; }
	if ($depth > 8) { return null; }
	if (array_key_exists('logic', $node) || array_key_exists('left', $node) || array_key_exists('right', $node)) {
		if (!in_array($node['logic'] ?? null, ['AND', 'OR'], true)) { return null; }
		if (!array_key_exists('left', $node) || !array_key_exists('right', $node)) { return null; }
		$left = luminum_validate_query_conditions($node['left'], $depth + 1, $leaves);
		if ($left === null) { return null; }
		$right = luminum_validate_query_conditions($node['right'], $depth + 1, $leaves);
		if ($right === null) { return null; }
		return ['logic' => $node['logic'], 'left' => $left, 'right' => $right];
	}
	$sid = $node['sid'] ?? null;
	if (!is_int($sid) || $sid < 1) { return null; }
	if (!in_array($node['op'] ?? null, luminum_query_ops(), true)) { return null; }
	$value = $node['value'] ?? null;
	if (!is_string($value) || strlen($value) > 1024) { return null; }
	$params = [];
	if (isset($node['params']) && $node['params'] !== null) {
		if (!is_array($node['params'])) { return null; }
		foreach ($node['params'] as $k => $v) {
			if (!is_string($k) || !preg_match('/^[A-Za-z0-9_]{1,64}$/', $k)) { return null; }
			if (!is_string($v) || strlen($v) > 1024) { return null; }
			$params[$k] = $v;
		}
	}
	$leaves++;
	if ($leaves > 25) { return null; }
	$out = ['sid' => $sid, 'op' => $node['op'], 'value' => $value];
	if ($params !== []) { $out['params'] = $params; }
	return $out;
}

// The unique sensor IDs referenced by a (validated) condition tree, in
// first-occurrence order - the config command must carry their definitions
// alongside the retrieve sensors' (protocol 7.3).
function luminum_query_condition_sids($tree) {
	$out = [];
	$walk = function ($node) use (&$walk, &$out) {
		if (isset($node['logic'])) {
			$walk($node['left']);
			$walk($node['right']);
			return;
		}
		if (!in_array($node['sid'], $out, true)) { $out[] = $node['sid']; }
	};
	$walk($tree);
	return $out;
}

// The unique sensor IDs a validated query payload references - the retrieve
// sensors plus the condition tree's leaves, deduplicated in
// first-occurrence order. $sensors is the normalized list from
// luminum_validate_query_sensors; $condtree the normalized tree (or null).
function luminum_query_sensor_ids($sensors, $condtree) {
	$out = [];
	foreach (array_column($sensors, 'sid') as $id) {
		if (!in_array($id, $out, true)) { $out[] = $id; }
	}
	if ($condtree !== null) {
		foreach (luminum_query_condition_sids($condtree) as $id) {
			if (!in_array($id, $out, true)) { $out[] = $id; }
		}
	}
	return $out;
}

// Of the sensor IDs a query references, the ones with no SENSORS row - in
// first-occurrence order. $existing is the set of IDs that do exist (ints).
// An empty result means every referenced sensor exists.
function luminum_missing_sensor_ids($sensors, $condtree, $existing) {
	$missing = [];
	foreach (luminum_query_sensor_ids($sensors, $condtree) as $id) {
		if (!in_array($id, $existing, true)) { $missing[] = $id; }
	}
	return $missing;
}

// Whether a SENSORS row carries a usable script: for the given (type, script)
// column pair (a specific platform), or for any platform when $cols is null
// (a broadcast query - at least one platform must be able to run it).
function luminum_sensor_has_script($sensor, $cols = null) {
	if (!is_array($sensor)) { return false; }
	if ($cols !== null) {
		list($t, $s) = $cols;
		return is_string($sensor[$t] ?? null) && $sensor[$t] !== ''
			&& is_string($sensor[$s] ?? null) && $sensor[$s] !== '';
	}
	return luminum_sensor_has_script($sensor, ['LSTYPE', 'LSCRIPT'])
		|| luminum_sensor_has_script($sensor, ['MSTYPE', 'MSCRIPT'])
		|| luminum_sensor_has_script($sensor, ['WSTYPE', 'WSCRIPT']);
}

// Merge user-provided params with a sensor's declared defaults (the
// SENSORPARAMS rows as a field => default|null map): provided values win, a
// null default contributes nothing, and the result is ordered by the
// declared fields. Unknown fields are the caller's job to reject.
function luminum_merge_sensor_params($known, $params) {
	$merged = [];
	foreach ($known as $k => $default) {
		if (array_key_exists($k, $params)) { $merged[$k] = $params[$k]; }
		elseif ($default !== null) { $merged[$k] = $default; }
	}
	return $merged;
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
