<?php
//
// Shared helpers for the console inactivity session timeout.
//
// The inactivity window comes from the UTIMEOUT server option (a value like
// "15M"; see the Server Options page). Each session's deadline lives in
// AUTH.SESSION.EXPIRES:
//   - set to now() + UTIMEOUT at login (index.php)
//   - refreshed by luminum_session_touch() on real user activity: full page
//     requests (via luminum_session_gate() in layout/header.php) and the
//     explicit /api/touch.php extend call made by the console's inactivity
//     client while the user is active
//   - enforced on every request: the page gate bounces expired sessions to
//     the login page, and the API auth gate (api/_init.php) rejects them
//     with a 401
//
// Background API polling (e.g. the Client Status table refreshing every few
// seconds) deliberately never refreshes the deadline, so an idle page cannot
// hold a session alive.
//

require_once __DIR__ . '/db.php';

// Parse a UTIMEOUT value ("90S", "15M", "1H", "1D") into seconds. Returns
// null for anything malformed so callers can fall back to the default.
function luminum_parse_utimeout($value) {
	if (!is_string($value) || !preg_match('/^(\d+)([SMHD])$/', $value, $m)) { return null; }
	$n = (int)$m[1];
	if ($n <= 0) { return null; }
	$mult = ['S' => 1, 'M' => 60, 'H' => 3600, 'D' => 86400];
	return $n * $mult[$m[2]];
}

// The inactivity window in seconds, from SYSTEM.CONFIG (default 15 minutes).
function luminum_utimeout_seconds($db) {
	static $cached = null;
	if ($cached !== null) { return $cached; }
	$cached = 900;
	$q = mysqli_query($db, "select CVAL from SYSTEM.CONFIG where CKEY = 'UTIMEOUT'");
	if ($q && ($row = $q->fetch_assoc()) && ($secs = luminum_parse_utimeout($row['CVAL'])) !== null) {
		$cached = $secs;
	}
	return $cached;
}

// Refresh the caller's session deadline to now() + UTIMEOUT. Returns the new
// deadline as a Unix timestamp, or null when there is no session to refresh.
function luminum_session_touch($db) {
	if (!isset($_SESSION['SID']) || !ctype_alnum($_SESSION['SID'])) { return null; }
	$sid = mysqli_real_escape_string($db, $_SESSION['SID']);
	$secs = luminum_utimeout_seconds($db);
	mysqli_query($db, "update AUTH.SESSION set EXPIRES = now() + interval $secs second where SID = '$sid'");
	$q = mysqli_query($db, "select unix_timestamp(EXPIRES) as deadline from AUTH.SESSION where SID = '$sid'");
	$row = $q ? $q->fetch_assoc() : null;
	return ($row && $row['deadline'] !== null) ? (int)$row['deadline'] : null;
}

// Page-request gate: bounce to the login page when the deadline has passed
// (removing the server-side session row and destroying the PHP session);
// otherwise refresh the deadline, since a page load is user activity.
// Must run before any output; the login page path (no SID) is untouched.
function luminum_session_gate($db) {
	if (!isset($_SESSION['SID']) || !ctype_alnum($_SESSION['SID'])) { return; }
	$sid = mysqli_real_escape_string($db, $_SESSION['SID']);
	$check = mysqli_query($db, "select 1 from AUTH.SESSION where SID = '$sid' and EXPIRES > now()");
	if (!$check || mysqli_num_rows($check) === 0) {
		mysqli_query($db, "delete from AUTH.SESSION where SID = '$sid'");
		session_unset();
		session_destroy();
		header('Location: /index.php?err=badsession');
		exit;
	}
	luminum_session_touch($db);
}
