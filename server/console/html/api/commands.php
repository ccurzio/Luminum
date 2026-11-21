<?php
//
// Command enqueue endpoint: the console's producer for the COMMANDS
// outbox (protocol 4.2, 9). Inserts PENDING rows for the broker's MQTT
// worker to publish to the target topic; a matching client response
// marks them ACKED. POST JSON only:
//
//   { "target": "42", "action": "setgroups", "groups": ["web","db"] }
//
// "groups" is the client's full replacement group list (an empty array
// removes it from all groups).
//
//   { "target": "42", "action": "query",
//     "sensors": [ { "sid": 7 }, { "sid": 9, "params": { "host": "db-01" } } ] }
//
// "target" may also be "all" (broadcast; the worker's all/cmd topic). With
// an optional "conditions" tree (protocol 7.3), only endpoints on which the
// tree evaluates true answer - the tree's sensors ride the config command
// alongside the retrieve sensors':
//
//   { "target": "all", "action": "query", "sensors": [ { "sid": 7 } ],
//     "conditions": { "sid": 3, "op": "==", "value": "prod" } }
//
// A query is produced as two rows (protocol 7.3): a core/config command
// carrying the sensor definitions (scripts) for the named sensors, then the
// core/query command. Outbox order (ID ascending) plus QoS 1 and the
// client's sequential processing guarantee the definitions reach the client
// before the query. The query's QID is its envelope id and its data.qid, so
// the worker correlates the answer by data.qid and stores the per-sensor
// results in QUERYRESULTS.
//
require_once __DIR__ . '/_init.php';
require_once __DIR__ . '/commandmap.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
	json_error('Method not allowed', 405);
}

$body = json_decode(file_get_contents('php://input'), true);
if (!is_array($body)) {
	json_error('Invalid JSON body', 400);
}

$action = $body['action'] ?? '';
if ($action !== 'setgroups' && $action !== 'query') {
	json_error('Unknown action: ' . $action, 400);
}

// Server ID for the outbox rows (the same value the broker signs/addresses
// commands with).
$result = api_query($db, "select CVAL from CONFIG where CKEY = 'SID'", 'SYSTEM');
$sid = mysqli_fetch_assoc($result)['CVAL'] ?? '';
if (!is_string($sid) || $sid === '') {
	json_error('Server ID is not configured', 500);
}
$eg_sid = mysqli_real_escape_string($db, $sid);

if ($action === 'setgroups') {
	// Per-UID target that exists and is not deactivated.
	$uid = luminum_validate_target($body['target'] ?? null);
	if ($uid === null) {
		json_error('Invalid target: must be a numeric client ID', 400);
	}

	$result = api_query($db, "select ID,CSTATE,OSPLATFORM from STATUS where ID = '$uid'", 'CLIENTS');
	$client = mysqli_fetch_assoc($result);
	if ($client === null) {
		json_error('No such client: ' . $uid, 404);
	}
	if ($client['CSTATE'] === 'DEACT') {
		json_error('Client ' . $uid . ' is deactivated', 400);
	}

	// Membership change.
	$groups = luminum_validate_groups($body['groups'] ?? null);
	if ($groups === null) {
		json_error('Invalid groups: must be an array of names matching [A-Za-z0-9_.-]', 400);
	}

	// Every group must exist (membership in an unknown group would also
	// have no ACL grant, so the client could never receive it).
	foreach ($groups as $g) {
		$eg = mysqli_real_escape_string($db, $g);
		$result = api_query($db, "select ID from GROUPS where NAME = '$eg'");
		if (mysqli_fetch_assoc($result) === null) {
			json_error('No such group: ' . $g, 400);
		}
	}

	// Membership (STATUS.INGROUPS, the server-side source of truth) and the
	// outbox row are one transaction on the CLIENTS database: the client is
	// told about the change exactly when the server has recorded it.
	$eg_data = mysqli_real_escape_string($db, luminum_command_data($groups));
	$qid = luminum_uuid4();
	if (count($groups) > 0) {
		$eg_ingroups = mysqli_real_escape_string($db, implode(',', $groups));
		$update = "update STATUS set INGROUPS = '$eg_ingroups' where ID = '$uid'";
	} else {
		$update = "update STATUS set INGROUPS = null where ID = '$uid'";
	}

	mysqli_begin_transaction($db);
	try {
		api_query($db, $update, 'CLIENTS');
		api_query($db, "insert into COMMANDS (SID,TARGET,LUMY,ACTION,DATA,QID,STATUS,CREATED) values ('$eg_sid','$uid','core','setgroups','$eg_data','$qid','PENDING',now())", 'CLIENTS');
		mysqli_commit($db);
	} catch (mysqli_sql_exception $e) {
		mysqli_rollback($db);
		json_error('Query failed: ' . mysqli_error($db), 500);
	}

	json_out([
		'ok' => true,
		'command' => (int)mysqli_insert_id($db),
		'target' => $uid,
		'action' => 'setgroups',
		'groups' => $groups,
	]);
}

