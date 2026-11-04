<?php
//
// Shared bootstrap for the console JSON API. Sets up the session, the JSON
// response headers, the auth gate, and the DB connection. Every endpoint
// requires this file first.
//
require_once __DIR__ . '/../layout/db.php';

session_start();
date_default_timezone_set("America/New_York");

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');

function json_out($data) {
	echo json_encode($data);
	exit;
}

function json_error($message, $code = 500) {
	http_response_code($code);
	echo json_encode(['error' => $message]);
	exit;
}

// Auth gate: require a console session that still exists server-side.
if (!isset($_SESSION['SID']) || !ctype_alnum($_SESSION['SID'])) {
	json_error('Unauthorized', 401);
}

try {
	$db = luminum_db();
} catch (mysqli_sql_exception $e) {
	json_error('Database connection failed', 500);
}

mysqli_select_db($db, 'AUTH') or json_error('Unable to access database.', 500);
$sid = mysqli_real_escape_string($db, $_SESSION['SID']);
$check = mysqli_query($db, "select 1 from SESSION where SID = '$sid'");
if (!$check || mysqli_num_rows($check) === 0) {
	json_error('Session expired', 401);
}

// Run a query on the given database; returns the result or json_errors.
function api_query($db, $sql, $dbname = null) {
	if ($dbname !== null) {
		if (!mysqli_select_db($db, $dbname)) {
			json_error('Unable to access database.', 500);
		}
	}
	$result = mysqli_query($db, $sql);
	if ($result === false) {
		json_error('Query failed: ' . mysqli_error($db), 500);
	}
	return $result;
}
