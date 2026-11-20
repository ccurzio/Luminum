<?php
//
// console_sysinfo_test.php - offline test harness for the System
// Information helpers in server/console/html/system/sysinfomap.php.
//
// Usage: php tests/console_sysinfo_test.php
// Exit code: 0 if all checks pass, 1 otherwise.

require_once __DIR__ . '/../server/console/html/system/sysinfomap.php';

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

$allzero = ['MemTotal' => 0, 'MemFree' => 0, 'MemAvailable' => 0, 'SwapTotal' => 0, 'SwapFree' => 0];

// --- luminum_meminfo_parse ---------------------------------------------------
$mi = luminum_meminfo_parse("MemTotal:       32115080 kB\n"
    . "MemFree:          370212 kB\n"
    . "Buffers:            7448 kB\n"
    . "Cached:         26792032 kB\n"
    . "SwapCached:       582280 kB\n"
    . "MemAvailable:   25600232 kB\n"
    . "SwapTotal:      32789500 kB\n"
    . "SwapFree:       25556536 kB\n"
    . "HugePages_Total:       0\n");
ok("MemTotal parsed", $mi['MemTotal'] === 32115080, json_encode($mi));
ok("MemFree parsed", $mi['MemFree'] === 370212);
ok("MemAvailable parsed", $mi['MemAvailable'] === 25600232);
ok("SwapTotal parsed", $mi['SwapTotal'] === 32789500);
ok("SwapFree parsed", $mi['SwapFree'] === 25556536);
ok("unused fields are not returned", !array_key_exists('Cached', $mi) && !array_key_exists('Buffers', $mi));
ok("non-kB lines are ignored", luminum_meminfo_parse("HugePages_Total:       0\n") === $allzero);
ok("empty input reads all zero", luminum_meminfo_parse("") === $allzero);
ok("null input reads all zero", luminum_meminfo_parse(null) === $allzero);
ok("partial input keeps the rest zero", luminum_meminfo_parse("MemTotal: 1024 kB\n") === ['MemTotal' => 1024, 'MemFree' => 0, 'MemAvailable' => 0, 'SwapTotal' => 0, 'SwapFree' => 0]);
ok("CRLF line endings tolerated", luminum_meminfo_parse("MemTotal: 2048 kB\r\nMemFree: 512 kB\r\n")['MemTotal'] === 2048);

// --- luminum_mem_kb_human ----------------------------------------------------
ok("0 is 0 KB", luminum_mem_kb_human(0) === "0 KB", luminum_mem_kb_human(0));
ok("512 stays KB", luminum_mem_kb_human(512) === "512 KB", luminum_mem_kb_human(512));
ok("1024 kB is 1 MB", luminum_mem_kb_human(1024) === "1 MB", luminum_mem_kb_human(1024));
ok("370212 kB is 361.5 MB", luminum_mem_kb_human(370212) === "361.5 MB", luminum_mem_kb_human(370212));
ok("32115080 kB is 30.6 GB", luminum_mem_kb_human(32115080) === "30.6 GB", luminum_mem_kb_human(32115080));
ok("whole GB drops the decimal", luminum_mem_kb_human(1073741824) === "1 TB", luminum_mem_kb_human(1073741824));
ok("1024 GB is 1 TB", luminum_mem_kb_human(1024 * 1048576) === "1 TB", luminum_mem_kb_human(1024 * 1048576));
ok("negative clamps to 0 KB", luminum_mem_kb_human(-5) === "0 KB", luminum_mem_kb_human(-5));
ok("non-numeric clamps to 0 KB", luminum_mem_kb_human("abc") === "0 KB", luminum_mem_kb_human("abc"));
ok("string number accepted", luminum_mem_kb_human("2048") === "2 MB", luminum_mem_kb_human("2048"));

