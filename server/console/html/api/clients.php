<?php
//
// Client Status endpoint. Returns the live client list (non-missing clients)
// as JSON for the console's Client Status table, plus the check-in interval
// (for the time filter's "Check-in Interval(s)" option), the server clock
// (the time filter's "now"), and the query duration. The console derives the
// OS/status breakdowns from the rows it currently displays, so they are not
// computed here.
//
require_once __DIR__ . '/_init.php';
require_once __DIR__ . '/clientmap.php';

$start = microtime(true);
$result = api_query(
	$db,
	"select ID,HOSTNAME,IPV4,OSPLATFORM,OSRELEASE,CLIENTVER,CSTATE,LASTSEEN,UNIX_TIMESTAMP(LASTSEEN) as LASTSEEN_TS from STATUS where MISSING = 0 order by HOSTNAME",
	'CLIENTS'
);

$rows = [];
while ($row = mysqli_fetch_assoc($result)) {
	$rows[] = luminum_client_row($row);
}
$end = microtime(true);

// The check-in interval in minutes (SYSTEM.CONFIG, default 5); the console's
// time filter turns "N Check-in Interval(s)" into N * this many minutes.
// Null when the value is absent or invalid, in which case the console falls
// back to the 5-minute default.
$checkinint = null;
$ci = api_query($db, "select CVAL from CONFIG where CKEY = 'CHECKININT'", 'SYSTEM');
if ($cirow = mysqli_fetch_assoc($ci)) {
	if (is_numeric($cirow['CVAL']) && (int)$cirow['CVAL'] > 0) {
		$checkinint = (int)$cirow['CVAL'];
	}
}

json_out([
	'count' => count($rows),
	'query_ms' => number_format($end - $start, 2, '.', ''),
	'checkinint' => $checkinint,
	'server_ts' => time(),
	'rows' => $rows,
]);
