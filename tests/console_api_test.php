<?php
//
// console_api_test.php - offline test harness for the console API helpers
// in server/console/html/api/clientmap.php, commandmap.php, and
// queryresultmap.php.
//
// Usage: php tests/console_api_test.php
// Exit code: 0 if all checks pass, 1 otherwise.

require_once __DIR__ . '/../server/console/html/api/clientmap.php';
require_once __DIR__ . '/../server/console/html/api/commandmap.php';
require_once __DIR__ . '/../server/console/html/api/queryresultmap.php';

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
    'LASTSEEN_TS' => '1762305600',
]);

ok('client_row: exactly 9 keys', count($row) === 9, json_encode(array_keys($row)));
ok('client_row: ID cast to int', $row['id'] === 42, var_export($row['id'], true));
ok('client_row: hostname', $row['hostname'] === 'web-01');
ok('client_row: ip', $row['ip'] === '172.16.0.10');
ok('client_row: platform', $row['platform'] === 'Linux');
ok('client_row: os', $row['os'] === 'Debian 12.10');
ok('client_row: clientver', $row['clientver'] === '0.0.1');
ok('client_row: state', $row['state'] === 'online');
ok('client_row: lastseen', $row['lastseen'] === '2026-11-04 12:00:00');
ok('client_row: lastseen_ts cast to int', $row['lastseen_ts'] === 1762305600, var_export($row['lastseen_ts'], true));
ok('client_row: null LASTSEEN_TS stays null',
    luminum_client_row(['ID' => '1', 'HOSTNAME' => 'h', 'IPV4' => 'i', 'OSPLATFORM' => 'p',
        'OSRELEASE' => 'o', 'CLIENTVER' => 'c', 'CSTATE' => 's', 'LASTSEEN' => null, 'LASTSEEN_TS' => null])['lastseen_ts'] === null);

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

// --- luminum_query_ops ------------------------------------------------------
ok('ops: the eight protocol operators',
	luminum_query_ops() === ['==', '!=', '=~', '!~', '>', '>=', '<', '<=']);

// --- luminum_validate_query_conditions --------------------------------------
$leaf = ['sid' => 3, 'op' => '==', 'value' => 'prod'];
ok('conditions: valid leaf', luminum_validate_query_conditions($leaf) === $leaf);
ok('conditions: leaf with params',
	luminum_validate_query_conditions(['sid' => 3, 'op' => '==', 'value' => 'x', 'params' => ['h' => 'db-01']])
		=== ['sid' => 3, 'op' => '==', 'value' => 'x', 'params' => ['h' => 'db-01']]);
ok('conditions: empty params omitted',
	luminum_validate_query_conditions(['sid' => 3, 'op' => '==', 'value' => 'x', 'params' => []])
		=== ['sid' => 3, 'op' => '==', 'value' => 'x']);
$node = ['logic' => 'AND', 'left' => $leaf, 'right' => ['sid' => 4, 'op' => '=~', 'value' => 'web']];
ok('conditions: valid AND node', luminum_validate_query_conditions($node) === $node);
ok('conditions: nested OR node', luminum_validate_query_conditions([
	'logic' => 'OR',
	'left' => $node,
	'right' => ['sid' => 5, 'op' => '>', 'value' => '10'],
]) !== null);
ok('conditions: rejects null', luminum_validate_query_conditions(null) === null);
ok('conditions: rejects non-array', luminum_validate_query_conditions('nope') === null);
ok('conditions: rejects unknown op', luminum_validate_query_conditions(['sid' => 3, 'op' => 'eq', 'value' => 'x']) === null);
ok('conditions: rejects string sid', luminum_validate_query_conditions(['sid' => '3', 'op' => '==', 'value' => 'x']) === null);
ok('conditions: rejects zero sid', luminum_validate_query_conditions(['sid' => 0, 'op' => '==', 'value' => 'x']) === null);
ok('conditions: rejects missing value', luminum_validate_query_conditions(['sid' => 3, 'op' => '==']) === null);
ok('conditions: rejects non-string value', luminum_validate_query_conditions(['sid' => 3, 'op' => '==', 'value' => 3]) === null);
ok('conditions: rejects over-long value', luminum_validate_query_conditions(['sid' => 3, 'op' => '==', 'value' => str_repeat('a', 1025)]) === null);
ok('conditions: rejects bad param key', luminum_validate_query_conditions(['sid' => 3, 'op' => '==', 'value' => 'x', 'params' => ['bad key' => 'v']]) === null);
ok('conditions: rejects bad param value', luminum_validate_query_conditions(['sid' => 3, 'op' => '==', 'value' => 'x', 'params' => ['k' => 3]]) === null);
ok('conditions: rejects bad logic', luminum_validate_query_conditions(['logic' => 'XOR', 'left' => $leaf, 'right' => $leaf]) === null);
ok('conditions: rejects node missing children', luminum_validate_query_conditions(['logic' => 'AND', 'left' => $leaf]) === null);
ok('conditions: rejects node with bad child', luminum_validate_query_conditions(['logic' => 'AND', 'left' => $leaf, 'right' => ['sid' => 0, 'op' => '==', 'value' => 'x']]) === null);
// 26 leaves is over the cap.
$big = $leaf;
for ($i = 0; $i < 25; $i++) { $big = ['logic' => 'AND', 'left' => $big, 'right' => $leaf]; }
ok('conditions: rejects 26 leaves', luminum_validate_query_conditions($big) === null);
// Depth over 8 (25 leaves also trips the leaf cap, so use a single-leaf chain).
$deep = $leaf;
for ($i = 0; $i < 10; $i++) { $deep = ['logic' => 'AND', 'left' => $deep, 'right' => $leaf]; }
ok('conditions: rejects depth over 8', luminum_validate_query_conditions($deep) === null);

