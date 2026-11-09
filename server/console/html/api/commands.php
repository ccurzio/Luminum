<?php
//
// Command enqueue endpoint: the console's producer for the COMMANDS
// outbox (protocol 4.2, 9). Inserts a PENDING row for the broker's MQTT
// worker to publish to the target topic; a matching client response
// marks it ACKED. POST JSON only:
//
//   { "target": "42", "action": "setgroups", "groups": ["web","db"] }
//
// "groups" is the client's full replacement group list (an empty array
// removes it from all groups).
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
if ($action !== 'setgroups') {
	json_error('Unknown action: ' . $action, 400);
}

// Per-UID target that exists and is not deactivated.
$uid = luminum_validate_target($body['target'] ?? null);
if ($uid === null) {
	json_error('Invalid target: must be a numeric client ID', 400);
}
$groups = luminum_validate_groups($body['groups'] ?? null);
if ($groups === null) {
	json_error('Invalid groups: must be an array of names matching [A-Za-z0-9_.-]', 400);
}

$result = api_query($db, "select ID,CSTATE from STATUS where ID = '$uid'", 'CLIENTS');
$client = mysqli_fetch_assoc($result);
if ($client === null) {
	json_error('No such client: ' . $uid, 404);
}
if ($client['CSTATE'] === 'DEACT') {
	json_error('Client ' . $uid . ' is deactivated', 400);
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

// Server ID for the outbox row (the same value the broker signs/addresses
// commands with).
$result = api_query($db, "select CVAL from CONFIG where CKEY = 'SID'");
$sid = mysqli_fetch_assoc($result)['CVAL'] ?? '';
if (!is_string($sid) || $sid === '') {
	json_error('Server ID is not configured', 500);
}

// Membership (STATUS.INGROUPS, the server-side source of truth) and the
// outbox row are one transaction on the CLIENTS database: the client is
// told about the change exactly when the server has recorded it.
$eg_sid = mysqli_real_escape_string($db, $sid);
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
