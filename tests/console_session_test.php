<?php
//
// console_session_test.php - offline test harness for the console session
// timeout helpers in server/console/html/layout/session.php. Only the
// DB-free luminum_parse_utimeout() is exercised here; the DB-backed helpers
// are covered end to end by tests/deploy_test.sh.
//
// Usage: php tests/console_session_test.php
// Exit code: 0 if all checks pass, 1 otherwise.

require_once __DIR__ . '/../server/console/html/layout/session.php';

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

// --- luminum_parse_utimeout -------------------------------------------------
ok('parse: 15M default value', luminum_parse_utimeout('15M') === 900);
ok('parse: 90S', luminum_parse_utimeout('90S') === 90);
ok('parse: 2M', luminum_parse_utimeout('2M') === 120);
ok('parse: 1H', luminum_parse_utimeout('1H') === 3600);
ok('parse: 12H', luminum_parse_utimeout('12H') === 43200);
ok('parse: 1D', luminum_parse_utimeout('1D') === 86400);
ok('parse: 30D', luminum_parse_utimeout('30D') === 2592000);
ok('parse: rejects empty string', luminum_parse_utimeout('') === null);
ok('parse: rejects number without unit', luminum_parse_utimeout('15') === null);
ok('parse: rejects zero', luminum_parse_utimeout('0M') === null);
ok('parse: rejects lowercase unit', luminum_parse_utimeout('15m') === null);
ok('parse: rejects negative', luminum_parse_utimeout('-5M') === null);
ok('parse: rejects garbage', luminum_parse_utimeout('abc') === null);
ok('parse: rejects trailing junk', luminum_parse_utimeout('15M30S') === null);
ok('parse: rejects leading space', luminum_parse_utimeout(' 15M') === null);
ok('parse: rejects non-string int', luminum_parse_utimeout(15) === null);
ok('parse: rejects non-string null', luminum_parse_utimeout(null) === null);
ok('parse: rejects non-string array', luminum_parse_utimeout(['15M']) === null);

echo str_repeat('-', 60), "\n";
if ($failures) {
    echo "FAILED: $failures check(s) failed\n";
    exit(1);
}
echo "All checks passed.\n";
exit(0);