// --- luminum_query_condition_sids -------------------------------------------
ok('condition sids: flat leaf', luminum_query_condition_sids($leaf) === [3]);
ok('condition sids: node, first-occurrence order, deduplicated',
	luminum_query_condition_sids(['logic' => 'OR',
		'left' => ['logic' => 'AND', 'left' => ['sid' => 4, 'op' => '==', 'value' => 'a'], 'right' => $leaf],
		'right' => ['sid' => 4, 'op' => '==', 'value' => 'b']]) === [4, 3]);

// --- luminum_query_sensor_ids -------------------------------------------------
$sensors2 = [['sid' => 7, 'params' => []], ['sid' => 9, 'params' => []]];
ok('query sensor ids: retrieve sensors only',
	luminum_query_sensor_ids($sensors2, null) === [7, 9]);
ok('query sensor ids: condition leaves join, deduplicated against retrieve',
	luminum_query_sensor_ids([['sid' => 3, 'params' => []]], $node) === [3, 4]);
ok('query sensor ids: retrieve order first, then condition order',
	luminum_query_sensor_ids($sensors2, ['logic' => 'OR',
		'left' => ['sid' => 9, 'op' => '==', 'value' => 'a'],
		'right' => ['sid' => 5, 'op' => '==', 'value' => 'b']]) === [7, 9, 5]);
ok('query sensor ids: nested tree walked',
	luminum_query_sensor_ids([['sid' => 1, 'params' => []]], ['logic' => 'AND',
		'left' => ['logic' => 'OR', 'left' => ['sid' => 2, 'op' => '==', 'value' => 'a'], 'right' => ['sid' => 3, 'op' => '==', 'value' => 'b']],
		'right' => ['sid' => 2, 'op' => '==', 'value' => 'c']]) === [1, 2, 3]);

// --- luminum_missing_sensor_ids -----------------------------------------------
ok('missing ids: none missing', luminum_missing_sensor_ids($sensors2, $node, [7, 9, 3, 4]) === []);
ok('missing ids: a retrieve sensor', luminum_missing_sensor_ids($sensors2, null, [9]) === [7]);
ok('missing ids: a condition leaf', luminum_missing_sensor_ids([['sid' => 7, 'params' => []]], $node, [7, 3]) === [4]);
ok('missing ids: every missing ID reported, first-occurrence order',
	luminum_missing_sensor_ids([['sid' => 9, 'params' => []], ['sid' => 7, 'params' => []]], $node, []) === [9, 7, 3, 4]);
ok('missing ids: a shared retrieve+condition ID reported once',
	luminum_missing_sensor_ids([['sid' => 3, 'params' => []]], $node, []) === [3, 4]);
ok('missing ids: string existing IDs do not match (strict)',
	luminum_missing_sensor_ids($sensors2, null, ['7', '9']) === [7, 9]);

// --- luminum_sensor_has_script ----------------------------------------------
$full = ['LSTYPE' => 'shell', 'LSCRIPT' => 'echo l', 'MSTYPE' => 'shell', 'MSCRIPT' => 'echo m', 'WSTYPE' => 'powershell', 'WSCRIPT' => 'echo w'];
$linuxonly = ['LSTYPE' => 'shell', 'LSCRIPT' => 'echo l', 'MSTYPE' => null, 'MSCRIPT' => null, 'WSTYPE' => null, 'WSCRIPT' => null];
$none = ['LSTYPE' => null, 'LSCRIPT' => null, 'MSTYPE' => null, 'MSCRIPT' => null, 'WSTYPE' => null, 'WSCRIPT' => null];
ok('has_script: platform pair present', luminum_sensor_has_script($full, ['LSTYPE', 'LSCRIPT']) === true);
ok('has_script: platform pair absent', luminum_sensor_has_script($linuxonly, ['MSTYPE', 'MSCRIPT']) === false);
ok('has_script: empty type rejected', luminum_sensor_has_script(['LSTYPE' => '', 'LSCRIPT' => 'echo l'], ['LSTYPE', 'LSCRIPT']) === false);
ok('has_script: empty script rejected', luminum_sensor_has_script(['LSTYPE' => 'shell', 'LSCRIPT' => ''], ['LSTYPE', 'LSCRIPT']) === false);
ok('has_script: any platform (broadcast)', luminum_sensor_has_script($linuxonly, null) === true);
ok('has_script: no platform (broadcast)', luminum_sensor_has_script($none, null) === false);
ok('has_script: non-array row', luminum_sensor_has_script(null, null) === false);

