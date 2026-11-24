//
// console_table_test.js - offline test harness for the UMD table module
// in server/console/html/layout/table.js (escapeHTML, headerHTML, rowHTML,
// rowsHTML, filterRows).
//
// Usage: node tests/console_table_test.js
// Exit code: 0 if all checks pass, 1 otherwise.

const path = require("path");
const LT = require(path.join(__dirname, "..", "server", "console", "html", "layout", "table.js"));

let failures = 0;
function ok(name, cond, detail) {
	if (cond) {
		console.log("ok   - " + name);
	} else {
		failures++;
		console.log("FAIL - " + name + (detail !== undefined ? " (" + detail + ")" : ""));
	}
}

const rows = [
	{ id: 1, hostname: "web-01", ip: "172.16.0.10", os: "Debian 12.10", platform: "linux" },
	{ id: 2, hostname: "mac-01", ip: "172.16.0.11", os: "macOS 15.1", platform: "macos" },
];
const plain = [
	{ label: "Hostname", key: "hostname" },
	{ label: "IP", key: "ip", width: "125px", align: "center" },
];
const cfg = { columns: plain, searchKeys: ["hostname", "ip", "os"] };

// --- escapeHTML -------------------------------------------------------------
ok("escapeHTML: null/undefined -> empty string",
	LT.escapeHTML(null) === "" && LT.escapeHTML(undefined) === "");
ok("escapeHTML: numbers stringified", LT.escapeHTML(42) === "42");
ok("escapeHTML: escapes & < > ' \"",
	LT.escapeHTML('a&b<c>d"e\'f') === "a&amp;b&lt;c&gt;d&quot;e&#39;f",
	LT.escapeHTML('a&b<c>d"e\'f'));

// --- headerHTML -------------------------------------------------------------
// The header row carries the luminum-head class (the console's header-row
// marker: the darker tone in default.css, and the sort-click target row for
// LuminumTable.attachHeaderSort).
ok("headerHTML: plain label, no style attr",
	LT.headerHTML({ columns: [plain[0]] }) === '<tr class="luminum-head"><td>Hostname</td></tr>',
	LT.headerHTML({ columns: [plain[0]] }));
ok("headerHTML: width + align in style",
	LT.headerHTML({ columns: [plain[1]] }) === '<tr class="luminum-head"><td style="width: 125px;text-align: center;">IP</td></tr>',
	LT.headerHTML({ columns: [plain[1]] }));
ok("headerHTML: custom header used raw",
	LT.headerHTML({ columns: [{ label: "OS", header: 'Operating <em>System</em>' }] }) ===
		'<tr class="luminum-head"><td>Operating <em>System</em></td></tr>');

// A config with a sub-labeled column (the query results page's CSPLIT
// sensor): the header is two tiers, the rows span one <tr> per sub-row.
const subCfg = {
	columns: [
		{ type: "checkbox", width: "15px", inputClass: "qrrow", idPrefix: "ID", header: '<input id="qrselectall" type="checkbox">' },
		{ label: "Computer Name", key: "s7", whiteSpace: "pre-wrap" },
		{ label: "Installed Applications", key: "s9", sub: ["Name", "Version"], whiteSpace: "pre-wrap" },
		{ label: "Count", key: "count", width: "60px", align: "center" }
	],
	searchKeys: ["s7", "s9"]
};
const subRow = {
	id: 4, count: 2, s7: "host-1",
	s9_0_0: "App One", s9_0_1: "1.0.1",
	s9_1_0: "App Two", s9_1_1: "2.0",
	span: 2
};

// --- physicalColumns --------------------------------------------------------
ok("physicalColumns: a plain config expands to itself",
	LT.physicalColumns(cfg).length === 2 &&
		LT.physicalColumns(cfg).every((p, i) => p.subIndex === null && p.col === cfg.columns[i]));
ok("physicalColumns: a sub column expands to one physical column per sub-label",
	LT.physicalColumns(subCfg).length === 5 &&
		LT.physicalColumns(subCfg)[2].subIndex === 0 &&
		LT.physicalColumns(subCfg)[2].label === "Name" &&
		LT.physicalColumns(subCfg)[3].subIndex === 1 &&
		LT.physicalColumns(subCfg)[3].label === "Version");

