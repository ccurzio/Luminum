<?php
//
// Pure validation/mapping helpers for the Server Options form
// (system/serveropts.php). Kept separate from the page so they can be
// unit-tested without a DB connection or session
// (tests/console_serveropts_test.php).
//
// The rules mirror server/luminum-config.pl (the command-line equivalent of
// this page): the same SYSTEM.CONFIG keys, the same valid values, and the
// same canonical stored form. Choice settings are matched case-insensitively
// and stored canonically.
//

// Case-insensitive enum check: returns the canonical value from $values, or
// null when $value is not one of them.
function luminum_serveropts_enum($value, array $values) {
	if (!is_string($value)) { return null; }
	$map = [];
	foreach ($values as $v) { $map[strtolower($v)] = $v; }
	return $map[strtolower($value)] ?? null;
}

// Whole number of $min or more (and $max or less when given): returns the
// int, or null.
function luminum_serveropts_int($value, $min, $max = null) {
	if (!is_string($value) || !preg_match('/^[0-9]+$/', $value)) { return null; }
	$n = (int)$value;
	if ($n < $min) { return null; }
	if ($max !== null && $n > $max) { return null; }
	return $n;
}

// Validate the Server Options POST (the form in system/serveropts.php).
// Returns ['ok' => true, 'email' => <admin email>, 'config' => [CKEY => CVAL, ...]]
// on success, or ['ok' => false, 'err' => [<form field ids>...]] on failure
// (every invalid field is reported, not just the first).
//
// The normalized config array carries the exact SYSTEM.CONFIG values:
//   TARGETCONF, TCONFTHRESHOLD (only while confirmation is enabled - the
//   field is disabled and not submitted otherwise, so the stored value is
//   left untouched), ENDPOINTCOMM, CHECKININT, MISSINGAFTER, DEFSENSORSET,
//   DEFPKGSET, SENREVS (0 disables history), PKGREVS, MINPASS, COMPLEXPASS,
//   PCUPPERLOWER, PCLETNUM, PCSPECIAL, PASSKEYS, 2FA, UTIMEOUT, UTIMEOUTWARN.
//
// Database-backed checks (the default content sets exist and are unlocked)
// are the caller's job - they need a connection.
function luminum_validate_serveropts($post) {
	$errs = [];
	$config = [];
	$email = null;

	// --- General -------------------------------------------------------------
	// The email is rendered into an HTML attribute on the page and handed to
	// mail tooling, so it is restricted to the safe unquoted-atom character
	// set (no quotes, angle brackets, or ampersands to break out of markup).
	$adminemail = is_string($post['adminemail'] ?? null) ? trim($post['adminemail']) : '';
	if ($adminemail === '' || strlen($adminemail) > 128 || !preg_match('/^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/', $adminemail)) {
		$errs[] = 'adminemail';
	} else {
		$email = $adminemail;
	}

	$targetconf = luminum_serveropts_enum($post['minactconf'] ?? null, ['Enabled', 'Disabled']);
	if ($targetconf === null) {
		$errs[] = 'minactconf';
	} else {
		$config['TARGETCONF'] = $targetconf;
		if ($targetconf === 'Enabled') {
			// Upper bound mirrors the form field's maxlength (5 digits).
			$threshold = luminum_serveropts_int($post['actconfclients'] ?? null, 1, 99999);
			if ($threshold === null) { $errs[] = 'actconfclients'; }
			else { $config['TCONFTHRESHOLD'] = (string)$threshold; }
		}
	}

	// --- Endpoints -----------------------------------------------------------
	$comm = luminum_serveropts_enum($post['commproto'] ?? null, ['mqtt', 'direct', 'hybrid']);
	if ($comm === null) { $errs[] = 'commproto'; }
	else { $config['ENDPOINTCOMM'] = $comm; }

	// Upper bounds mirror the form fields' maxlength (2 digits).
	$checkinint = luminum_serveropts_int($post['checkinint'] ?? null, 1, 99);
	if ($checkinint === null) { $errs[] = 'checkinint'; }
	else { $config['CHECKININT'] = (string)$checkinint; }

	$missingafter = luminum_serveropts_int($post['missingafter'] ?? null, 1, 99);
	if ($missingafter === null) { $errs[] = 'missingafter'; }
	else { $config['MISSINGAFTER'] = (string)$missingafter; }

	// --- Content -------------------------------------------------------------
	$sensorset = luminum_serveropts_int($post['sensorset'] ?? null, 1);
	if ($sensorset === null) { $errs[] = 'sensorset'; }
	else { $config['DEFSENSORSET'] = (string)$sensorset; }

	$packageset = luminum_serveropts_int($post['packageset'] ?? null, 1);
	if ($packageset === null) { $errs[] = 'packageset'; }
	else { $config['DEFPKGSET'] = (string)$packageset; }

	$senhist = luminum_serveropts_enum($post['sensorhist'] ?? null, ['Enabled', 'Disabled']);
	if ($senhist === null) {
		$errs[] = 'sensorhist';
	} elseif ($senhist === 'Disabled') {
		$config['SENREVS'] = '0';
	} else {
		$srev = luminum_serveropts_int($post['srevcnt'] ?? null, 1, 99);
		if ($srev === null) { $errs[] = 'srevcnt'; }
		else { $config['SENREVS'] = (string)$srev; }
	}

	$pkghist = luminum_serveropts_enum($post['packagehist'] ?? null, ['Enabled', 'Disabled']);
	if ($pkghist === null) {
		$errs[] = 'packagehist';
	} elseif ($pkghist === 'Disabled') {
		$config['PKGREVS'] = '0';
	} else {
		$prev = luminum_serveropts_int($post['prevcnt'] ?? null, 1, 99);
		if ($prev === null) { $errs[] = 'prevcnt'; }
		else { $config['PKGREVS'] = (string)$prev; }
	}

	// --- Accounts ------------------------------------------------------------
	$minpass = luminum_serveropts_int($post['passlen'] ?? null, 8, 99);
	if ($minpass === null) { $errs[] = 'passlen'; }
	else { $config['MINPASS'] = (string)$minpass; }

	$complex = luminum_serveropts_enum($post['complexpass'] ?? null, ['Enabled', 'Disabled']);
	if ($complex === null) {
		$errs[] = 'complexpass';
	} elseif ($complex === 'Enabled') {
		$config['COMPLEXPASS'] = 'Enabled';
		$config['PCUPPERLOWER'] = isset($post['pwdcase']) ? 'Enabled' : 'Disabled';
		$config['PCLETNUM'] = isset($post['pwdnums']) ? 'Enabled' : 'Disabled';
		$config['PCSPECIAL'] = isset($post['pwdspec']) ? 'Enabled' : 'Disabled';
	} else {
		// The requirement checkboxes are disabled (and not submitted) while
		// complexity is off, so the sub-requirements are stored Disabled.
		$config['COMPLEXPASS'] = 'Disabled';
		$config['PCUPPERLOWER'] = 'Disabled';
		$config['PCLETNUM'] = 'Disabled';
		$config['PCSPECIAL'] = 'Disabled';
	}

	$passkeys = luminum_serveropts_enum($post['passkeys'] ?? null, ['Enabled', 'Disabled']);
	if ($passkeys === null) { $errs[] = 'passkeys'; }
	else { $config['PASSKEYS'] = $passkeys; }

	$twofa = luminum_serveropts_enum($post['2fa'] ?? null, ['Required', 'Optional', 'Disabled']);
	if ($twofa === null) { $errs[] = '2fa'; }
	else { $config['2FA'] = $twofa; }

	$inactive = luminum_serveropts_int($post['inactiveint'] ?? null, 1, 99);
	if ($inactive === null) { $errs[] = 'inactiveint'; }
	$inttype = luminum_serveropts_enum($post['inttype'] ?? null, ['min', 'hour']);
	if ($inttype === null) { $errs[] = 'inttype'; }
	if ($inactive !== null && $inttype !== null) {
		$config['UTIMEOUT'] = $inactive . ($inttype === 'min' ? 'M' : 'H');
	}

	$warn = luminum_serveropts_enum($post['2minwarn'] ?? null, ['Enabled', 'Disabled']);
	if ($warn === null) { $errs[] = '2minwarn'; }
	else { $config['UTIMEOUTWARN'] = $warn; }

	if ($errs) { return ['ok' => false, 'err' => $errs]; }
	return ['ok' => true, 'email' => $email, 'config' => $config];
}
