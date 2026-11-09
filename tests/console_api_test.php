<?php
//
// console_api_test.php - offline test harness for the console API helpers
// in server/console/html/api/clientmap.php and commandmap.php.
//
// Usage: php tests/console_api_test.php
// Exit code: 0 if all checks pass, 1 otherwise.

require_once __DIR__ . '/../server/console/html/api/clientmap.php';
require_once __DIR__ . '/../server/console/html/api/commandmap.php';

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

// --- luminum_validate_target ------------------------------------------------
ok('target: valid numeric UID', luminum_validate_target('42') === '42');
ok('target: single digit', luminum_validate_target('0') === '0');
ok('target: rejects empty string', luminum_validate_target('') === null);
ok('target: rejects non-numeric', luminum_validate_target('abc') === null);
ok('target: rejects mixed', luminum_validate_target('12a') === null);
ok('target: rejects negative', luminum_validate_target('-1') === null);
ok('target: rejects non-string', luminum_validate_target(42) === null);
ok('target: rejects null', luminum_validate_target(null) === null);
ok('target: rejects over-long IDs', luminum_validate_target('12345678901') === null);
ok('target: group-style targets are not per-UID', luminum_validate_target('grp/web') === null);

// --- luminum_validate_groups ------------------------------------------------
ok('groups: valid list', luminum_validate_groups(['web', 'db']) === ['web', 'db']);
ok('groups: empty list is valid (leave all groups)', luminum_validate_groups([]) === []);
ok('groups: charset allows dot underscore dash', luminum_validate_groups(['g_1.x-2']) === ['g_1.x-2']);
ok('groups: deduplicates, order preserved', luminum_validate_groups(['a', 'b', 'a']) === ['a', 'b']);
ok('groups: rejects non-array (null)', luminum_validate_groups(null) === null);
ok('groups: rejects non-array (string)', luminum_validate_groups('web') === null);
ok('groups: rejects non-string element', luminum_validate_groups(['web', 3]) === null);
ok('groups: rejects spaces in names', luminum_validate_groups(['web db']) === null);
ok('groups: rejects empty name', luminum_validate_groups(['']) === null);
ok('groups: rejects over-long names', luminum_validate_groups([str_repeat('a', 65)]) === null);

// --- luminum_command_data ---------------------------------------------------
ok('command_data: full replacement list shape',
	luminum_command_data(['web', 'db']) === '{"groups":["web","db"]}');
ok('command_data: empty list', luminum_command_data([]) === '{"groups":[]}');

// --- luminum_uuid4 ----------------------------------------------------------
$qid = luminum_uuid4();
ok('uuid4: matches the envelope id format',
	preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/', $qid) === 1,
	$qid);
ok('uuid4: distinct across calls', luminum_uuid4() !== $qid);

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