// --- headerHTML: two tiers --------------------------------------------------
const twoTier = LT.headerHTML(subCfg);
ok("headerHTML: two tiers when a column carries sub-labels",
	(twoTier.match(/<tr[ >]/g) || []).length === 2, twoTier);
ok("headerHTML: the sub column's label spans its sub-columns",
	twoTier.indexOf('<td colspan="2">Installed Applications</td>') !== -1, twoTier);
ok("headerHTML: the sub-labels sit in the second tier",
	/<tr class="luminum-head"><td>Name<\/td><td>Version<\/td><\/tr>/.test(twoTier), twoTier);
ok("headerHTML: the other columns span both tiers",
	twoTier.indexOf('rowspan="2"') !== -1 && (twoTier.match(/rowspan="2"/g) || []).length === 3, twoTier);
ok("headerHTML: the checkbox header keeps its raw HTML",
	twoTier.indexOf('id="qrselectall"') !== -1, twoTier);
ok("headerHTML: a plain config stays a single tier",
	(LT.headerHTML(cfg).match(/<tr[ >]/g) || []).length === 1);

// --- colgroupHTML -----------------------------------------------------------
ok("colgroupHTML: checkbox column pinned to the fixed width",
	LT.colgroupHTML({ columns: [{ type: "checkbox" }, { label: "Name", key: "name" }] }) ===
		'<colgroup><col style="width: 32px;"><col></colgroup>',
	LT.colgroupHTML({ columns: [{ type: "checkbox" }, { label: "Name", key: "name" }] }));
ok("colgroupHTML: a width column keeps its width",
	LT.colgroupHTML({ columns: [{ label: "IP", key: "ip", width: "125px" }] }) ===
		'<colgroup><col style="width: 125px;"></colgroup>',
	LT.colgroupHTML({ columns: [{ label: "IP", key: "ip", width: "125px" }] }));
ok("colgroupHTML: a column without a width is flexible (bare <col>)",
	LT.colgroupHTML({ columns: [{ label: "A", key: "a" }, { label: "B", key: "b", width: "60px" }, { label: "C", key: "c" }] }) ===
		'<colgroup><col><col style="width: 60px;"><col></colgroup>',
	LT.colgroupHTML({ columns: [{ label: "A", key: "a" }, { label: "B", key: "b", width: "60px" }, { label: "C", key: "c" }] }));
ok("colgroupHTML: sub-columns are flexible, the rest keep their widths",
	LT.colgroupHTML(subCfg) ===
		'<colgroup><col style="width: 32px;"><col><col><col><col style="width: 60px;"></colgroup>',
	LT.colgroupHTML(subCfg));

// --- rowHTML ----------------------------------------------------------------
const baseRow = LT.rowHTML(cfg, rows[0], {});
ok("rowHTML: tr carries luminum-row class + data-id",
	baseRow.startsWith('<tr class="luminum-row" data-id="1">'), baseRow);
ok("rowHTML: base background", baseRow.includes("background-color: #494a69"));
ok("rowHTML: values present", baseRow.includes("web-01") && baseRow.includes("172.16.0.10"));
ok("rowHTML: width/align applied",
	baseRow.includes("width: 125px") && baseRow.includes("text-align: center"));

const selRow = LT.rowHTML(cfg, rows[0], { selected: { 1: true } });
ok("rowHTML: selected background", selRow.includes("background-color: #686993"));

const cbCfg = { columns: [{ label: "Sel", key: "sel", type: "checkbox", idPrefix: "row" }] };
const cbRow = LT.rowHTML(cbCfg, rows[0], {});
ok("rowHTML: checkbox td id", cbRow.includes('id="1A"'), cbRow);
ok("rowHTML: checkbox class", cbRow.includes('class="row"'));
ok("rowHTML: checkbox input id from idPrefix", cbRow.includes('id="row1"'));
ok("rowHTML: checkbox data-id", cbRow.includes('data-id="1"'));
ok("rowHTML: checkbox unchecked by default",
	cbRow.includes('type="checkbox">') && !cbRow.includes("checked"));
