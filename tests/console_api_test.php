<?php
//
// console_api_test.php - offline test harness for the console API helpers
// in server/console/html/api/clientmap.php.
//
// Usage: php tests/console_api_test.php
// Exit code: 0 if all checks pass, 1 otherwise.

require_once __DIR__ . '/../server/console/html/api/clientmap.php';

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

// --- luminum_client_row -----------------------------------------------------
$row = luminum_client_row([
    'ID' => '42',
    'HOSTNAME' => 'web-01',
    'IPV4' => '172.16.0.10',
    'OSPLATFORM' => 'Linux',
    'OSRELEASE' => 'Debian 12.10',
    'CLIENTVER' => '0.0.1',
    'CSTATE' => 'online',
    'LASTSEEN' => '2026-11-04 12:00:00',
]);

ok('client_row: exactly 8 keys', count($row) === 8, json_encode(array_keys($row)));
ok('client_row: ID cast to int', $row['id'] === 42, var_export($row['id'], true));
ok('client_row: hostname', $row['hostname'] === 'web-01');
ok('client_row: ip', $row['ip'] === '172.16.0.10');
ok('client_row: platform', $row['platform'] === 'Linux');
ok('client_row: os', $row['os'] === 'Debian 12.10');
ok('client_row: clientver', $row['clientver'] === '0.0.1');
ok('client_row: state', $row['state'] === 'online');
ok('client_row: lastseen', $row['lastseen'] === '2026-11-04 12:00:00');

// --- luminum_platform_tally -------------------------------------------------
$tally = ['linux' => 0, 'macos' => 0, 'windows' => 0];
luminum_platform_tally($tally, 'Linux');
luminum_platform_tally($tally, 'LINUX');
luminum_platform_tally($tally, 'macOS');
luminum_platform_tally($tally, 'Windows');
luminum_platform_tally($tally, 'FreeBSD'); // unknown: must be ignored
ok('tally: linux incremented case-insensitively', $tally['linux'] === 2, var_export($tally, true));
ok('tally: macos incremented', $tally['macos'] === 1);
ok('tally: windows incremented', $tally['windows'] === 1);
ok('tally: unknown platform ignored', array_sum($tally) === 4);

echo str_repeat('-', 60), "\n";
if ($failures) {
    echo "FAILED: $failures check(s) failed\n";
    exit(1);
}
echo "All checks passed.\n";
exit(0);
