<?php
//
// console_serveropts_test.php - offline test harness for the Server Options
// form validator in server/console/html/system/serveroptsmap.php. The
// DB-backed path (content set existence, the CONFIG upserts, the admin
// email update) is covered end to end by tests/deploy_test.sh.
//
// Usage: php tests/console_serveropts_test.php
// Exit code: 0 if all checks pass, 1 otherwise.

require_once __DIR__ . '/../server/console/html/system/serveroptsmap.php';

$failures = 0;
function ok($name, $cond, $detail = null) {
    global $failures;
    if ($cond) {
        echo "ok   - $name\n";
    } else {
        $failures++;
        echo "FAIL - $name" . ($detail !== null ? " ($detail)" : "") . "\n";
    }
}

// A fully valid POST: every field the form submits when all options are in
// their default state (plus a few non-default values to prove they pass).
function valid_post() {
    return [
        'adminemail'    => 'admin@example.com',
        'minactconf'    => 'enabled',
        'actconfclients'=> '250',
        'commproto'     => 'mqtt',
        'checkinint'    => '5',
        'missingafter'  => '90',
        'sensorset'     => '1',
        'packageset'    => '2',
        'sensorhist'    => 'Enabled',
        'srevcnt'       => '5',
        'packagehist'   => 'Enabled',
        'prevcnt'       => '5',
        'passlen'       => '8',
        'complexpass'   => 'disabled',
        'passkeys'      => 'Disabled',
        '2fa'           => 'Optional',
        'inactiveint'   => '15',
        'inttype'       => 'min',
        '2minwarn'      => 'enabled',
    ];
}

// --- helpers -----------------------------------------------------------------
ok('enum: canonical value passes', luminum_serveropts_enum('Enabled', ['Enabled', 'Disabled']) === 'Enabled');
ok('enum: case-insensitive match', luminum_serveropts_enum('eNaBlEd', ['Enabled', 'Disabled']) === 'Enabled');
ok('enum: unknown value rejected', luminum_serveropts_enum('Maybe', ['Enabled', 'Disabled']) === null);
ok('enum: non-string rejected', luminum_serveropts_enum(1, ['Enabled', 'Disabled']) === null);
ok('int: valid value', luminum_serveropts_int('250', 1) === 250);
ok('int: below minimum rejected', luminum_serveropts_int('0', 1) === null);
ok('int: non-numeric rejected', luminum_serveropts_int('abc', 1) === null);
ok('int: negative rejected', luminum_serveropts_int('-5', 1) === null);
ok('int: decimal rejected', luminum_serveropts_int('5.5', 1) === null);
ok('int: non-string rejected', luminum_serveropts_int(5, 1) === null);

// --- fully valid payload ------------------------------------------------------
$v = luminum_validate_serveropts(valid_post());
ok('valid payload: ok', $v['ok'] === true, json_encode($v));
if ($v['ok']) {
    $c = $v['config'];
    $expect = [
        'TARGETCONF'     => 'Enabled',
        'TCONFTHRESHOLD' => '250',
        'ENDPOINTCOMM'   => 'mqtt',
        'CHECKININT'     => '5',
        'MISSINGAFTER'   => '90',
        'DEFSENSORSET'   => '1',
        'DEFPKGSET'      => '2',
        'SENREVS'        => '5',
        'PKGREVS'        => '5',
        'MINPASS'        => '8',
        'COMPLEXPASS'    => 'Disabled',
        'PCUPPERLOWER'   => 'Disabled',
        'PCLETNUM'       => 'Disabled',
        'PCSPECIAL'      => 'Disabled',
        'PASSKEYS'       => 'Disabled',
        '2FA'            => 'Optional',
        'UTIMEOUT'       => '15M',
        'UTIMEOUTWARN'   => 'Enabled',
    ];
    foreach ($expect as $key => $val) {
        ok("valid payload: $key = $val", ($c[$key] ?? null) === $val, 'got ' . var_export($c[$key] ?? null, true));
    }
    ok('valid payload: no unexpected keys', count($c) === count($expect), implode(',', array_keys($c)));
    ok('valid payload: email captured', $v['email'] === 'admin@example.com');
}

// --- canonicalization ---------------------------------------------------------
$p = valid_post();
$p['minactconf'] = 'DISABLED';
$p['commproto'] = 'HYBRID';
$p['2fa'] = 'required';
$p['2minwarn'] = 'DISABLED';
$p['inttype'] = 'hour';
$p['inactiveint'] = '30';
$v = luminum_validate_serveropts($p);
ok('canonical: ok', $v['ok'] === true, json_encode($v));
if ($v['ok']) {
    ok('canonical: TARGETCONF -> Disabled', $v['config']['TARGETCONF'] === 'Disabled');
    ok('canonical: ENDPOINTCOMM -> hybrid', $v['config']['ENDPOINTCOMM'] === 'hybrid');
    ok('canonical: 2FA -> Required', $v['config']['2FA'] === 'Required');
    ok('canonical: UTIMEOUTWARN -> Disabled', $v['config']['UTIMEOUTWARN'] === 'Disabled');
    ok('canonical: UTIMEOUT 30 hour -> 30H', $v['config']['UTIMEOUT'] === '30H');
}