// Query (protocol 6.1, 7.3): two outbox rows, one transaction.
$sensors = luminum_validate_query_sensors($body['sensors'] ?? null);
if ($sensors === null) {
	json_error('Invalid sensors: must be a non-empty array of {sid, params?} with positive integer sids', 400);
}

// Optional condition tree (7.3): validated here, its sensors resolved below,
// and - with the merged params - carried in the query DATA. Endpoints on
// which the tree evaluates false never answer.
$condtree = null;
if (array_key_exists('conditions', $body) && $body['conditions'] !== null) {
	$condtree = luminum_validate_query_conditions($body['conditions']);
	if ($condtree === null) {
		json_error('Invalid conditions: must be a tree of {sid, op, value, params?} leaves and {logic, left, right} nodes', 400);
	}
}

// Target: a single client, or the broadcast "all" form (a query with
// conditions then reaches only the matching endpoints - 7.3).
$target = $body['target'] ?? null;
$client = null;
$cols = null;
if ($target !== 'all') {
	$uid = luminum_validate_target($target);
	if ($uid === null) {
		json_error('Invalid target: must be a numeric client ID or "all"', 400);
	}
	$result = api_query($db, "select ID,CSTATE,OSPLATFORM from STATUS where ID = '$uid'", 'CLIENTS');
	$client = mysqli_fetch_assoc($result);
	if ($client === null) {
		json_error('No such client: ' . $uid, 404);
	}
	if ($client['CSTATE'] === 'DEACT') {
		json_error('Client ' . $uid . ' is deactivated', 400);
	}
	$cols = luminum_os_script_cols($client['OSPLATFORM']);
	if ($cols === null) {
		json_error('Unsupported client platform: ' . $client['OSPLATFORM'], 400);
	}
}
$plat = $client !== null ? $client['OSPLATFORM'] : null;

// Every sensor the query references (retrieve sensors + condition leaves)
// must exist: a query naming a nonexistent sensor is rejected whole - every
// missing ID reported at once - before anything is resolved or enqueued.
$allids = luminum_query_sensor_ids($sensors, $condtree);
$in = implode(',', array_map('intval', $allids));
$result = api_query($db, "select ID from SENSORS where ID in ($in)", 'CONTENT');
$exist = [];
while ($erow = mysqli_fetch_assoc($result)) { $exist[] = (int)$erow['ID']; }
$missing = luminum_missing_sensor_ids($sensors, $condtree, $exist);
if (count($missing) > 0) {
	json_error('No such sensor: ' . implode(', ', $missing), 404);
}

// Resolve one sensor for the query: it must exist and carry a script (for
// the target client's platform, or for any platform on a broadcast); the
// caller's params are checked against the sensor's declared fields and
// merged with the defaults so the client receives the final values to
// inject. Returns [sensor row, merged params].
$resolve_sensor = function ($sid2, $params) use ($db, $cols, $plat) {
	$result = api_query($db, "select ID,NAME,LSTYPE,LSCRIPT,MSTYPE,MSCRIPT,WSTYPE,WSCRIPT,WITHPARAMS from SENSORS where ID = '$sid2'", 'CONTENT');
	$sensor = mysqli_fetch_assoc($result);
	if ($sensor === null) {
		json_error("No such sensor: $sid2", 404);
	}
	if (!luminum_sensor_has_script($sensor, $cols)) {
		json_error($plat === null ? "Sensor $sid2 has no script for any platform" : "Sensor $sid2 has no script for $plat", 400);
	}
	if (intval($sensor['WITHPARAMS']) === 0) {
		if ($params !== []) {
			json_error("Sensor $sid2 does not accept parameters", 400);
		}
		return [$sensor, []];
	}
	$result = api_query($db, "select FIELD,DEFAULTVAL from SENSORPARAMS where SID = '$sid2'", 'CONTENT');
	$known = [];
	while ($prow = mysqli_fetch_assoc($result)) {
		if (!is_string($prow['FIELD']) || $prow['FIELD'] === '') { continue; }
		if (array_key_exists($prow['FIELD'], $known)) { continue; }
		$known[$prow['FIELD']] = (is_string($prow['DEFAULTVAL']) && $prow['DEFAULTVAL'] !== '') ? $prow['DEFAULTVAL'] : null;
	}
	foreach ($params as $k => $v) {
		if (!array_key_exists($k, $known)) {
			json_error("Sensor $sid2 has no such parameter: $k", 400);
		}
	}
	return [$sensor, luminum_merge_sensor_params($known, $params)];
};

