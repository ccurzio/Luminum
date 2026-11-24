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

// CSRF gate: the inactivity client (layout/session.js) sends the session's
// token in the X-CSRF-Token header; a request without it is a forged
// cross-site submission and must not be able to extend the deadline.
if (!luminum_csrf_valid()) {
	json_error('Invalid or missing CSRF token', 403);
}

$expires = luminum_session_touch($db);
if ($expires === null) {
	json_error('Session expired', 401);
}
json_out(['ok' => true, 'expires' => $expires, 'now' => time()]);
