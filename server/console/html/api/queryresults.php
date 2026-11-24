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
// Each query also carries the inputs for the results page's footer clock:
// the command's deadline (deadline_ts, set to now() + CMDTIMEOUT when the
// MQTT worker publishes it), its SENT/CREATED/ACKED instants, target_online
// (the online endpoints the target must answer - CSTATE = 'OK'), answered
// (the unique endpoints that have), no_match (the unique endpoints that
// reported NO_MATCH - the query's condition tree evaluated false on them,
// protocol 7.3), and last_answer_ts (the newest response of either kind).
// The page's clock stops at the soonest of the deadline or every online
// target endpoint having answered or reported no match.
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
$sql = "select ID,QID,TARGET,CREATED,UNIX_TIMESTAMP(CREATED) as CREATED_TS,STATUS,UNIX_TIMESTAMP(SENT) as SENT_TS,UNIX_TIMESTAMP(ACKED) as ACKED_TS,UNIX_TIMESTAMP(DEADLINE) as DEADLINE_TS,DATA from COMMANDS where ACTION = 'query'";
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

// Sensor names (and the CSPLIT/DELIMITER/OUTCOLS the results page needs to
// expand a split sensor's output into named sub-columns) for the retrieve
// lists (one lookup for all 50 queries).
$sensors = [];
if (count($allsids) > 0) {
	$in = implode(',', array_map('intval', $allsids));
	$result = api_query($db, "select ID,NAME,CSPLIT,DELIMITER,OUTCOLS from SENSORS where ID in ($in)", 'CONTENT');
	while ($nrow = mysqli_fetch_assoc($result)) {
		$sensors[(int)$nrow['ID']] = $nrow;
	}
}

// The online endpoints a query's target must answer (the results page's
// clock stops when every one has): CSTATE = 'OK' (a live check-in). "all"
// is every online endpoint; a numeric target is that one client (0 when it
// is not online or no longer exists). Cached per target - the 50-query
// listing repeats targets.
$online_cache = [];
$target_online = function ($target) use ($db, &$online_cache) {
	if (array_key_exists($target, $online_cache)) { return $online_cache[$target]; }
	if ($target === 'all') {
		$result = api_query($db, "select count(*) as N from STATUS where CSTATE = 'OK'", 'CLIENTS');
	} else {
		$uid = (int)$target;
		$result = api_query($db, "select if(CSTATE = 'OK', 1, 0) as N from STATUS where ID = $uid", 'CLIENTS');
	}
	$crow = mysqli_fetch_assoc($result);
	$n = $crow !== null ? (int)$crow['N'] : 0;
	$online_cache[$target] = $n;
	return $n;
};

$out = [];
foreach ($queries as $q) {
	$row = $q['row'];
	$qid = mysqli_real_escape_string($db, $row['QID']);
	$result = api_query($db, "select r.UID, r.SENSORID, r.STATUS, r.OUTPUT, r.ERR, r.TS, UNIX_TIMESTAMP(r.TS) as TS_EPOCH, s.NAME as SENSORNAME, st.HOSTNAME from CLIENTS.QUERYRESULTS r left join CONTENT.SENSORS s on s.ID = r.SENSORID left join CLIENTS.STATUS st on st.ID = r.UID where r.QID = '$qid' order by r.ID", 'CLIENTS');
	$results = [];
	$answer_uids = [];
	$last_ts = 0;
	while ($rrow = mysqli_fetch_assoc($result)) {
		$results[] = luminum_result_row($rrow);
		$answer_uids[(int)$rrow['UID']] = true;
		$ts = (int)$rrow['TS_EPOCH'];
		if ($ts > $last_ts) { $last_ts = $ts; }
	}
	// No-match reports (protocol 7.3): the endpoints on which the query's
	// condition tree evaluated false. They carry no results - only the
	// (QID, UID) record and its instant, which the clock's stop condition
	// (every online target endpoint answered or no-matched) and
	// last_answer_ts use.
	$nomatch_uids = [];
	$result = api_query($db, "select UID, UNIX_TIMESTAMP(TS) as TS_EPOCH from CLIENTS.QUERYNOMATCH where QID = '$qid'", 'CLIENTS');
	while ($nrow = mysqli_fetch_assoc($result)) {
		$nomatch_uids[(int)$nrow['UID']] = true;
		$ts = (int)$nrow['TS_EPOCH'];
		if ($ts > $last_ts) { $last_ts = $ts; }
	}
	// The retrieve sensors (the query's order): the results page builds one
	// table column per entry and matches each result row to its column by
	// sid. A sensor that no longer exists falls back to an ID-based label
	// with no split metadata.
	$sensor_list = [];
	foreach ($q['sids'] as $sid) {
		$sensor_list[] = isset($sensors[$sid])
			? luminum_sensor_entry($sensors[$sid])
			: ['sid' => $sid, 'name' => 'Sensor ' . $sid, 'csplit' => 0, 'delimiter' => null, 'outcols' => null];
	}
	$dd = json_decode(is_string($row['DATA']) ? $row['DATA'] : '', true);
	$out[] = [
		'command' => (int)$row['ID'],
		'qid' => $row['QID'],
		'target' => $row['TARGET'],
		'created' => $row['CREATED'],
		'created_ts' => (int)$row['CREATED_TS'],
		'sent_ts' => $row['SENT_TS'] !== null ? (int)$row['SENT_TS'] : null,
		'acked_ts' => $row['ACKED_TS'] !== null ? (int)$row['ACKED_TS'] : null,
		'deadline_ts' => $row['DEADLINE_TS'] !== null ? (int)$row['DEADLINE_TS'] : null,
		'status' => $row['STATUS'],
		'target_online' => $target_online($row['TARGET']),
		'answered' => count($answer_uids),
		'no_match' => count($nomatch_uids),
		'last_answer_ts' => (count($answer_uids) + count($nomatch_uids)) > 0 ? $last_ts : null,
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
