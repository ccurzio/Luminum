//
// console_queryresults_test.js - offline test for layout/queryresults.js,
// the results wiring of the query page's Results tab (modules/query.php).
//
// The pure functions (cellValue, pivotResults, buildConfig) are tested
// directly; the DOM helper (init) only runs in the browser.
//
// Usage: node tests/console_queryresults_test.js
// Exit code: 0 if all checks pass, 1 otherwise.

const fs = require("fs");
const path = require("path");
const Q = require(path.join(__dirname, "..", "server", "console", "html", "layout", "queryresults.js"));

let failures = 0;
function ok(name, cond, detail) {
	if (cond) {
		console.log("ok   - " + name);
	} else {
		failures++;
		console.log("FAIL - " + name + (detail !== undefined ? " (" + detail + ")" : ""));
	}
}
function eq(a, b) { return JSON.stringify(a) === JSON.stringify(b); }

// --- cellValue ---------------------------------------------------------------

ok("cell: OK renders the output", Q.cellValue({ status: "OK", output: "TRUE", err: null }) === "TRUE");
ok("cell: OK with a NULL output renders empty", Q.cellValue({ status: "OK", output: null, err: null }) === "");
ok("cell: ERR renders the error message", Q.cellValue({ status: "ERR", output: null, err: "UNKNOWN_SENSOR" }) === "UNKNOWN_SENSOR");
ok("cell: ERR without a message renders the status", Q.cellValue({ status: "ERR", output: null, err: null }) === "ERR");

// --- pivotResults --------------------------------------------------------------

// A result row for (uid, sensor) with the given answer.
function res(uid, sensor, status, output, err) {
	return { uid: uid, hostname: "host-" + uid, sensor: sensor, status: status, output: output, err: err };
}

// The motivating case: one sensor, 15 endpoints all answering TRUE -> a
// single row TRUE/15.
(function () {
	var results = [];
	for (var uid = 1; uid <= 15; uid++) { results.push(res(uid, 7, "OK", "TRUE", null)); }
	var rows = Q.pivotResults({ sensors: [{ sid: 7, name: "Is Windows" }], results: results });
	ok("pivot: 15 identical answers -> a single row", rows.length === 1);
	ok("pivot: the row carries the answer and the count", rows[0].s7 === "TRUE" && rows[0].count === 15);
})();

// 13 TRUE + 2 FALSE -> two rows: TRUE/13 and FALSE/2.
(function () {
	var results = [];
	for (var uid = 1; uid <= 13; uid++) { results.push(res(uid, 7, "OK", "TRUE", null)); }
	results.push(res(14, 7, "OK", "FALSE", null), res(15, 7, "OK", "FALSE", null));
	var rows = Q.pivotResults({ sensors: [{ sid: 7, name: "Is Windows" }], results: results });
	ok("pivot: 13 TRUE + 2 FALSE -> two rows", rows.length === 2);
	ok("pivot: the rows are TRUE/13 then FALSE/2 (first-appearance order)",
		rows[0].s7 === "TRUE" && rows[0].count === 13 && rows[1].s7 === "FALSE" && rows[1].count === 2);
})();

// All answers unique -> one row per answer, each counted 1.
(function () {
	var rows = Q.pivotResults({
		sensors: [{ sid: 7, name: "Is Windows" }],
		results: [res(1, 7, "OK", "TRUE", null), res(2, 7, "OK", "FALSE", null), res(3, 7, "OK", "MAYBE", null)]
	});
	ok("pivot: unique answers -> one row each, count 1",
		rows.length === 3 && rows.every(function (r) { return r.count === 1; }));
})();

// Two sensors: an answer is the whole row (every sensor column).
(function () {
	var rows = Q.pivotResults({
		sensors: [{ sid: 7, name: "Is Windows" }, { sid: 9, name: "CPU Load" }],
		results: [
			res(1, 7, "OK", "TRUE", null), res(1, 9, "OK", "1", null),
			res(2, 7, "OK", "TRUE", null), res(2, 9, "OK", "1", null),
			res(3, 7, "OK", "FALSE", null), res(3, 9, "OK", "2", null)
		]
	});
	ok("pivot: two sensors -> one row per unique full answer", rows.length === 2);
	ok("pivot: the shared full answer is TRUE/1 counted 2",
		rows[0].s7 === "TRUE" && rows[0].s9 === "1" && rows[0].count === 2);
	ok("pivot: the other full answer is FALSE/2 counted 1",
		rows[1].s7 === "FALSE" && rows[1].s9 === "2" && rows[1].count === 1);
})();

