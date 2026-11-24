<?php
//
// console_csrf_test.php - offline test harness for the console CSRF token
// helpers in server/console/html/layout/csrf.php.
//
// Usage: php tests/console_csrf_test.php
// Exit code: 0 if all checks pass, 1 otherwise.

require_once __DIR__ . '/../server/console/html/layout/csrf.php';

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

// --- token generation --------------------------------------------------------
$_SESSION = [];
unset($_POST);
unset($_SERVER['HTTP_X_CSRF_TOKEN']);
$t1 = luminum_csrf_token();
ok("token is 64 lowercase hex chars", is_string($t1) && preg_match('/^[0-9a-f]{64}$/', $t1) === 1, var_export($t1, true));
$t2 = luminum_csrf_token();
ok("token is stable within the session", $t1 === $t2);
$_SESSION = [];
$t3 = luminum_csrf_token();
ok("a new session gets a different token", $t3 !== $t1);
$_SESSION = ['CSRF' => 'short'];
$t4 = luminum_csrf_token();
ok("a malformed stored token is regenerated", $t4 !== 'short' && preg_match('/^[0-9a-f]{64}$/', $t4) === 1);
$_SESSION = ['CSRF' => $t1];

// --- field markup ------------------------------------------------------------
ob_start();
luminum_csrf_field();
$field = ob_get_clean();
ok("field is the hidden csrf input carrying the token",
    $field === '<input type="hidden" name="csrf" value="' . $t1 . '">', var_export($field, true));

// --- validation: accepted ----------------------------------------------------
$_POST = ['csrf' => $t1];
ok("matching form field accepted", luminum_csrf_valid() === true);
$_POST = [];
$_SERVER['HTTP_X_CSRF_TOKEN'] = $t1;
ok("matching X-CSRF-Token header accepted", luminum_csrf_valid() === true);

// --- validation: rejected ----------------------------------------------------
$_POST = [];
unset($_SERVER['HTTP_X_CSRF_TOKEN']);
ok("missing token rejected", luminum_csrf_valid() === false);
$_POST = ['csrf' => str_repeat('0', 64)];
ok("wrong token rejected", luminum_csrf_valid() === false);
$_POST = ['csrf' => ''];
ok("empty token rejected", luminum_csrf_valid() === false);
$_POST = ['csrf' => ['nested']];
ok("array field rejected", luminum_csrf_valid() === false);
$_POST = ['csrf' => $t1 . '0'];
ok("longer token rejected", luminum_csrf_valid() === false);
$_POST = ['csrf' => substr($t1, 0, 63)];
ok("shorter token rejected", luminum_csrf_valid() === false);

// Another session's token must not validate (the classic CSRF replay).
$other = $t3;
$_POST = ['csrf' => $other];
ok("another session's token rejected", luminum_csrf_valid() === false);

// --- precedence: the form field, when present, is the one checked ------------
$_POST = ['csrf' => $t1];
$_SERVER['HTTP_X_CSRF_TOKEN'] = $other;
ok("a good field is not invalidated by a conflicting header", luminum_csrf_valid() === true);
$_POST = ['csrf' => $other];
$_SERVER['HTTP_X_CSRF_TOKEN'] = $t1;
ok("a bad field is not rescued by a good header", luminum_csrf_valid() === false);
unset($_SERVER['HTTP_X_CSRF_TOKEN']);

echo "------------------------------------------------------------\n";
if ($failures > 0) {
    echo "FAILED: $failures check(s) failed\n";
    exit(1);
}
echo "All checks passed.\n";
exit(0);