const cbSel = LT.rowHTML(cbCfg, rows[0], { selected: { 1: true } });
ok("rowHTML: checkbox checked when selected", cbSel.includes('type="checkbox" checked'));

const rawCfg = { columns: [{ label: "HTML", key: "html", render: (r) => "<b>" + r.html + "</b>" }] };
const rawRow = LT.rowHTML(rawCfg, { id: 9, html: "x" }, {});
ok("rowHTML: render() output used raw",
	rawRow.includes('<td style="background-color: #494a69; font-weight: normal;"><b>x</b></td>'),
	rawRow);

const wsCfg = { columns: [{ label: "Output", key: "out", whiteSpace: "pre-wrap" }] };
const wsRow = LT.rowHTML(wsCfg, { id: 3, out: "a\nb" }, {});
ok("rowHTML: whiteSpace flag lands in the cell style",
	wsRow.includes('white-space: pre-wrap'), wsRow);
ok("rowHTML: a column without whiteSpace gets none",
	!baseRow.includes("white-space"));

// A row with sub values renders one <tr> per sub-row: the sub values fill
// the sub-columns line by line, and the checkbox, the plain column, and the
// Count span the <tr>s with rowspan.
const spanRow = LT.rowHTML(subCfg, subRow, {});
const spanTrs = spanRow.match(/<tr[^>]*>[\s\S]*?<\/tr>/g) || [];
ok("rowHTML: a span-2 row renders two <tr>s", spanTrs.length === 2, spanRow);
ok("rowHTML: only the first <tr> carries the row class + data-id",
	spanTrs[0].startsWith('<tr class="luminum-row" data-id="4">') &&
		spanTrs[1].startsWith("<tr>"), spanRow);
ok("rowHTML: the checkbox spans the sub-rows",
	spanRow.indexOf('rowspan="2" id="4A"') !== -1, spanRow);
ok("rowHTML: the plain column spans the sub-rows",
	spanRow.indexOf('<td rowspan="2" style="background-color: #494a69; font-weight: normal;white-space: pre-wrap;">host-1</td>') !== -1, spanRow);
ok("rowHTML: the Count cell spans the sub-rows",
	spanRow.indexOf('<td rowspan="2" style="background-color: #494a69; font-weight: normal;width: 60px;text-align: center;">2</td>') !== -1, spanRow);
ok("rowHTML: sub-row 0 carries line 0's segments",
	spanTrs[0].includes(">App One</td>") && spanTrs[0].includes(">1.0.1</td>"), spanRow);
ok("rowHTML: sub-row 1 carries line 1's segments",
	spanTrs[1].includes(">App Two</td>") && spanTrs[1].includes(">2.0</td>"), spanRow);
ok("rowHTML: a missing sub value renders an empty cell",
	LT.rowHTML(subCfg, { id: 5, count: 1, s7: "h", s9_0_0: "Only", span: 1 }, {})
		.includes(">Only</td><td style=\"background-color: #494a69; font-weight: normal;white-space: pre-wrap;\"></td>"));
ok("rowHTML: a span-1 row in a sub config renders a single <tr>",
	((LT.rowHTML(subCfg, { id: 6, count: 1, s7: "h", s9_0_0: "A", s9_0_1: "B", span: 1 }).match(/<tr[^>]*>/g) || []).length === 1));
ok("rowHTML: the selected background reaches every sub-row",
	((LT.rowHTML(subCfg, subRow, { selected: { 4: true } }).match(/<tr[^>]*>[\s\S]*?<\/tr>/g) || []))
		.every((t) => t.includes("background-color: #686993")));

// --- rowsHTML ---------------------------------------------------------------
const empty = LT.rowsHTML(cfg, [], {});
ok("rowsHTML: empty state colspan", empty.includes('colspan="2"'), empty);
ok("rowsHTML: default empty message", empty.includes("No Results"), empty);
const emptyCustom = LT.rowsHTML({ columns: plain, emptyMessage: "Nothing here" }, [], {});
ok("rowsHTML: custom empty message", emptyCustom.includes("Nothing here"), emptyCustom);
ok("rowsHTML: the empty state spans the physical columns",
	LT.rowsHTML(subCfg, [], {}).includes('colspan="5"'), LT.rowsHTML(subCfg, [], {}));
