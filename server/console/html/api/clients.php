<?php
//
// Client Status endpoint. Returns the live client list (non-missing clients)
// as JSON for the console's Client Status table, plus the OS breakdown and
// the query duration.
//
require_once __DIR__ . '/_init.php';
require_once __DIR__ . '/clientmap.php';

$start = microtime(true);
$result = api_query(
	$db,
	"select ID,HOSTNAME,IPV4,OSPLATFORM,OSRELEASE,CLIENTVER,CSTATE,LASTSEEN from STATUS where MISSING = 0 order by HOSTNAME",
	'CLIENTS'
);

$rows = [];
$platforms = ['linux' => 0, 'macos' => 0, 'windows' => 0];
while ($row = mysqli_fetch_assoc($result)) {
	luminum_platform_tally($platforms, $row['OSPLATFORM']);
	$rows[] = luminum_client_row($row);
}
$end = microtime(true);

json_out([
	'count' => count($rows),
	'query_ms' => number_format($end - $start, 2, '.', ''),
	'platforms' => $platforms,
	'rows' => $rows,
]);
