<?php
//
// Pure shaping helpers for the query results API (api/queryresults.php).
// Kept separate from the endpoint so they can be unit-tested without a DB
// connection or session.
//

// Shape one QUERYRESULTS row for the results API. The client hostname and
// sensor name come from the joins in queryresults.php; a client or sensor
// that no longer exists falls back to an ID-based label. The output is
// served whole: the results page renders it in full (a split sensor's
// output lines are the table's rows), and its size is already bounded by
// the MQTT answer cap (64 KiB per answer envelope).
function luminum_result_row($row) {
	return [
		'uid' => (int)$row['UID'],
		'hostname' => (is_string($row['HOSTNAME']) && $row['HOSTNAME'] !== '') ? $row['HOSTNAME'] : ('client ' . $row['UID']),
		'sensor' => (int)$row['SENSORID'],
		'sensor_name' => (is_string($row['SENSORNAME']) && $row['SENSORNAME'] !== '') ? $row['SENSORNAME'] : ('Sensor ' . $row['SENSORID']),
		'status' => $row['STATUS'],
		'output' => $row['OUTPUT'],
		'err' => $row['ERR'],
		'ts' => $row['TS'],
	];
}

// Shape one SENSORS row (ID, NAME, CSPLIT, DELIMITER, OUTCOLS) as a
// retrieve-sensor entry for the results API: the name the results page
// titles the column with, and - for a CSPLIT sensor - the delimiter and
// the named output columns (OUTCOLS split back on the delimiter) the page
// uses to expand the sensor's output into sub-columns.
function luminum_sensor_entry($row) {
	$outcols = null;
	if ((int)$row['CSPLIT'] === 1 && is_string($row['OUTCOLS']) && $row['OUTCOLS'] !== '') {
		$delim = (is_string($row['DELIMITER']) && $row['DELIMITER'] !== '') ? $row['DELIMITER'] : '|';
		$outcols = explode($delim, $row['OUTCOLS']);
	}
	return [
		'sid' => (int)$row['ID'],
		'name' => (is_string($row['NAME']) && $row['NAME'] !== '') ? $row['NAME'] : ('Sensor ' . $row['ID']),
		'csplit' => (int)$row['CSPLIT'],
		'delimiter' => $row['DELIMITER'],
		'outcols' => $outcols,
	];
}

// The retrieve sensor IDs named by a query command's DATA (the JSON format
// produced by luminum_query_command_data); [] when unparseable.
function luminum_query_data_sids($data) {
	$d = json_decode(is_string($data) ? $data : '', true);
	if (!is_array($d) || !isset($d['sensors']) || !is_array($d['sensors'])) { return []; }
	$out = [];
	foreach ($d['sensors'] as $s) {
		if (is_array($s) && isset($s['sid']) && is_int($s['sid'])) { $out[] = $s['sid']; }
	}
	return $out;
}
