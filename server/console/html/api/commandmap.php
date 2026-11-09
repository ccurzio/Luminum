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

// A UUID v4 for the outbox QID (the envelope message id, which the client
// deduplicates redelivered commands by - protocol 9.2).
function luminum_uuid4() {
	$bytes = random_bytes(16);
	$bytes[6] = chr((ord($bytes[6]) & 0x0f) | 0x40);
	$bytes[8] = chr((ord($bytes[8]) & 0x3f) | 0x80);
	return vsprintf('%s%s-%s-%s-%s-%s%s%s', str_split(bin2hex($bytes), 4));
}