// The retrieve sensors, and their definitions for the config command.
$defs = [];
$defsids = [];
$qsensors = [];
foreach ($sensors as $s) {
	list($sensor, $params) = $resolve_sensor($s['sid'], $s['params']);
	$defs[] = [
		'sid' => $s['sid'],
		'name' => $sensor['NAME'],
		'lstype' => $sensor['LSTYPE'],
		'lscript' => $sensor['LSCRIPT'],
		'mstype' => $sensor['MSTYPE'],
		'mscript' => $sensor['MSCRIPT'],
		'wstype' => $sensor['WSTYPE'],
		'wscript' => $sensor['WSCRIPT'],
	];
	$defsids[] = $s['sid'];
	$qsensors[] = ['sid' => $s['sid'], 'params' => $params];
}

// The condition tree's sensors (same rules); their definitions join the
// config command (deduplicated against the retrieve sensors), and each leaf
// comes back with its merged params for the query DATA.
$resolve_cond = function ($node) use (&$resolve_cond, &$resolve_sensor, &$defs, &$defsids) {
	if (isset($node['logic'])) {
		return [
			'logic' => $node['logic'],
			'left' => $resolve_cond($node['left']),
			'right' => $resolve_cond($node['right']),
		];
	}
	list($sensor, $params) = $resolve_sensor($node['sid'], $node['params'] ?? []);
	if (!in_array($node['sid'], $defsids, true)) {
		$defs[] = [
			'sid' => $node['sid'],
			'name' => $sensor['NAME'],
			'lstype' => $sensor['LSTYPE'],
			'lscript' => $sensor['LSCRIPT'],
			'mstype' => $sensor['MSTYPE'],
			'mscript' => $sensor['MSCRIPT'],
			'wstype' => $sensor['WSTYPE'],
			'wscript' => $sensor['WSCRIPT'],
		];
		$defsids[] = $node['sid'];
	}
	$leaf = ['sid' => $node['sid'], 'op' => $node['op'], 'value' => $node['value']];
	if ($params !== []) { $leaf['params'] = $params; }
	return $leaf;
};
$finalcond = $condtree !== null ? $resolve_cond($condtree) : null;

// The definitions row is inserted first: the worker publishes in ID order,
// so the client has the scripts before it is asked to run them.
$qid = luminum_uuid4();
$cfgqid = luminum_uuid4();
$eg_cfgdata = mysqli_real_escape_string($db, luminum_sensor_config_data($defs));
$eg_qdata = mysqli_real_escape_string($db, luminum_query_command_data($qid, $qsensors, $finalcond));
$eg_target = mysqli_real_escape_string($db, $target);
$cfgid = null;
$qryid = null;
mysqli_begin_transaction($db);
try {
	api_query($db, "insert into COMMANDS (SID,TARGET,LUMY,ACTION,DATA,QID,STATUS,CREATED) values ('$eg_sid','$eg_target','core','config','$eg_cfgdata','$cfgqid','PENDING',now())", 'CLIENTS');
	$cfgid = (int)mysqli_insert_id($db);
	api_query($db, "insert into COMMANDS (SID,TARGET,LUMY,ACTION,DATA,QID,STATUS,CREATED) values ('$eg_sid','$eg_target','core','query','$eg_qdata','$qid','PENDING',now())", 'CLIENTS');
	$qryid = (int)mysqli_insert_id($db);
	mysqli_commit($db);
} catch (mysqli_sql_exception $e) {
	mysqli_rollback($db);
	json_error('Query failed: ' . mysqli_error($db), 500);
}

json_out([
	'ok' => true,
	'command' => $qryid,
	'config_command' => $cfgid,
	'target' => $target,
	'action' => 'query',
	'qid' => $qid,
	'sensors' => array_column($qsensors, 'sid'),
	'conditions' => $finalcond !== null,
]);