// --- luminum_merge_sensor_params --------------------------------------------
$known = ['host' => 'db-01', 'port' => null];
ok('merge params: provided wins', luminum_merge_sensor_params($known, ['host' => 'web-01']) === ['host' => 'web-01']);
ok('merge params: default fills gap', luminum_merge_sensor_params($known, []) === ['host' => 'db-01']);
ok('merge params: null default dropped', luminum_merge_sensor_params(['p' => null], []) === []);
ok('merge params: declared order kept', luminum_merge_sensor_params(['a' => '1', 'b' => '2'], ['b' => 'x', 'a' => 'y']) === ['a' => 'y', 'b' => 'x']);
ok('merge params: empty string provided wins over default', luminum_merge_sensor_params(['a' => '1'], ['a' => '']) === ['a' => '']);

// --- luminum_query_command_data with conditions ------------------------------
$data = luminum_query_command_data('qid-1', [['sid' => 7, 'params' => []]], $node);
$decoded = json_decode($data, true);
ok('query data: conditions carried when present',
	$decoded === ['qid' => 'qid-1', 'sensors' => [['sid' => 7]], 'conditions' => $node],
	$data);
$data = luminum_query_command_data('qid-1', [['sid' => 7, 'params' => []]], null);
$decoded = json_decode($data, true);
ok('query data: conditions field omitted when null',
	$decoded === ['qid' => 'qid-1', 'sensors' => [['sid' => 7]]],
	$data);

// --- luminum_result_row output passthrough -----------------------------------
// The results page renders the output in full (a split sensor's output
// lines are the table's rows), so the API must serve it whole - a large
// multi-line output (well past the old 4096-byte preview cap) arrives
// byte-for-byte, and a null output (an ERR answer) stays null.
$big = '';
for ($i = 1; $i <= 300; $i++) { $big .= sprintf("app-%03d|1.0.%d\n", $i, $i); }
ok('result row: a large output is served whole (no preview cap)',
	luminum_result_row(['UID' => '1', 'HOSTNAME' => 'h', 'SENSORID' => '9', 'SENSORNAME' => 's',
		'STATUS' => 'OK', 'OUTPUT' => $big, 'ERR' => null, 'TS' => 't'])['output'] === $big);
ok('result row: a null output stays null',
	luminum_result_row(['UID' => '1', 'HOSTNAME' => 'h', 'SENSORID' => '9', 'SENSORNAME' => 's',
		'STATUS' => 'ERR', 'OUTPUT' => null, 'ERR' => 'TIMEOUT', 'TS' => 't'])['output'] === null);

// --- luminum_result_row -------------------------------------------------------
$rr = luminum_result_row([
	'UID' => '42', 'HOSTNAME' => 'web-01', 'SENSORID' => '7', 'SENSORNAME' => 'probe',
	'STATUS' => 'OK', 'OUTPUT' => "line1\nline2", 'ERR' => null, 'TS' => '2026-11-16 10:00:00',
]);
ok('result row: shaped fields',
	$rr === ['uid' => 42, 'hostname' => 'web-01', 'sensor' => 7, 'sensor_name' => 'probe',
		'status' => 'OK', 'output' => "line1\nline2", 'err' => null, 'ts' => '2026-11-16 10:00:00'],
	json_encode($rr));
$rr = luminum_result_row([
	'UID' => '42', 'HOSTNAME' => null, 'SENSORID' => '7', 'SENSORNAME' => null,
	'STATUS' => 'ERR', 'OUTPUT' => null, 'ERR' => 'TIMEOUT', 'TS' => '2026-11-16 10:00:00',
]);
ok('result row: deleted client/sensor fall back to ID labels',
	$rr['hostname'] === 'client 42' && $rr['sensor_name'] === 'Sensor 7', json_encode($rr));

// --- luminum_query_data_sids --------------------------------------------------
ok('data sids: parsed from query DATA',
	luminum_query_data_sids('{"qid":"q","sensors":[{"sid":7},{"sid":9,"params":{"h":"x"}}]}') === [7, 9]);
ok('data sids: unparseable DATA -> []', luminum_query_data_sids('not json') === []);
ok('data sids: non-string DATA -> []', luminum_query_data_sids(null) === []);
ok('data sids: missing sensors -> []', luminum_query_data_sids('{"qid":"q"}') === []);
ok('data sids: bad entries skipped', luminum_query_data_sids('{"sensors":[{"sid":7},{"sid":"x"},3]}') === [7]);

echo str_repeat('-', 60), "\n";
if ($failures) {
    echo "FAILED: $failures check(s) failed\n";
    exit(1);
}
echo "All checks passed.\n";
exit(0);