// --- luminum_mem_dmidecode_slots ----------------------------------------------
$fixture = "# dmidecode 3.6\n"
    . "Getting SMBIOS data from sysfs.\n"
    . "SMBIOS 3.2.0 present.\n"
    . "\n"
    . "Memory Device\n"
    . "    Array Handle: 0x000E\n"
    . "    Error Information Handle: 0x8000\n"
    . "    Total Width: 64 bits\n"
    . "    Data Width: 64 bits\n"
    . "    Size: 16 GB\n"
    . "    Form Factor: DIMM\n"
    . "    Set: None\n"
    . "    Locator: P0_DIMM0\n"
    . "    Bank Locator: P0 Channel A\n"
    . "    Type: DDR4\n"
    . "    Type Detail: Synchronous\n"
    . "    Speed: 3200 MT/s\n"
    . "    Manufacturer: Samsung\n"
    . "    Part Number: M393A2K40DB3-CWE\n"
    . "    Serial Number: 00000000\n"
    . "    Asset Tag: 987654321\n"
    . "\n"
    . "Memory Device\n"
    . "    Array Handle: 0x000E\n"
    . "    Error Information Handle: 0x8000\n"
    . "    Total Width: Unknown\n"
    . "    Data Width: Unknown\n"
    . "    Size: No Module Installed\n"
    . "    Form Factor: DIMM\n"
    . "    Set: None\n"
    . "    Locator: P0_DIMM1\n"
    . "    Bank Locator: P0 Channel B\n"
    . "    Type: DDR4\n"
    . "    Speed: Unknown\n"
    . "    Manufacturer: Not Specified\n"
    . "    Part Number: Not Specified\n";
$slots = luminum_mem_dmidecode_slots($fixture);
ok("two slots parsed", count($slots) === 2, json_encode($slots));
ok("slot 1 is installed", ($slots[0]['installed'] ?? null) === true);
ok("slot 1 size", ($slots[0]['Size'] ?? '') === '16 GB');
ok("slot 1 form factor", ($slots[0]['Form Factor'] ?? '') === 'DIMM');
ok("slot 1 locator", ($slots[0]['Locator'] ?? '') === 'P0_DIMM0');
ok("slot 1 bank locator", ($slots[0]['Bank Locator'] ?? '') === 'P0 Channel A');
ok("slot 1 type", ($slots[0]['Type'] ?? '') === 'DDR4');
ok("slot 1 speed", ($slots[0]['Speed'] ?? '') === '3200 MT/s');
ok("slot 1 manufacturer", ($slots[0]['Manufacturer'] ?? '') === 'Samsung');
ok("slot 1 part number", ($slots[0]['Part Number'] ?? '') === 'M393A2K40DB3-CWE');
ok("slot 2 is empty", ($slots[1]['installed'] ?? null) === false);
ok("slot 2 locator", ($slots[1]['Locator'] ?? '') === 'P0_DIMM1');
ok("empty input has no slots", luminum_mem_dmidecode_slots("") === []);
ok("null input has no slots", luminum_mem_dmidecode_slots(null) === []);
ok("error output has no slots", luminum_mem_dmidecode_slots("Scanning /dev/mem for entry point.\nCan't read memory from /dev/mem") === []);
ok("header-only output has no slots", luminum_mem_dmidecode_slots("# dmidecode 3.6\nGetting SMBIOS data from sysfs.\nSMBIOS 3.2.0 present.\n") === []);
ok("slot with no Size field is empty", luminum_mem_dmidecode_slots("Memory Device\n    Locator: X1\n") === [['installed' => false, 'Size' => '', 'Form Factor' => '', 'Locator' => 'X1', 'Bank Locator' => '', 'Type' => '', 'Speed' => '', 'Manufacturer' => '', 'Part Number' => '']]);
ok("value containing a colon is kept whole", luminum_mem_dmidecode_slots("Memory Device\n    Size: 8 GB\n    Part Number: ABC:123\n") === [['installed' => true, 'Size' => '8 GB', 'Form Factor' => '', 'Locator' => '', 'Bank Locator' => '', 'Type' => '', 'Speed' => '', 'Manufacturer' => '', 'Part Number' => 'ABC:123']]);

echo "------------------------------------------------------------\n";
if ($failures > 0) {
    echo "FAILED: $failures check(s) failed\n";
    exit(1);
}
echo "All checks passed.\n";
exit(0);
