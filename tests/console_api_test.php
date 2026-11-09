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

// --- luminum_os_script_cols -------------------------------------------------
ok('script cols: Linux -> L pair', luminum_os_script_cols('Linux') === ['LSTYPE', 'LSCRIPT']);
ok('script cols: lowercase linux', luminum_os_script_cols('linux') === ['LSTYPE', 'LSCRIPT']);
ok('script cols: macOS -> M pair', luminum_os_script_cols('macOS') === ['MSTYPE', 'MSCRIPT']);
ok('script cols: Windows -> W pair', luminum_os_script_cols('Windows') === ['WSTYPE', 'WSCRIPT']);
ok('script cols: unknown platform -> null', luminum_os_script_cols('FreeBSD') === null);
ok('script cols: non-string -> null', luminum_os_script_cols(42) === null);
ok('script cols: null -> null', luminum_os_script_cols(null) === null);

// --- luminum_validate_query_sensors -----------------------------------------
ok('query sensors: valid single entry',
	luminum_validate_query_sensors([['sid' => 7]]) === [['sid' => 7, 'params' => []]]);
ok('query sensors: valid with params',
	luminum_validate_query_sensors([['sid' => 9, 'params' => ['host' => 'db-01', 'p_2' => 'x']]])
		=== [['sid' => 9, 'params' => ['host' => 'db-01', 'p_2' => 'x']]]);
ok('query sensors: explicit null params normalized to empty',
	luminum_validate_query_sensors([['sid' => 1, 'params' => null]]) === [['sid' => 1, 'params' => []]]);
ok('query sensors: rejects null', luminum_validate_query_sensors(null) === null);
ok('query sensors: rejects non-array', luminum_validate_query_sensors('nope') === null);
ok('query sensors: rejects empty list', luminum_validate_query_sensors([]) === null);
ok('query sensors: rejects over-long list',
	luminum_validate_query_sensors(array_map(fn($i) => ['sid' => $i], range(1, 26))) === null);
ok('query sensors: rejects non-array element', luminum_validate_query_sensors([7]) === null);
ok('query sensors: rejects string sid', luminum_validate_query_sensors([['sid' => '7']]) === null);
ok('query sensors: rejects float sid', luminum_validate_query_sensors([['sid' => 7.5]]) === null);
ok('query sensors: rejects zero sid', luminum_validate_query_sensors([['sid' => 0]]) === null);
ok('query sensors: rejects missing sid', luminum_validate_query_sensors([['params' => []]]) === null);
ok('query sensors: rejects duplicate sids',
	luminum_validate_query_sensors([['sid' => 7], ['sid' => 7]]) === null);
ok('query sensors: rejects non-string param value',
	luminum_validate_query_sensors([['sid' => 7, 'params' => ['n' => 3]]]) === null);
ok('query sensors: rejects bad param key',
	luminum_validate_query_sensors([['sid' => 7, 'params' => ['bad key' => 'x']]]) === null);
ok('query sensors: rejects over-long param value',
	luminum_validate_query_sensors([['sid' => 7, 'params' => ['k' => str_repeat('a', 1025)]]]) === null);

// --- luminum_query_command_data ---------------------------------------------
$data = luminum_query_command_data('qid-1', [
	['sid' => 7, 'params' => []],
	['sid' => 9, 'params' => ['host' => 'db-01']],
]);
$decoded = json_decode($data, true);
ok('query data: qid + sensors shape',
	$decoded === ['qid' => 'qid-1', 'sensors' => [['sid' => 7], ['sid' => 9, 'params' => ['host' => 'db-01']]]],
	$data);
ok('query data: params omitted when empty', strpos($data, '"params":[]') === false);

// --- luminum_sensor_config_data ---------------------------------------------
$defs = [
	['sid' => 7, 'name' => 'probe', 'lstype' => 'shell', 'lscript' => 'echo ok',
	 'mstype' => null, 'mscript' => null, 'wstype' => null, 'wscript' => null],
];
$sdata = luminum_sensor_config_data($defs);
$decoded = json_decode($sdata, true);
ok('sensor config data: sensors array shape',
	$decoded === ['sensors' => [['sid' => 7, 'name' => 'probe', 'lstype' => 'shell', 'lscript' => 'echo ok',
		'mstype' => null, 'mscript' => null, 'wstype' => null, 'wscript' => null]]],
	$sdata);

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