// Equal in one sensor column but not the other is a different answer.
(function () {
	var rows = Q.pivotResults({
		sensors: [{ sid: 7, name: "Is Windows" }, { sid: 9, name: "CPU Load" }],
		results: [
			res(1, 7, "OK", "TRUE", null), res(1, 9, "OK", "1", null),
			res(2, 7, "OK", "TRUE", null), res(2, 9, "OK", "2", null)
		]
	});
	ok("pivot: one column equal, the other not -> two rows",
		rows.length === 2 && rows.every(function (r) { return r.count === 1; }));
})();

// An endpoint that never answered a requested sensor gets an empty cell,
// which still takes part in the answer.
(function () {
	var rows = Q.pivotResults({
		sensors: [{ sid: 7, name: "Is Windows" }, { sid: 9, name: "CPU Load" }],
		results: [
			res(1, 7, "OK", "TRUE", null),
			res(2, 7, "OK", "TRUE", null), res(2, 9, "OK", "1", null),
			res(3, 7, "OK", "TRUE", null)
		]
	});
	ok("pivot: a missing sensor answer is an empty cell", rows[0].s9 === "");
	ok("pivot: the empty cell still takes part in the answer",
		rows.length === 2 && rows[0].count === 2 && rows[1].count === 1);
})();

// Error answers render the error message and group like any other answer.
(function () {
	var rows = Q.pivotResults({
		sensors: [{ sid: 7, name: "Is Windows" }, { sid: 9, name: "Mac Sensor" }],
		results: [
			res(1, 7, "OK", "TRUE", null), res(1, 9, "ERR", null, "UNKNOWN_SENSOR"),
			res(2, 7, "OK", "TRUE", null), res(2, 9, "ERR", null, "UNKNOWN_SENSOR")
		]
	});
	ok("pivot: an ERR answer renders the error in the cell", rows[0].s9 === "UNKNOWN_SENSOR");
	ok("pivot: two identical error answers share one row", rows.length === 1 && rows[0].count === 2);
})();

// No answers yet (the query is still in flight) -> no rows.
(function () {
	var rows = Q.pivotResults({ sensors: [{ sid: 7, name: "Is Windows" }], results: [] });
	ok("pivot: no answers -> no rows", rows.length === 0);
})();

// Answers that concatenate to the same string but differ per column must not
// collide (the signature's NUL separator).
(function () {
	var rows = Q.pivotResults({
		sensors: [{ sid: 7, name: "A" }, { sid: 9, name: "B" }],
		results: [
			res(1, 7, "OK", "TR", null), res(1, 9, "OK", "UE", null),
			res(2, 7, "OK", "T", null), res(2, 9, "OK", "RUE", null),
			res(3, 7, "OK", "TR", null), res(3, 9, "OK", "UE", null)
		]
	});
	ok("pivot: concatenated-equal answers do not collide",
		rows.length === 2 && rows[0].count === 2 && rows[1].count === 1);
})();

// Rows keep the order in which each answer first appeared.
(function () {
	var rows = Q.pivotResults({
		sensors: [{ sid: 7, name: "Is Windows" }, { sid: 9, name: "CPU Load" }],
		results: [
			res(2, 7, "OK", "A", null),
			res(1, 7, "OK", "B", null), res(1, 9, "OK", "1", null),
			res(2, 9, "OK", "2", null)
		]
	});
	ok("pivot: rows keep first-appearance order", rows[0].s7 === "A" && rows[1].s7 === "B");
})();

// --- buildConfig ----------------------------------------------------------------

(function () {
	var q = { sensors: [{ sid: 7, name: "Is Windows" }, { sid: 9, name: "CPU Load" }] };
	// A duplicate row (count 2) -> the Count column is present.
	var rows = [
		{ id: 0, count: 2, s7: "TRUE", s9: "1" },
		{ id: 1, count: 1, s7: "FALSE", s9: "2" },
		{ id: 2, count: 1, s7: "MAYBE", s9: "3" }
	];
	var cfg = Q.buildConfig(q, rows);
	ok("config: the first column is the select checkbox",
		cfg.columns[0].type === "checkbox" && cfg.columns[0].header.indexOf('id="qrselectall"') >= 0);
	ok("config: a duplicate row -> the sensors in query order, Count last",
		eq(cfg.columns.slice(1).map(function (c) { return c.label; }), ["Is Windows", "CPU Load", "Count"]));
	ok("config: the Count column is centered",
		cfg.columns[3].key === "count" && cfg.columns[3].align === "center");
	ok("config: the sensor columns pre-wrap multi-line output",
		cfg.columns[1].whiteSpace === "pre-wrap" && cfg.columns[2].whiteSpace === "pre-wrap");
	ok("config: the checkbox and Count columns are not pre-wrapped",
		!cfg.columns[0].whiteSpace && !cfg.columns[3].whiteSpace);
	ok("config: the filter searches the sensor cells, not the count",
		eq(cfg.searchKeys, ["s7", "s9"]));
	ok("config: rows present -> 'No Results' empty message", cfg.emptyMessage === "No Results");
})();

