<?php
//
// Shared bootstrap for the Luminum console: reads the console config and
// opens the MySQL connection. Paths are overridable via environment so the
// console can run under a non-standard install (e.g. the test harness); the
// defaults are the production locations.
//

if (!defined('LUMINUM_CONSOLE_CONF')) {
	define('LUMINUM_CONSOLE_CONF', getenv('LUMINUM_CONSOLE_CONF') ?: '/opt/Luminum/LuminumServer/config/console.conf');
}
if (!defined('LUMINUM_DB_SOCKET')) {
	define('LUMINUM_DB_SOCKET', getenv('LUMINUM_DB_SOCKET') ?: '/var/run/mysqld/mysqld.sock');
}
if (!defined('LUMINUM_DB_HOST')) {
	define('LUMINUM_DB_HOST', getenv('LUMINUM_DB_HOST') ?: 'localhost');
}

// Read a single key from the flat console.conf file.
function luminum_console_conf($key) {
	$cmd = '/usr/bin/grep ' . escapeshellarg($key) . ' ' . escapeshellarg(LUMINUM_CONSOLE_CONF)
		. " | /usr/bin/sed -e 's/^" . $key . ".*\\= //'";
	$out = trim((string)exec($cmd));
	return $out;
}

// Open (and cache) the MySQL connection. Throws mysqli_sql_exception on
// failure under PHP 8; callers decide how to surface that.
function luminum_db() {
	static $db = null;
	if ($db === null) {
		$db = new mysqli(
			LUMINUM_DB_HOST,
			luminum_console_conf('dbuser'),
			luminum_console_conf('dbpass'),
			'',
			0,
			LUMINUM_DB_SOCKET
		);
	}
	return $db;
}
