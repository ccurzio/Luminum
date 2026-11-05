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
ok("headerHTML: plain label, no style attr",
	LT.headerHTML({ columns: [plain[0]] }) === "<tr><td>Hostname</td></tr>",
	LT.headerHTML({ columns: [plain[0]] }));
ok("headerHTML: width + align in style",
	LT.headerHTML({ columns: [plain[1]] }) === '<tr><td style="width: 125px;text-align: center;">IP</td></tr>',
	LT.headerHTML({ columns: [plain[1]] }));
ok("headerHTML: custom header used raw",
	LT.headerHTML({ columns: [{ label: "OS", header: 'Operating <em>System</em>' }] }) ===
		"<tr><td>Operating <em>System</em></td></tr>");

// --- rowHTML ----------------------------------------------------------------
const baseRow = LT.rowHTML(cfg, rows[0], {});
ok("rowHTML: tr carries data-id", baseRow.startsWith('<tr data-id="1">'), baseRow);
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

// --- rowsHTML ---------------------------------------------------------------
const empty = LT.rowsHTML(cfg, [], {});
ok("rowsHTML: empty state colspan", empty.includes('colspan="2"'), empty);
ok("rowsHTML: default empty message", empty.includes("No Results"), empty);
const emptyCustom = LT.rowsHTML({ columns: plain, emptyMessage: "Nothing here" }, [], {});
ok("rowsHTML: custom empty message", emptyCustom.includes("Nothing here"), emptyCustom);
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

console.log("-".repeat(60));
if (failures) {
	console.log("FAILED: " + failures + " check(s) failed");
	process.exit(1);
}
console.log("All checks passed.");
process.exit(0);