// The Count column appears only when at least one answer is shared by more
// than one endpoint (a duplicate row) - with all-unique answers every count
// would be 1 and the column carries nothing.
(function () {
	var q = { sensors: [{ sid: 7, name: "Is Windows" }] };
	var unique = [
		{ id: 0, count: 1, s7: "TRUE" },
		{ id: 1, count: 1, s7: "FALSE" }
	];
	var cfg = Q.buildConfig(q, unique);
	ok("config: all-unique answers -> no Count column",
		eq(cfg.columns.slice(1).map(function (c) { return c.label; }), ["Is Windows"]));
	var dup = [
		{ id: 0, count: 3, s7: "TRUE" },
		{ id: 1, count: 1, s7: "FALSE" }
	];
	var cfg2 = Q.buildConfig(q, dup);
	ok("config: one shared answer -> the Count column appears",
		eq(cfg2.columns.slice(1).map(function (c) { return c.label; }), ["Is Windows", "Count"]));
})();

(function () {
	var q = { sensors: [{ sid: 7, name: "Is Windows" }] };
	var cfg = Q.buildConfig(q, []);
	ok("config: no rows yet -> no Count column (no duplicates to count)",
		eq(cfg.columns.slice(1).map(function (c) { return c.label; }), ["Is Windows"]));
	ok("config: no rows yet -> 'No results yet' empty message", cfg.emptyMessage === "No results yet");
})();

// --- the page wiring (static) -----------------------------------------------------

const pageSrc = fs.readFileSync(path.join(__dirname, "..", "server", "console", "html", "modules", "query.php"), "utf8");
ok("page: the results view loads the module", pageSrc.indexOf('/layout/queryresults.js') >= 0);
ok("page: the results view boots the module with the query ID",
	/LuminumQueryResults\.init\(\s*<\?php print \$queryid; \?>\s*\)/.test(pageSrc));
["qrtable", "qrtopcell", "qrcount", "qrtotal", "qrselcount", "qrrefresh", "qrfilter", "qrtable-head", "qrtable-body", "qrfootcell"].forEach(function (id) {
	ok("page: the table shell carries #" + id, pageSrc.indexOf('id="' + id + '"') >= 0);
});
// The top row is the console's standard format: the refresh button first,
// then "displayed of total Items" and the (N Selected) suffix span.
ok("page: the top row leads with the refresh button, then the count",
	pageSrc.indexOf('id="qrrefresh"') >= 0 && pageSrc.indexOf('id="qrrefresh"') < pageSrc.indexOf('id="qrcount"'));
ok("page: the top row shows displayed of total Items",
	pageSrc.indexOf('<span id="qrcount">0</span> of <span id="qrtotal">0</span> Items') >= 0);

// The results view has no tabs at all: the Results tab button is gone from
// the query page, and the tab bar itself only renders in the builder branch.
ok("page: the Results tab button is gone", pageSrc.indexOf("switchTab(event, 'Results')") < 0);
ok("page: the tab bar renders only in the builder branch",
	pageSrc.indexOf('<?php } else { ?>') >= 0 && pageSrc.indexOf('tabbarback') > pageSrc.indexOf('<?php } else { ?>'));
ok("page: the results table renders in the results branch",
	pageSrc.indexOf('<?php if ($showresults) { ?>') >= 0 && pageSrc.indexOf('id="qrtable"') < pageSrc.indexOf('<?php } else { ?>'));

// The Saved Queries tab is reachable from the header menu via ?tab=saved -
// the old standalone Saved Queries page (admin/savedqueries.php) is gone.
ok("page: ?tab=saved selects the Saved tab button",
	/tablink<\?php print \$showsaved \? ' tabbarsel' : ''; \?>/.test(pageSrc));
ok("page: ?tab=saved hides the Builder tab",
	pageSrc.indexOf("<div id=\"Builder\" class=\"configtab\" style=\"<?php print $showsaved ? 'display: none;' : ''; ?>\">") >= 0);
ok("page: ?tab=saved shows the Saved tab",
	pageSrc.indexOf("<div id=\"Saved\" class=\"configtab\" style=\"<?php print $showsaved ? '' : 'display: none;'; ?>\">") >= 0);

// The left form button follows the active tab: Reset Form on the Query
// Builder tab, Copy to Builder on the Saved Queries tab - switchTab swaps
// the label, the click dispatches on the active tab, and the initial
// label matches ?tab=saved.
ok("page: the form button's initial label matches ?tab=saved",
	/<button id="resetform" class="formgo" style="margin-right: 0;"><\?php print \$showsaved \? 'Copy to Builder' : 'Reset Form'; \?><\/button>/.test(pageSrc));
