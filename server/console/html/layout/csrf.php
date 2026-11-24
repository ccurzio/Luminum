<?php
//
// Shared CSRF token helpers for the console.
//
// Every state-changing console request must carry the caller's per-session
// token:
//   - HTML form POSTs (login, sensor create/edit, server options, ...)
//     render it as a hidden input (luminum_csrf_field) and post it back
//   - the JSON API writes (/api/commands.php, /api/touch.php) receive it
//     in the X-CSRF-Token header, which the console JS reads from the
//     <meta name="csrf-token"> tag layout/header.php emits
//
// The token is a 64-hex random value stored in the PHP session: generated
// on first use, stable for the session's life, destroyed with it (logout
// and the expired-session gate both destroy the PHP session, so a dead
// session's token dies with it). Verification is hash_equals (timing-safe).
// A request carrying no token - or another session's token - is rejected
// by the endpoint. The login form is covered too: index.php starts the
// PHP session before rendering the login page, so the anonymous session
// carries the token, and the session is not regenerated on a successful
// login, so the same token stays valid across the sign-in.
//

// The caller's session token, generating it on first use.
function luminum_csrf_token() {
	if (!isset($_SESSION['CSRF']) || !is_string($_SESSION['CSRF']) || strlen($_SESSION['CSRF']) !== 64) {
		$_SESSION['CSRF'] = bin2hex(random_bytes(32));
	}
	return $_SESSION['CSRF'];
}

// The hidden input an HTML form posts the token back with.
function luminum_csrf_field() {
	print '<input type="hidden" name="csrf" value="' . luminum_csrf_token() . '">';
}

// True when the request carries this session's token - as the "csrf" form
// field (HTML form POST) or the X-CSRF-Token header (JSON API). The form
// field, when present, is the one checked (a POST that carries both must
// carry the token in both).
function luminum_csrf_valid() {
	$sent = null;
	if (isset($_POST['csrf']) && is_string($_POST['csrf'])) { $sent = $_POST['csrf']; }
	elseif (isset($_SERVER['HTTP_X_CSRF_TOKEN'])) { $sent = $_SERVER['HTTP_X_CSRF_TOKEN']; }
	return is_string($sent) && hash_equals(luminum_csrf_token(), $sent);
}