const all = LT.rowsHTML(cfg, rows, {});
ok("rowsHTML: joins rows with newline",
	all.split("\n").length === 2 && all.includes('data-id="1"') && all.includes('data-id="2"'));

// --- filterRows -------------------------------------------------------------
ok("filterRows: no state returns all",
	LT.filterRows(rows, cfg, {}).length === 2);
ok("filterRows: case-insensitive text",
	LT.filterRows(rows, cfg, { text: "WEB-01" }).length === 1 &&
		LT.filterRows(rows, cfg, { text: "web-01" })[0].id === 1);
ok("filterRows: matches any searchKey",
	LT.filterRows(rows, cfg, { text: "172.16.0.11" })[0].id === 2);
ok("filterRows: no match", LT.filterRows(rows, cfg, { text: "zzz" }).length === 0);

ok("filterRows: no platform checked keeps all",
	LT.filterRows(rows, cfg, { platforms: { linux: false, macos: false, windows: false } }).length === 2);
ok("filterRows: single platform",
	LT.filterRows(rows, cfg, { platforms: { linux: true, macos: false, windows: false } })
		.map((r) => r.id).join(",") === "1");
ok("filterRows: multiple platforms",
	LT.filterRows(rows, cfg, { platforms: { linux: true, macos: true, windows: false } }).length === 2);
ok("filterRows: text + platform intersect",
	LT.filterRows(rows, cfg, { text: "web", platforms: { linux: false, macos: true, windows: false } })
		.length === 0);
ok("filterRows: text + platform keep match",
	LT.filterRows(rows, cfg, { text: "mac", platforms: { linux: false, macos: true, windows: false } })
		.map((r) => r.id).join(",") === "2");

ok("filterRows: falls back to JSON.stringify without searchKeys",
	LT.filterRows(rows, { columns: plain }, { text: "debian" }).map((r) => r.id).join(",") === "1");

// --- stateBucket ------------------------------------------------------------
ok("stateBucket: OK -> green", LT.stateBucket("OK") === "green");
ok("stateBucket: WARN -> yellow", LT.stateBucket("WARN") === "yellow");
ok("stateBucket: OFFLINE -> offline", LT.stateBucket("OFFLINE") === "offline");
ok("stateBucket: CRIT -> red", LT.stateBucket("CRIT") === "red");
ok("stateBucket: DEACT -> red", LT.stateBucket("DEACT") === "red");
ok("stateBucket: unknown/null -> red",
	LT.stateBucket("nope") === "red" && LT.stateBucket(null) === "red");

// --- filterRows: status filter ----------------------------------------------
const srows = [
	{ id: 1, state: "OK" },
	{ id: 2, state: "WARN" },
	{ id: 3, state: "CRIT" },
	{ id: 4, state: "OFFLINE" },
];
const noStates = { green: false, yellow: false, red: false, offline: false };
ok("filterRows: no status checked keeps all",
	LT.filterRows(srows, cfg, { states: { ...noStates } }).length === 4);
ok("filterRows: single status (green)",
	LT.filterRows(srows, cfg, { states: { ...noStates, green: true } }).map((r) => r.id).join(",") === "1");
ok("filterRows: red catches the non-OK/WARN/OFFLINE states",
	LT.filterRows(srows, cfg, { states: { ...noStates, red: true } }).map((r) => r.id).join(",") === "3");
ok("filterRows: multiple statuses",
	LT.filterRows(srows, cfg, { states: { ...noStates, green: true, offline: true } })
		.map((r) => r.id).join(",") === "1,4");
ok("filterRows: status + platform intersect",
	LT.filterRows(rows, cfg, { states: { ...noStates, green: true }, platforms: { linux: false, macos: true, windows: false } }).length === 0);

// --- filterRows: check-in cutoff --------------------------------------------
const trows = [
	{ id: 1, lastseen_ts: 1000 },
	{ id: 2, lastseen_ts: 2000 },
	{ id: 3, lastseen_ts: 3000 },
	{ id: 4, lastseen_ts: null },
];
ok("filterRows: no cutoff keeps all (incl. null lastseen_ts)",
	LT.filterRows(trows, cfg, {}).length === 4);