ok("page: switchTab swaps the form button label with the active tab",
	pageSrc.indexOf('document.getElementById("resetform").textContent = (configSect === "Saved") ? "Copy to Builder" : "Reset Form"') >= 0);
ok("page: the form button dispatches on the active tab",
	pageSrc.indexOf("if (document.getElementById('Saved').style.display !== 'none')") >= 0 &&
	pageSrc.indexOf("copyToBuilder();") >= 0);

// The Saved Queries tab carries the console's standard table (the old
// "No saved queries yet." placeholder is gone): the displayed-of-total
// count with the (N Selected) suffix span, the right-hand filter box, the
// checkbox / Query Name / Structure / Author / Create Date columns, and the
// empty state - saved queries have no storage yet, so the table renders 0
// of 0. The Structure column renders the query's full text-based
// interpretation (LuminumQueryBuilder.queryStructure).
ok("page: the Saved tab's placeholder text is gone", pageSrc.indexOf("No saved queries yet.") < 0);
ok("page: the Saved tab's top row shows displayed of total items",
	pageSrc.indexOf('<span id="sqviscount">0</span> of <span id="sqtotcount">0</span> items <span id="sqselcount"></span>') >= 0);
ok("page: the Saved tab's top row carries the filter box", pageSrc.indexOf('id="savedqueriesfilter"') >= 0);
// The Query Name and Structure columns carry no fixed width: they are the
// flexible columns that absorb the table's 100% width (the Computer Name
// column's role on the Client Status page), which keeps the 15px checkbox
// column from being stretched by the auto table layout.
ok("page: the Saved tab's columns are Query Name, Structure, Author, Create Date",
	/<td>Query Name<\/td><td>Structure<\/td><td style="width: 100px;">Author<\/td><td style="width: 100px;">Create Date<\/td>/.test(pageSrc));
ok("page: the Saved tab's rows span the five columns",
	/<tr><td colspan="5" style="text-align: center; background-color: #494a69; font-weight: normal; font-style: italic;">No Results<\/td><\/tr>/.test(pageSrc));
// The table sits inside the blue content box with the standard module
// padding around it (the tab's module-content is padding: 0 for the tab bar).
ok("page: the Saved tab's table carries the standard module inset",
	pageSrc.indexOf('<div style="padding: 5px 20px 20px 20px;">') >= 0);
ok("page: the Saved tab renders the empty state", pageSrc.indexOf("No Results") >= 0);
ok("page: the Saved tab's filter keeps the displayed count in step",
	pageSrc.indexOf("LuminumTable.attachTextFilter('savedqueriesfilter'") >= 0 && pageSrc.indexOf("document.getElementById('sqviscount')") >= 0);
ok("page: the Saved tab's selection maintains the (N Selected) suffix",
	pageSrc.indexOf("document.getElementById(\"sqselcount\").textContent = checkTrigger > 0 ? '(' + checkTrigger + ' Selected)' : ''") >= 0);
const headerSrc = fs.readFileSync(path.join(__dirname, "..", "server", "console", "html", "layout", "header.php"), "utf8");
ok("header: the Saved Queries link opens the query page's Saved tab",
	headerSrc.indexOf('href=\\"/modules.php?view=query&tab=saved\\"') >= 0);
const indexSrc = fs.readFileSync(path.join(__dirname, "..", "server", "console", "html", "index.php"), "utf8");
ok("index: the standalone savedqueries view is gone", indexSrc.indexOf("savedqueries") < 0);

// The checkbox column's selection wiring lives in the module (the header is
// re-rendered on every poll, so both listeners are delegated to the stable
// tbody elements).
const qrSrc = fs.readFileSync(path.join(__dirname, "..", "server", "console", "html", "layout", "queryresults.js"), "utf8");
ok("module: row checkboxes carry the qrrow class", qrSrc.indexOf("'qrrow'") >= 0);
ok("module: row selection is delegated on the body tbody",
	qrSrc.indexOf("table.querySelector('tbody[data-luminum-body]')") >= 0 && qrSrc.indexOf("state.selected[e.target.dataset.id]") >= 0);
ok("module: select-all is delegated on the header tbody",
	qrSrc.indexOf("e.target.id !== 'qrselectall'") >= 0);
ok("module: the select-all state survives the per-poll header re-render",
	qrSrc.indexOf("document.getElementById('qrselectall')") >= 0);
ok("module: the top row carries the (N Selected) suffix",
	qrSrc.indexOf("document.getElementById('qrselcount')") >= 0 && qrSrc.indexOf("'(' + sel + ' Selected)'") >= 0);

if (failures > 0) {
	console.log("----------------------------------------");
	console.log(failures + " check(s) failed");
	process.exit(1);
}
console.log("All checks passed.");
