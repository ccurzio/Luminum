<?php
//
// Pure mapping helpers for the Client Status API. Kept separate from the
// endpoint so they can be unit-tested without a DB connection or session.
//

// Map a CLIENTS.STATUS row (mysqli assoc) to the JSON shape the console uses.
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
	];
}

// Increment the OS breakdown counter for a platform; unknown platforms are
// ignored so the three known buckets always sum to the reported count.
function luminum_platform_tally(&$platforms, $platform) {
	$key = strtolower($platform);
	if (isset($platforms[$key])) { $platforms[$key]++; }
}