ok("filterRows: cutoff drops rows checked in before it",
	LT.filterRows(trows, cfg, { checkin: { cutoff: 2500 } }).map((r) => r.id).join(",") === "3");
ok("filterRows: cutoff keeps rows checked in exactly at it",
	LT.filterRows(trows, cfg, { checkin: { cutoff: 2000 } }).map((r) => r.id).join(",") === "2,3");
ok("filterRows: cutoff drops rows with no lastseen_ts",
	LT.filterRows(trows, cfg, { checkin: { cutoff: 1 } }).map((r) => r.id).join(",") === "1,2,3");
ok("filterRows: cutoff + status + text combine",
	LT.filterRows(
		[{ id: 1, state: "OK", hostname: "a", lastseen_ts: 3000 }, { id: 2, state: "WARN", hostname: "b", lastseen_ts: 3000 }],
		cfg,
		{ checkin: { cutoff: 2500 }, states: { ...noStates, green: true }, text: "a" }
	).map((r) => r.id).join(",") === "1");

// --- filterRows: subset filter (client version) ------------------------------
const vrows = [
	{ id: 1, clientver: "0.0.1" },
	{ id: 2, clientver: "0.0.1" },
	{ id: 3, clientver: "0.0.2" },
	{ id: 4, clientver: "0.1.0" },
];
const noVers = {};
ok("filterRows: no subset keeps all",
	LT.filterRows(vrows, cfg, { subset: { field: "clientver", checked: noVers } }).length === 4);
ok("filterRows: subset with no value checked keeps all",
	LT.filterRows(vrows, cfg, { subset: { field: "clientver", checked: { "0.0.1": false } } }).length === 4);
ok("filterRows: single version checked",
	LT.filterRows(vrows, cfg, { subset: { field: "clientver", checked: { "0.0.2": true } } })
		.map((r) => r.id).join(",") === "3");
ok("filterRows: multiple versions checked",
	LT.filterRows(vrows, cfg, { subset: { field: "clientver", checked: { "0.0.1": true, "0.1.0": true } } })
		.map((r) => r.id).join(",") === "1,2,4");
ok("filterRows: unchecked values do not match",
	LT.filterRows(vrows, cfg, { subset: { field: "clientver", checked: { "0.0.1": true, "0.0.2": false } } })
		.map((r) => r.id).join(",") === "1,2");
ok("filterRows: subset + platform intersect",
	LT.filterRows(rows, cfg, { subset: { field: "platform", checked: { linux: true } }, platforms: { linux: false, macos: true, windows: false } }).length === 0);
ok("filterRows: subset + text + cutoff combine",
	LT.filterRows(
		[
			{ id: 1, clientver: "1.0", hostname: "aa", lastseen_ts: 3000 },
			{ id: 2, clientver: "1.0", hostname: "bb", lastseen_ts: 3000 },
			{ id: 3, clientver: "2.0", hostname: "aa", lastseen_ts: 3000 },
		],
		cfg,
		{ subset: { field: "clientver", checked: { "1.0": true } }, text: "aa", checkin: { cutoff: 2500 } }
	).map((r) => r.id).join(",") === "1");

// --- compareValues ----------------------------------------------------------
ok("compareValues: equal values are 0", LT.compareValues("abc", "abc") === 0);
ok("compareValues: case-insensitive text",
	LT.compareValues("Apple", "apple") === 0 &&
		LT.compareValues("Banana", "apple") > 0 &&
		LT.compareValues("apple", "Banana") < 0);
ok("compareValues: numbers compare numerically (2 < 10)",
	LT.compareValues("2", "10") < 0 && LT.compareValues("10", "2") > 0);
ok("compareValues: negative and decimal numbers",
	LT.compareValues("-5", "3") < 0 && LT.compareValues("1.5", "1.45") > 0);
ok("compareValues: a number and a non-number compare as text",
	LT.compareValues("10", "9x") < 0 && LT.compareValues("x10", "9") > 0);