// --- disabled-branch semantics -------------------------------------------------
$p = valid_post();
$p['minactconf'] = 'disabled';
unset($p['actconfclients']); // the field is disabled in the form, so not submitted
$v = luminum_validate_serveropts($p);
ok('targetconf disabled: ok', $v['ok'] === true, json_encode($v));
if ($v['ok']) {
    ok('targetconf disabled: stored threshold untouched (no TCONFTHRESHOLD)', !array_key_exists('TCONFTHRESHOLD', $v['config']));
}

$p = valid_post();
$p['sensorhist'] = 'Disabled';
unset($p['srevcnt']);
$p['packagehist'] = 'Disabled';
unset($p['prevcnt']);
$v = luminum_validate_serveropts($p);
ok('history disabled: ok', $v['ok'] === true, json_encode($v));
if ($v['ok']) {
    ok('history disabled: SENREVS -> 0', $v['config']['SENREVS'] === '0');
    ok('history disabled: PKGREVS -> 0', $v['config']['PKGREVS'] === '0');
}

$p = valid_post();
$p['complexpass'] = 'enabled';
$p['pwdcase'] = 'on';
$p['pwdspec'] = 'on'; // pwdnums left off
$v = luminum_validate_serveropts($p);
ok('complexity enabled: ok', $v['ok'] === true, json_encode($v));
if ($v['ok']) {
    ok('complexity enabled: COMPLEXPASS -> Enabled', $v['config']['COMPLEXPASS'] === 'Enabled');
    ok('complexity enabled: checked pwdcase -> Enabled', $v['config']['PCUPPERLOWER'] === 'Enabled');
    ok('complexity enabled: unchecked pwdnums -> Disabled', $v['config']['PCLETNUM'] === 'Disabled');
    ok('complexity enabled: checked pwdspec -> Enabled', $v['config']['PCSPECIAL'] === 'Enabled');
}

$p = valid_post();
$p['complexpass'] = 'disabled';
$p['pwdcase'] = 'on'; // stale checkbox in the payload; complexity is off
$v = luminum_validate_serveropts($p);
ok('complexity disabled: ok', $v['ok'] === true, json_encode($v));
if ($v['ok']) {
    ok('complexity disabled: sub-requirements stored Disabled', $v['config']['PCUPPERLOWER'] === 'Disabled' && $v['config']['PCLETNUM'] === 'Disabled' && $v['config']['PCSPECIAL'] === 'Disabled');
}

// --- invalid fields -------------------------------------------------------------
function expect_err($name, $mutate, $field) {
    $p = valid_post();
    $mutate($p);
    $v = luminum_validate_serveropts($p);
    $has = $v['ok'] === false && in_array($field, $v['err'], true);
    ok($name, $has, json_encode($v));
}

