<?php
//
// console_sensor_test.php - offline test harness for the sensor create
// form helpers in server/console/html/admin/sensormap.php.
//
// Usage: php tests/console_sensor_test.php
// Exit code: 0 if all checks pass, 1 otherwise.

require_once __DIR__ . '/../server/console/html/admin/sensormap.php';

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

// A minimal valid POST: Linux shell sensor, no options.
function base_post() {
    return [
        'pkgname' => 'Disk Usage',
        'pkgdesc' => 'Report disk usage for the root volume',
        'timeout' => '30',
        'tint' => 'sec',
        'rtype' => 'text',
        'contentset' => '1',
        'category' => 'none',
        'leselect' => 'on',
        'lstype' => 'shell',
        'lscript' => "#!/bin/sh\ndf -h /\n",
    ];
}

// --- luminum_sensor_os_types -------------------------------------------------
ok("linux types are shell/perl/python", luminum_sensor_os_types('linux') === ['shell', 'perl', 'python']);
ok("macos types are shell/perl/python", luminum_sensor_os_types('macos') === ['shell', 'perl', 'python']);
ok("windows types are powershell/vbscript/batch/python", luminum_sensor_os_types('windows') === ['powershell', 'vbscript', 'batch', 'python']);
ok("unknown platform has no types", luminum_sensor_os_types('amiga') === []);

// --- luminum_validate_sensor_create: happy path ------------------------------
$v = luminum_validate_sensor_create(base_post());
ok("valid POST accepted", $v['ok'] === true, json_encode($v));
$s = $v['sensor'] ?? [];
ok("name normalized", ($s['NAME'] ?? '') === 'Disk Usage');
ok("description normalized", ($s['DESCRIPTION'] ?? '') === 'Report disk usage for the root volume');
ok("timeout is 30S", ($s['TIMEOUT'] ?? '') === '30S');
ok("rtype stored", ($s['RTYPE'] ?? '') === 'text');
ok("cset is int 1", ($s['CSET'] ?? null) === 1);
ok("category none is null", array_key_exists('CATEGORY', $s) && $s['CATEGORY'] === null);
ok("linux type stored", ($s['LSTYPE'] ?? '') === 'shell');
ok("linux script stored verbatim", ($s['LSCRIPT'] ?? '') === "#!/bin/sh\ndf -h /\n");
ok("disabled macos stores null type", array_key_exists('MSTYPE', $s) && $s['MSTYPE'] === null);
ok("disabled macos stores null script", array_key_exists('MSCRIPT', $s) && $s['MSCRIPT'] === null);
ok("disabled windows stores null type", array_key_exists('WSTYPE', $s) && $s['WSTYPE'] === null);
ok("disabled windows stores null script", array_key_exists('WSCRIPT', $s) && $s['WSCRIPT'] === null);
ok("usecase defaults off", ($s['USECASE'] ?? 1) === 0);
ok("csplit defaults off", ($s['CSPLIT'] ?? 1) === 0);
ok("delimiter null when unsplit", array_key_exists('DELIMITER', $s) && $s['DELIMITER'] === null);
ok("withparams defaults off", ($s['WITHPARAMS'] ?? 1) === 0);

// --- timeout unit + range ----------------------------------------------------
$p = base_post(); $p['tint'] = 'min';
$v = luminum_validate_sensor_create($p);
ok("minute unit produces 2M-style value", $v['ok'] && $v['sensor']['TIMEOUT'] === '30M');

foreach (['0', '007', '1000', 'abc', ''] as $bad) {
    $p = base_post(); $p['timeout'] = $bad;
    $v = luminum_validate_sensor_create($p);
    ok("timeout '$bad' rejected", $v['ok'] === false && $v['err'] === 'timeout');
}
$p = base_post(); $p['tint'] = 'hour';
$v = luminum_validate_sensor_create($p);
ok("unknown timeout unit rejected", $v['ok'] === false && $v['err'] === 'timeout');