ok("compareValues: IPv4 compares octet by octet (10.x < 192.x)",
	LT.compareValues("10.0.0.9", "192.168.1.2") < 0 &&
		LT.compareValues("192.168.1.2", "192.168.1.10") < 0 &&
		LT.compareValues("172.16.0.1", "172.16.0.1") === 0);
ok("compareValues: an IP and a non-IP compare as text",
	LT.compareValues("10.0.0.1", "10.0.0.1x") !== 0);
ok("compareValues: null/undefined sort as empty",
	LT.compareValues(null, "a") < 0 && LT.compareValues(undefined, undefined) === 0);
ok("compareValues: surrounding whitespace is ignored",
	LT.compareValues("  abc ", "abc") === 0);

// --- sortRows ---------------------------------------------------------------
const sortRows = [
	{ id: 1, hostname: "web-01", ip: "172.16.0.10" },
	{ id: 2, hostname: "alpha-02", ip: "10.0.0.5" },
	{ id: 3, hostname: "Alpha-01", ip: "192.168.1.20" },
];
const sortCfg = { columns: [
	{ label: "Hostname", key: "hostname" },
	{ label: "IP", key: "ip" },
] };
ok("sortRows: no sort returns the rows untouched",
	LT.sortRows(sortRows, sortCfg, null) === sortRows);
ok("sortRows: ascending text (case-insensitive)",
	LT.sortRows(sortRows, sortCfg, { col: 0, dir: 1 }).map((r) => r.id).join(",") === "3,2,1");
ok("sortRows: descending text",
	LT.sortRows(sortRows, sortCfg, { col: 0, dir: -1 }).map((r) => r.id).join(",") === "1,2,3");
ok("sortRows: IP column sorts octet by octet",
	LT.sortRows(sortRows, sortCfg, { col: 1, dir: 1 }).map((r) => r.id).join(",") === "2,1,3");
ok("sortRows: does not mutate the input",
	sortRows.map((r) => r.id).join(",") === "1,2,3");
ok("sortRows: ties keep their relative order",
	LT.sortRows(
		[{ id: 1, n: "a" }, { id: 2, n: "b" }, { id: 3, n: "a" }, { id: 4, n: "b" }],
		{ columns: [{ label: "N", key: "n" }] },
		{ col: 0, dir: 1 }
	).map((r) => r.id).join(",") === "1,3,2,4");
ok("sortRows: a column index past the config leaves the rows alone",
	LT.sortRows(sortRows, sortCfg, { col: 9, dir: 1 }).map((r) => r.id).join(",") === "1,2,3");

// A sub-column (the query results page's CSPLIT sensor): the physical index
// addresses the sub-column, and the sort key is the first line's segment.
const subSortRows = [
	{ id: 1, s9: "b-line", s9_0_0: "beta", s9_0_1: "2.0", s9_1_0: "x", s9_1_1: "1.0", span: 2 },
	{ id: 2, s9: "a-line", s9_0_0: "alpha", s9_0_1: "10.0", s9_1_0: "y", s9_1_1: "2.0", span: 2 },
	{ id: 3, s9: "c-line", s9_0_0: "Alpha", s9_0_1: "9.0", s9_1_0: "z", s9_1_1: "1.0", span: 2 },
];
ok("sortRows: a sub-column sorts by the first line's segment",
	LT.sortRows(subSortRows, subCfg, { col: 2, dir: 1 }).map((r) => r.id).join(",") === "2,3,1");
ok("sortRows: the sub-column's second sub-label sorts its own segments",
	LT.sortRows(subSortRows, subCfg, { col: 3, dir: 1 }).map((r) => r.id).join(",") === "1,3,2");
ok("sortRows: a sub-column descending (ties keep their input order)",
	LT.sortRows(subSortRows, subCfg, { col: 2, dir: -1 }).map((r) => r.id).join(",") === "1,2,3");
ok("sortRows: a plain column of a sub config still sorts by the row value",
	LT.sortRows(subSortRows, subCfg, { col: 1, dir: 1 }).map((r) => r.id).join(",") === "1,2,3");

console.log("-".repeat(60));
if (failures) {
	console.log("FAILED: " + failures + " check(s) failed");
	process.exit(1);
}
console.log("All checks passed.");
process.exit(0);
