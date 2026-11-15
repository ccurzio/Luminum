<?php
//
// Session extend endpoint. Refreshes the caller's inactivity deadline
// (AUTH.SESSION.EXPIRES) to now() + UTIMEOUT and returns the new deadline as
// a Unix timestamp. Invoked by the console's inactivity client
// (layout/session.js) when the user is active and by the "Extend" button on
// the timeout warning. Background polling endpoints deliberately do not call
// this, so an idle page cannot hold a session alive.
//
require_once __DIR__ . '/_init.php';
require_once __DIR__ . '/../layout/session.php';

$expires = luminum_session_touch($db);
if ($expires === null) {
	json_error('Session expired', 401);
}
json_out(['ok' => true, 'expires' => $expires, 'now' => time()]);
