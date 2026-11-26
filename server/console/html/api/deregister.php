<?php
//
// Endpoint deregistration endpoint (protocol 6.1). POST JSON only:
//
//   { "target": "42" }
//
// Administrator-only (USERS.ROLE = 1), enforced here server-side as well
// as in the browser (the Client Status page renders the Deregister button
// only for administrators). The removal itself is performed by the
// broker's MQTT worker, not here: the web console cannot maintain the
// mosquitto password_file (owned by the mosquitto user), so this endpoint
// only queues the request - a PENDING row in CLIENTS.DEREGS - and the
// worker removes the client's MQTT secret, deletes the CLIENTS.AUTH and
// CLIENTS.STATUS rows, and reloads the broker. The endpoint is idempotent:
// a second request for a UID already queued answers ok without queueing a
// duplicate.
//
require_once __DIR__ . '/_init.php';
require_once __DIR__ . '/commandmap.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
	json_error('Method not allowed', 405);
}

// CSRF gate: the console JS sends the session's token in the X-CSRF-Token
// header (read from the page's <meta name="csrf-token"> tag); a POST
// without it is a forged cross-site submission.
if (!luminum_csrf_valid()) {
	json_error('Invalid or missing CSRF token', 403);
}

// Role gate: deregistration removes an endpoint from the server, so it is
// restricted to the Administrator role (ROLE = 1). The session row was
// validated by _init.php; this joins it to the account's current role.
$result = api_query($db, "select u.ROLE from USERS u join SESSION s on s.ID = u.ID where s.SID = '$sid' and u.ENABLED = 1");
$role = mysqli_fetch_assoc($result);
if ($role === null || (int)$role['ROLE'] !== 1) {
	json_error('Administrator role required', 403);
}

$body = json_decode(file_get_contents('php://input'), true);
if (!is_array($body)) {
	json_error('Invalid JSON body', 400);
}

$uid = luminum_validate_target($body['target'] ?? null);
if ($uid === null) {
	json_error('Invalid target: must be a numeric client ID', 400);
}

// The endpoint must still have a record. A client already removed by a
// processed deregistration has no STATUS row and is a 404. A client that is
// merely deactivated (CSTATE = 'DEACT', the client-initiated path) is
// offline and can never check in again, so it is removable: the worker's
// deletes are idempotent and finish the job the deactivation left half
// done (the AUTH and STATUS rows still present).
$result = api_query($db, "select ID from STATUS where ID = '$uid'", 'CLIENTS');
$client = mysqli_fetch_assoc($result);
if ($client === null) {
	json_error('No such client: ' . $uid, 404);
}

// Idempotent queueing: a request already in flight for this UID is not
// duplicated (the worker's removal is itself idempotent, but one row
// per request keeps the queue auditable).
$result = api_query($db, "select ID from DEREGS where UID = '$uid' and STATUS = 'PENDING'", 'CLIENTS');
if (mysqli_fetch_assoc($result) !== null) {
	json_out(['ok' => true, 'queued' => false, 'target' => $uid]);
}

api_query($db, "insert into DEREGS (UID,REQUESTED,STATUS) values ('$uid',now(),'PENDING')", 'CLIENTS');

json_out(['ok' => true, 'queued' => true, 'target' => $uid]);
