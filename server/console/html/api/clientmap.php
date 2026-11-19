<?php
//
// Pure mapping helpers for the Client Status API. Kept separate from the
// endpoint so they can be unit-tested without a DB connection or session.
//

// Map a CLIENTS.STATUS row (mysqli assoc) to the JSON shape the console uses.
// LASTSEEN_TS is UNIX_TIMESTAMP(LASTSEEN) from the endpoint's query; it is the
// epoch-seconds form the console's check-in time filter compares against.
function luminum_client_row($row) {
	return [
		'id' => (int)$row['ID'],
		'hostname' => $row['HOSTNAME'],
		'ip' => $row['IPV4'],
		'platform' => $row['OSPLATFORM'],
		'os' => $row['OSRELEASE'],
		'clientver' => $row['CLIENTVER'],
		'state' => $row['CSTATE'],
		'lastseen' => $row['LASTSEEN'],
		'lastseen_ts' => $row['LASTSEEN_TS'] !== null ? (int)$row['LASTSEEN_TS'] : null,
	];
}