// --- luminum_sensor_timeout_parts (edit form pre-fill) -----------------------
ok("30S splits to 30/sec", luminum_sensor_timeout_parts('30S') === ['num' => '30', 'unit' => 'sec']);
ok("2M splits to 2/min", luminum_sensor_timeout_parts('2M') === ['num' => '2', 'unit' => 'min']);
ok("999M splits to 999/min", luminum_sensor_timeout_parts('999M') === ['num' => '999', 'unit' => 'min']);
foreach (['', '0S', '0M', '1000S', '30X', '30', 'S', '30S ', ' 30S', '30s', null, 30] as $bad) {
    ok("timeout " . var_export($bad, true) . " rejected", luminum_sensor_timeout_parts($bad) === null);
}

// --- name validation ---------------------------------------------------------
foreach (['', '   ', 'bad/name', "-leading", '9'.str_repeat('x', 128)] as $bad) {
    $p = base_post(); $p['pkgname'] = $bad;
    $v = luminum_validate_sensor_create($p);
    ok("name " . var_export($bad, true) . " rejected", $v['ok'] === false && $v['err'] === 'name');
}
$p = base_post(); $p['pkgname'] = '  Disk Usage  ';
$v = luminum_validate_sensor_create($p);
ok("name is trimmed", $v['ok'] && $v['sensor']['NAME'] === 'Disk Usage');
$p = base_post(); $p['pkgname'] = 'a_b-c.d e5';
$v = luminum_validate_sensor_create($p);
ok("name with underscore/dash/dot/space accepted", $v['ok'] === true);

// --- description validation --------------------------------------------------
foreach (['', str_repeat('x', 129)] as $bad) {
    $p = base_post(); $p['pkgdesc'] = $bad;
    $v = luminum_validate_sensor_create($p);
    ok("desc " . strlen($bad) . " chars rejected", $v['ok'] === false && $v['err'] === 'desc');
}

// --- rtype / cset / category -------------------------------------------------
$p = base_post(); $p['rtype'] = 'boolean';
$v = luminum_validate_sensor_create($p);
ok("unknown rtype rejected", $v['ok'] === false && $v['err'] === 'rtype');

foreach (['', '0', 'abc', '-1'] as $bad) {
    $p = base_post(); $p['contentset'] = $bad;
    $v = luminum_validate_sensor_create($p);
    ok("contentset '$bad' rejected", $v['ok'] === false && $v['err'] === 'cset');
}
$p = base_post(); $p['category'] = 'abc';
$v = luminum_validate_sensor_create($p);
ok("non-numeric category rejected", $v['ok'] === false && $v['err'] === 'category');
$p = base_post(); $p['category'] = '7';
$v = luminum_validate_sensor_create($p);
ok("numeric category stored as int", $v['ok'] && $v['sensor']['CATEGORY'] === 7);

// --- split / delimiter -------------------------------------------------------
$p = base_post(); $p['split'] = 'on'; $p['delimeter'] = '|';
$v = luminum_validate_sensor_create($p);
ok("split with one-char delimiter accepted", $v['ok'] && $v['sensor']['CSPLIT'] === 1 && $v['sensor']['DELIMITER'] === '|');
$p = base_post(); $p['split'] = 'on'; $p['delimeter'] = 'ab';
$v = luminum_validate_sensor_create($p);
ok("multi-char delimiter rejected", $v['ok'] === false && $v['err'] === 'delimiter');
$p = base_post(); $p['split'] = 'on';
$v = luminum_validate_sensor_create($p);
ok("split without delimiter rejected", $v['ok'] === false && $v['err'] === 'delimiter');

// --- options -----------------------------------------------------------------
$p = base_post(); $p['case'] = 'on'; $p['useparams'] = 'on';
$v = luminum_validate_sensor_create($p);
ok("case + params checkboxes stored", $v['ok'] && $v['sensor']['USECASE'] === 1 && $v['sensor']['WITHPARAMS'] === 1);

// --- per-OS scripts ----------------------------------------------------------
$p = base_post();
unset($p['leselect']);
$v = luminum_validate_sensor_create($p);
ok("no platform enabled rejected", $v['ok'] === false && $v['err'] === 'os');

$p = base_post(); $p['lscript'] = '   ';
$v = luminum_validate_sensor_create($p);
ok("whitespace-only script rejected", $v['ok'] === false && $v['err'] === 'os');