expect_err('email: missing', function (&$p) { unset($p['adminemail']); }, 'adminemail');
expect_err('email: no @', function (&$p) { $p['adminemail'] = 'admin.example.com'; }, 'adminemail');
expect_err('email: no domain', function (&$p) { $p['adminemail'] = 'admin@'; }, 'adminemail');
expect_err('email: space', function (&$p) { $p['adminemail'] = 'admin @example.com'; }, 'adminemail');
expect_err('email: over 128 chars', function (&$p) { $p['adminemail'] = str_repeat('a', 120) . '@example.com'; }, 'adminemail');
// The email is rendered into an HTML attribute on the page, so markup-
// breaking characters must be rejected, not just escaped.
expect_err('email: double quote (attribute breakout)', function (&$p) { $p['adminemail'] = 'a"onfocus=alert(1)@x.com'; }, 'adminemail');
expect_err('email: single quote', function (&$p) { $p['adminemail'] = "a'onfocus=alert(1)@x.com"; }, 'adminemail');
expect_err('email: angle brackets', function (&$p) { $p['adminemail'] = 'a<b>@x.com'; }, 'adminemail');
expect_err('email: ampersand', function (&$p) { $p['adminemail'] = 'a&b@x.com'; }, 'adminemail');
expect_err('email: backtick', function (&$p) { $p['adminemail'] = 'a`b@x.com'; }, 'adminemail');
expect_err('email: non-ASCII', function (&$p) { $p['adminemail'] = 'admïn@example.com'; }, 'adminemail');
expect_err('email: single-letter TLD', function (&$p) { $p['adminemail'] = 'admin@example.c'; }, 'adminemail');
// The safe character set still accepts ordinary addresses.
$p = valid_post();
$p['adminemail'] = 'first.last+tag@sub.domain-name.co.uk';
$v = luminum_validate_serveropts($p);
ok('email: dots, plus, hyphen, multi-label domain accepted', $v['ok'] === true && $v['email'] === 'first.last+tag@sub.domain-name.co.uk', json_encode($v));
expect_err('minactconf: unknown value', function (&$p) { $p['minactconf'] = 'sometimes'; }, 'minactconf');
expect_err('threshold: zero', function (&$p) { $p['actconfclients'] = '0'; }, 'actconfclients');
expect_err('threshold: non-numeric', function (&$p) { $p['actconfclients'] = 'abc'; }, 'actconfclients');
expect_err('threshold: missing while enabled', function (&$p) { unset($p['actconfclients']); }, 'actconfclients');
expect_err('threshold: over 5 digits', function (&$p) { $p['actconfclients'] = '100000'; }, 'actconfclients');
expect_err('commproto: unknown value', function (&$p) { $p['commproto'] = 'carrier-pigeon'; }, 'commproto');
expect_err('checkinint: zero', function (&$p) { $p['checkinint'] = '0'; }, 'checkinint');
expect_err('checkinint: empty', function (&$p) { $p['checkinint'] = ''; }, 'checkinint');
expect_err('checkinint: over 2 digits', function (&$p) { $p['checkinint'] = '100'; }, 'checkinint');
expect_err('missingafter: zero', function (&$p) { $p['missingafter'] = '0'; }, 'missingafter');
expect_err('missingafter: over 2 digits', function (&$p) { $p['missingafter'] = '100'; }, 'missingafter');
expect_err('sensorset: zero', function (&$p) { $p['sensorset'] = '0'; }, 'sensorset');
expect_err('sensorset: non-numeric', function (&$p) { $p['sensorset'] = 'abc'; }, 'sensorset');
expect_err('packageset: missing', function (&$p) { unset($p['packageset']); }, 'packageset');
expect_err('sensorhist: unknown value', function (&$p) { $p['sensorhist'] = 'Maybe'; }, 'sensorhist');
expect_err('srevcnt: zero while enabled', function (&$p) { $p['srevcnt'] = '0'; }, 'srevcnt');
expect_err('srevcnt: missing while enabled', function (&$p) { unset($p['srevcnt']); }, 'srevcnt');
expect_err('srevcnt: over 2 digits', function (&$p) { $p['srevcnt'] = '100'; }, 'srevcnt');
expect_err('packagehist: unknown value', function (&$p) { $p['packagehist'] = 'Nope'; }, 'packagehist');
expect_err('prevcnt: zero while enabled', function (&$p) { $p['prevcnt'] = '0'; }, 'prevcnt');
expect_err('prevcnt: over 2 digits', function (&$p) { $p['prevcnt'] = '100'; }, 'prevcnt');
expect_err('passlen: below 8', function (&$p) { $p['passlen'] = '7'; }, 'passlen');
expect_err('passlen: empty', function (&$p) { $p['passlen'] = ''; }, 'passlen');
expect_err('passlen: over 2 digits', function (&$p) { $p['passlen'] = '100'; }, 'passlen');
expect_err('complexpass: unknown value', function (&$p) { $p['complexpass'] = 'sometimes'; }, 'complexpass');
expect_err('passkeys: unknown value', function (&$p) { $p['passkeys'] = 'Maybe'; }, 'passkeys');
expect_err('2fa: unknown value', function (&$p) { $p['2fa'] = 'Recommended'; }, '2fa');
expect_err('inactiveint: zero', function (&$p) { $p['inactiveint'] = '0'; }, 'inactiveint');
expect_err('inactiveint: over 2 digits', function (&$p) { $p['inactiveint'] = '100'; }, 'inactiveint');
expect_err('inttype: unknown value', function (&$p) { $p['inttype'] = 'day'; }, 'inttype');
expect_err('2minwarn: missing', function (&$p) { unset($p['2minwarn']); }, '2minwarn');
// Array-typed fields (e.g. adminemail[]=x) must be rejected, not coerced.
expect_err('array-typed email rejected', function (&$p) { $p['adminemail'] = ['admin@example.com']; }, 'adminemail');
expect_err('array-typed int rejected', function (&$p) { $p['checkinint'] = ['5']; }, 'checkinint');

// Multiple invalid fields are all reported, not just the first.
$p = valid_post();
$p['adminemail'] = 'nope';
$p['checkinint'] = '0';
$p['passlen'] = '3';
$v = luminum_validate_serveropts($p);
ok('multiple errors: all reported', $v['ok'] === false && in_array('adminemail', $v['err'], true) && in_array('checkinint', $v['err'], true) && in_array('passlen', $v['err'], true), json_encode($v));

// An empty POST fails on every field.
$v = luminum_validate_serveropts([]);
ok('empty POST: rejected', $v['ok'] === false && count($v['err']) >= 15, json_encode($v));

echo str_repeat('-', 60), "\n";
if ($failures) {
    echo "FAILED: $failures check(s) failed\n";
    exit(1);
}
echo "All checks passed.\n";
exit(0);
