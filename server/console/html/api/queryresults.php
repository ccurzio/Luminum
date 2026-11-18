<?php
//
// Query results endpoint. Returns the most recent query commands (latest 50,
// newest first) with their per-sensor results - QUERYRESULTS, filled by the
// broker's MQTT worker when a client answers (protocol 7.3) - for the
// console's query page. A query with no answers yet carries an empty results
// list; endpoints on which the condition tree evaluated false never appear
// at all.
//
// With an optional ?id= parameter (the query command's COMMANDS.ID - the
// "command" value /api/commands.php returns when the query is submitted) the
// response carries only that query, which is how the query page shows the
// results for a single submitted query.
//
require_once __DIR__ . '/_init.php';
require_once __DIR__ . '/queryresultmap.php';

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
	json_error('Method not allowed', 405);
}

$onlyid = 0;
if (isset($_GET['id']) && ctype_digit($_GET['id']) && (int)$_GET['id'] > 0) {
	$onlyid = (int)$_GET['id'];
}

$start = microtime(true);
$sql = "select ID,QID,TARGET,CREATED,STATUS,DATA from COMMANDS where ACTION = 'query'";
if ($onlyid > 0) { $sql .= " and ID = $onlyid"; }
$sql .= " order by ID desc limit 50";
$result = api_query($db, $sql, 'CLIENTS');
$queries = [];
$allsids = [];
while ($row = mysqli_fetch_assoc($result)) {
	$sids = luminum_query_data_sids($row['DATA']);
	foreach ($sids as $sid) {
		if (!in_array($sid, $allsids, true)) { $allsids[] = $sid; }
	}
	$queries[] = ['row' => $row, 'sids' => $sids];
}

// Sensor names for the retrieve lists (one lookup for all 50 queries).
$names = [];
if (count($allsids) > 0) {
	$in = implode(',', array_map('intval', $allsids));
	$result = api_query($db, "select ID,NAME from SENSORS where ID in ($in)", 'CONTENT');
	while ($nrow = mysqli_fetch_assoc($result)) {
		$names[(int)$nrow['ID']] = $nrow['NAME'];
	}
}

$out = [];
foreach ($queries as $q) {
	$row = $q['row'];
	$qid = mysqli_real_escape_string($db, $row['QID']);
	$result = api_query($db, "select r.UID, r.SENSORID, r.STATUS, r.OUTPUT, r.ERR, r.TS, s.NAME as SENSORNAME, st.HOSTNAME from CLIENTS.QUERYRESULTS r left join CONTENT.SENSORS s on s.ID = r.SENSORID left join CLIENTS.STATUS st on st.ID = r.UID where r.QID = '$qid' order by r.ID", 'CLIENTS');
	$results = [];
	while ($rrow = mysqli_fetch_assoc($result)) {
		$results[] = luminum_result_row($rrow);
	}
	// The retrieve sensors as {sid, name} pairs (the query's order): the
	// results page builds one table column per entry and matches each
	// result row to its column by sid.
	$sensor_list = [];
	foreach ($q['sids'] as $sid) {
		$sensor_list[] = ['sid' => $sid, 'name' => isset($names[$sid]) ? $names[$sid] : ('Sensor ' . $sid)];
	}
	$dd = json_decode(is_string($row['DATA']) ? $row['DATA'] : '', true);
	$out[] = [
		'command' => (int)$row['ID'],
		'qid' => $row['QID'],
		'target' => $row['TARGET'],
		'created' => $row['CREATED'],
		'status' => $row['STATUS'],
		'sensors' => $sensor_list,
		'conditions' => is_array($dd) && isset($dd['conditions']),
		'results' => $results,
	];
}
$end = microtime(true);

json_out([
	'count' => count($out),
	'query_ms' => number_format($end - $start, 2, '.', ''),
	'queries' => $out,
]);
