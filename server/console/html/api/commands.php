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

// Server ID for the outbox rows (the same value the broker signs/addresses
// commands with).
$result = api_query($db, "select CVAL from CONFIG where CKEY = 'SID'");
$sid = mysqli_fetch_assoc($result)['CVAL'] ?? '';
if (!is_string($sid) || $sid === '') {
	json_error('Server ID is not configured', 500);
}
$eg_sid = mysqli_real_escape_string($db, $sid);

if ($action === 'setgroups') {
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
$cols = luminum_os_script_cols($client['OSPLATFORM']);
if ($cols === null) {
	json_error('Unsupported client platform: ' . $client['OSPLATFORM'], 400);
}
list($type_col, $script_col) = $cols;

// Resolve each sensor: it must exist and carry a script for the target
// client's platform; parameter values are merged with the sensor's defaults
// (SENSORPARAMS) so the client receives the final values to inject.
$defs = [];
$qsensors = [];
foreach ($sensors as $s) {
	$sid2 = $s['sid'];
	$result = api_query($db, "select ID,NAME,LSTYPE,LSCRIPT,MSTYPE,MSCRIPT,WSTYPE,WSCRIPT,WITHPARAMS from SENSORS where ID = '$sid2'", 'CONTENT');
	$sensor = mysqli_fetch_assoc($result);
	if ($sensor === null) {
		json_error("No such sensor: $sid2", 404);
	}
	if (!is_string($sensor[$type_col]) || $sensor[$type_col] === '' || !is_string($sensor[$script_col]) || $sensor[$script_col] === '') {
		json_error("Sensor $sid2 has no script for " . $client['OSPLATFORM'], 400);
	}
	$params = $s['params'];
	if (intval($sensor['WITHPARAMS']) === 0) {
		if ($params !== []) {
			json_error("Sensor $sid2 does not accept parameters", 400);
		}
		$params = [];
	} else {
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
		$merged = [];
		foreach ($known as $k => $default) {
			if (array_key_exists($k, $params)) { $merged[$k] = $params[$k]; }
			elseif ($default !== null) { $merged[$k] = $default; }
		}
		$params = $merged;
	}
	$defs[] = [
		'sid' => $sid2,
		'name' => $sensor['NAME'],
		'lstype' => $sensor['LSTYPE'],
		'lscript' => $sensor['LSCRIPT'],
		'mstype' => $sensor['MSTYPE'],
		'mscript' => $sensor['MSCRIPT'],
		'wstype' => $sensor['WSTYPE'],
		'wscript' => $sensor['WSCRIPT'],
	];
	$qsensors[] = ['sid' => $sid2, 'params' => $params];
}

// The definitions row is inserted first: the worker publishes in ID order,
// so the client has the scripts before it is asked to run them.
$qid = luminum_uuid4();
$cfgqid = luminum_uuid4();
$eg_cfgdata = mysqli_real_escape_string($db, luminum_sensor_config_data($defs));
$eg_qdata = mysqli_real_escape_string($db, luminum_query_command_data($qid, $qsensors));
$cfgid = null;
$qryid = null;
mysqli_begin_transaction($db);
try {
	api_query($db, "insert into COMMANDS (SID,TARGET,LUMY,ACTION,DATA,QID,STATUS,CREATED) values ('$eg_sid','$uid','core','config','$eg_cfgdata','$cfgqid','PENDING',now())", 'CLIENTS');
	$cfgid = (int)mysqli_insert_id($db);
	api_query($db, "insert into COMMANDS (SID,TARGET,LUMY,ACTION,DATA,QID,STATUS,CREATED) values ('$eg_sid','$uid','core','query','$eg_qdata','$qid','PENDING',now())", 'CLIENTS');
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
	'target' => $uid,
	'action' => 'query',
	'qid' => $qid,
	'sensors' => array_column($qsensors, 'sid'),
]);