$p = base_post(); $p['lstype'] = 'powershell';
$v = luminum_validate_sensor_create($p);
ok("powershell is not a linux type", $v['ok'] === false && $v['err'] === 'os');

$p = base_post(); $p['lscript'] = str_repeat('x', LUMINUM_SENSOR_SCRIPT_MAX + 1);
$v = luminum_validate_sensor_create($p);
ok("oversized script rejected", $v['ok'] === false && $v['err'] === 'os');

$p = base_post(); $p['lscript'] = str_repeat('x', LUMINUM_SENSOR_SCRIPT_MAX);
$v = luminum_validate_sensor_create($p);
ok("script at the size cap accepted", $v['ok'] === true);

// All three platforms at once.
$p = base_post();
$p['meselect'] = 'on'; $p['mstype'] = 'python'; $p['mscript'] = "#!/usr/local/bin/python3\nprint(1)\n";
$p['weselect'] = 'on'; $p['wstype'] = 'powershell'; $p['wscript'] = "Get-Volume\n";
$v = luminum_validate_sensor_create($p);
ok("all three platforms accepted", $v['ok'] === true);
if ($v['ok']) {
    ok("macos script stored", $v['sensor']['MSTYPE'] === 'python' && $v['sensor']['MSCRIPT'] === "#!/usr/local/bin/python3\nprint(1)\n");
    ok("windows script stored", $v['sensor']['WSTYPE'] === 'powershell' && $v['sensor']['WSCRIPT'] === "Get-Volume\n");
}

// Enabled platform with a missing script field (the hidden input absent).
$p = base_post(); unset($p['lscript']);
$v = luminum_validate_sensor_create($p);
ok("enabled platform without script field rejected", $v['ok'] === false && $v['err'] === 'os');

// --- line-ending normalization -----------------------------------------------
// A script pasted from a Windows editor carries \r\n; the client runs it on
// the interpreter's stdin, where a stray \r breaks shell scripts.
$p = base_post(); $p['lscript'] = "#!/bin/sh\r\nif true; then\r\necho hi\r\nfi\r\n";
$v = luminum_validate_sensor_create($p);
ok("CRLF script accepted", $v['ok'] === true, json_encode($v));
ok("CRLF script stored with LF endings", ($v['sensor']['LSCRIPT'] ?? '') === "#!/bin/sh\nif true; then\necho hi\nfi\n", var_export($v['sensor']['LSCRIPT'] ?? null, true));

$p = base_post(); $p['lscript'] = "echo a\recho b\r";
$v = luminum_validate_sensor_create($p);
ok("lone CR script normalized to LF", $v['ok'] && $v['sensor']['LSCRIPT'] === "echo a\necho b\n");

$p = base_post();
$p['meselect'] = 'on'; $p['mstype'] = 'shell'; $p['mscript'] = "echo mac\r\n";
$p['weselect'] = 'on'; $p['wstype'] = 'powershell'; $p['wscript'] = "Get-Date\r\n";
$v = luminum_validate_sensor_create($p);
ok("macos and windows scripts normalized too", $v['ok'] && $v['sensor']['MSCRIPT'] === "echo mac\n" && $v['sensor']['WSCRIPT'] === "Get-Date\n");

// --- malformed input shapes --------------------------------------------------
$v = luminum_validate_sensor_create(null);
ok("null POST rejected", $v['ok'] === false);
$p = base_post(); $p['pkgname'] = ['evil'];
$v = luminum_validate_sensor_create($p);
ok("array field rejected", $v['ok'] === false && $v['err'] === 'name');

// --- error messages ----------------------------------------------------------
foreach (['name', 'desc', 'timeout', 'rtype', 'cset', 'category', 'delimiter', 'os', 'dupname', 'save'] as $code) {
    $msg = luminum_sensor_error_message($code);
    ok("error message for '$code' is non-empty", is_string($msg) && $msg !== '');
}
ok("unknown error code falls back to a generic message", luminum_sensor_error_message('???') === 'The sensor could not be saved.');

echo "------------------------------------------------------------\n";
if ($failures > 0) {
    echo "FAILED: $failures check(s) failed\n";
    exit(1);
}
echo "All checks passed.\n";
exit(0);
