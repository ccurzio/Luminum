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

// --- luminum_pci_class_category ---------------------------------------------
ok("VGA class maps to Display adapters", luminum_pci_class_category('0x030000') === 'Display adapters');
ok("Ethernet class maps to Network adapters", luminum_pci_class_category('0x020000') === 'Network adapters');
ok("wireless class joins Network adapters", luminum_pci_class_category('0x0d0000') === 'Network adapters');
ok("USB host controller gets its own category", luminum_pci_class_category('0x0c0330') === 'USB controllers');
ok("other serial bus stays Serial bus controllers", luminum_pci_class_category('0x0c0000') === 'Serial bus controllers');
ok("NVM storage maps to Storage controllers", luminum_pci_class_category('0x010802') === 'Storage controllers');
ok("host bridge maps to System devices", luminum_pci_class_category('0x060000') === 'System devices');
ok("bare hex (no 0x) accepted", luminum_pci_class_category('060400') === 'System devices');
ok("unknown base class maps to Other devices", luminum_pci_class_category('0x000000') === 'Other devices');
ok("0xff base maps to Other devices", luminum_pci_class_category('0xff0000') === 'Other devices');
ok("garbage class maps to Other devices", luminum_pci_class_category('nope') === 'Other devices');
ok("empty class maps to Other devices", luminum_pci_class_category('') === 'Other devices');

// --- luminum_pci_vendor_name --------------------------------------------------
ok("Intel vendor name", luminum_pci_vendor_name('0x8086') === 'Intel');
ok("NVIDIA vendor name", luminum_pci_vendor_name('0x10de') === 'NVIDIA');
ok("AMD vendor name (device id form)", luminum_pci_vendor_name('0x1022') === 'Advanced Micro Devices');
ok("MediaTek second vendor ID", luminum_pci_vendor_name('0x14c3') === 'MediaTek');
ok("Realtek second vendor ID", luminum_pci_vendor_name('0x10ec') === 'Realtek');
ok("bare hex (no 0x) accepted", luminum_pci_vendor_name('8086') === 'Intel');
ok("unknown vendor reports its raw ID", luminum_pci_vendor_name('0x1234') === 'Vendor 0x1234');
ok("garbage vendor is Unknown vendor", luminum_pci_vendor_name('zz') === 'Unknown vendor');

// --- luminum_devices_build ----------------------------------------------------
$pcifix = "0000:00:00.0|0x060000|0x8086|0x7d29|\n"
    . "0000:00:02.0|0x030000|0x8086|0x7d67|i915\n"
    . "0000:00:0d.0|0x0c0330|0x8086|0x7ec0|xhci_hcd\n"
    . "0000:00:1f.6|0x020000|0x8086|0x15d8|igc\n"
    . "badline\n"
    . "zzzz:00:00.0|0x030000|0x8086|0x7d67|\n";
$usbfix = "3-14|0489|e0e2|MediaTek Inc.|Wireless_Device\n"
    . "3-7|05e3|0608||USB2.0 Hub\n"
    . "3-9|1234|5678||\n";
$tree = luminum_devices_build($pcifix, $usbfix, 'Intel(R) Xeon(R) CPU E5-2680 v4', '8');
$keys = array_keys($tree);
ok("fixed categories keep their order", $keys === ['Processors', 'Display adapters', 'Network adapters', 'USB controllers', 'USB devices', 'System devices'], json_encode($keys));
ok("processor entry carries the model and core count", $tree['Processors'][0]['label'] === 'Intel(R) Xeon(R) CPU E5-2680 v4 (8 cores)', json_encode($tree['Processors'][0]));
ok("single core reads 'core'", luminum_devices_build('', '', 'Test CPU', '1')['Processors'][0]['label'] === 'Test CPU (1 core)');
ok("display adapter labeled with vendor name and IDs", $tree['Display adapters'][0]['label'] === 'Intel 0x8086:0x7d67', json_encode($tree['Display adapters'][0]));
ok("display adapter detail carries address and driver", $tree['Display adapters'][0]['detail'] === '0000:00:02.0 - driver: i915');
ok("bridge without a driver has no driver note", $tree['System devices'][0]['detail'] === '0000:00:00.0');
ok("USB controller classified separately from other serial bus", isset($tree['USB controllers']) && !isset($tree['Serial bus controllers']));
ok("network adapter labeled", $tree['Network adapters'][0]['label'] === 'Intel 0x8086:0x15d8');
ok("USB device labeled manufacturer + product", $tree['USB devices'][0]['label'] === 'MediaTek Inc. Wireless_Device', json_encode($tree['USB devices'][0]));
ok("USB device detail carries IDs and bus", $tree['USB devices'][0]['detail'] === '0x0489:0xe0e2 - bus 3-14');
ok("USB device without manufacturer falls back to product", $tree['USB devices'][1]['label'] === 'USB2.0 Hub');
ok("USB device without names falls back to IDs", $tree['USB devices'][2]['label'] === 'USB device 0x1234:0x5678');
ok("malformed PCI lines are skipped", count($tree['Display adapters']) === 1 && count($tree['System devices']) === 1);
ok("empty input with a CPU yields only Processors", array_keys(luminum_devices_build('', '', 'CPU X', '4')) === ['Processors']);
ok("empty input with no CPU yields no categories", luminum_devices_build('', '', '', '') === []);
ok("empty input with a null CPU yields no categories", luminum_devices_build(null, null, null, null) === []);
$tree2 = luminum_devices_build("0000:00:00.0|0x000000|0x8086|0x7d29|\n0000:00:01.0|0x050000|0x8086|0xae7f|\n", '', '', '');
$keys2 = array_keys($tree2);
ok("remaining categories sort alphabetically with Other devices last", $keys2 === ['Memory controllers', 'Other devices'], json_encode($keys2));

echo "------------------------------------------------------------\n";
if ($failures > 0) {
    echo "FAILED: $failures check(s) failed\n";
    exit(1);
}
echo "All checks passed.\n";
exit(0);
