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

// --- expandRow (the CSPLIT sensor's output lines -> sub-row values) ------------

// A split sensor: each output line becomes a sub-row, each line's
// delimiter-separated segments fill the sub-columns.
(function () {
	var row = { id: 0, count: 1, s9: "App One|1.0.1\nApp Two|2.0\nApp Three|7.2" };
	Q.expandRow(row, [{ sid: 9, name: "Installed Applications", csplit: 1, delimiter: "|", outcols: ["Name", "Version"] }]);
	ok("expand: the row spans one sub-row per output line", row.span === 3);
	ok("expand: line 0's segments land in the sub values",
		row.s9_0_0 === "App One" && row.s9_0_1 === "1.0.1");
	ok("expand: line 2's segments land in the sub values",
		row.s9_2_0 === "App Three" && row.s9_2_1 === "7.2");
	ok("expand: the largest segment count is recorded", row.s9_segs === 2);
	ok("expand: the raw cell is kept (the filter searches it)",
		row.s9 === "App One|1.0.1\nApp Two|2.0\nApp Three|7.2");
})();

// A trailing newline (a script that ends its output with one) does not add
// an empty last line.
(function () {
	var row = { id: 0, count: 1, s9: "A|1\nB|2\n" };
	Q.expandRow(row, [{ sid: 9, name: "S", csplit: 1, delimiter: "|", outcols: ["N", "V"] }]);
	ok("expand: a trailing newline is dropped", row.span === 2 && row.s9_1_0 === "B");
})();

// A non-split sensor leaves the row alone (span 1, no sub values).
(function () {
	var row = { id: 0, count: 1, s7: "TRUE" };
	Q.expandRow(row, [{ sid: 7, name: "Is Windows", csplit: 0, delimiter: null, outcols: null }]);
	ok("expand: a non-split sensor keeps span 1", row.span === 1);
	ok("expand: no sub values are created", row.s7_0_0 === undefined && row.s7_segs === undefined);
})();

// A split sensor the endpoint never answered renders one empty line.
(function () {
	var row = { id: 0, count: 1, s9: "" };
	Q.expandRow(row, [{ sid: 9, name: "S", csplit: 1, delimiter: "|", outcols: ["N", "V"] }]);
	ok("expand: an empty answer is one line with an empty segment",
		row.span === 1 && row.s9_0_0 === "" && row.s9_segs === 1);
})();

// A custom delimiter splits on the sensor's own character.
(function () {
	var row = { id: 0, count: 1, s9: "A,1\nB,2" };
	Q.expandRow(row, [{ sid: 9, name: "S", csplit: 1, delimiter: ",", outcols: ["N", "V"] }]);
	ok("expand: a comma delimiter splits on the comma",
		row.s9_0_0 === "A" && row.s9_0_1 === "1" && row.s9_1_1 === "2");
})();

// Two split sensors with different line counts: the row spans the largest.
(function () {
	var row = { id: 0, count: 1, s7: "A|1\nB|2", s9: "X\nY\nZ" };
	Q.expandRow(row, [
		{ sid: 7, name: "S7", csplit: 1, delimiter: "|", outcols: ["N", "V"] },
		{ sid: 9, name: "S9", csplit: 1, delimiter: "|", outcols: ["Only"] }
	]);
	ok("expand: the span is the largest line count across split cells", row.span === 3);
	ok("expand: both sensors' sub values are present",
		row.s7_1_0 === "B" && row.s9_2_0 === "Z");
})();

// A line with more segments than stored names records the extra count
// (buildConfig names the extras generically).
(function () {
	var row = { id: 0, count: 1, s9: "A|1|extra\nB|2" };
	Q.expandRow(row, [{ sid: 9, name: "S", csplit: 1, delimiter: "|", outcols: ["N", "V"] }]);
	ok("expand: extra segments are recorded", row.s9_segs === 3 && row.s9_0_2 === "extra");
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

// A CSPLIT sensor's column carries its stored column names as sub-labels
// (the header's second tier); the filter still searches the raw cell.
(function () {
	var q = {
		sensors: [
			{ sid: 7, name: "Computer Name", csplit: 0, delimiter: null, outcols: null },
			{ sid: 9, name: "Installed Applications", csplit: 1, delimiter: "|", outcols: ["Name", "Version"] }
		]
	};
	var rows = [
		{ id: 0, count: 1, s7: "host-1", s9: "App One|1.0.1\nApp Two|2.0", s9_0_0: "App One", s9_0_1: "1.0.1", s9_1_0: "App Two", s9_1_1: "2.0", s9_segs: 2, span: 2 }
	];
	var cfg = Q.buildConfig(q, rows);
	ok("config: the split sensor's column carries its sub-labels",
		cfg.columns[2].key === "s9" && eq(cfg.columns[2].sub, ["Name", "Version"]));
	ok("config: the non-split sensor's column has no sub-labels", !cfg.columns[1].sub);
	ok("config: the split sensor's column stays pre-wrapped", cfg.columns[2].whiteSpace === "pre-wrap");
	ok("config: the filter searches the split sensor's raw cell",
		eq(cfg.searchKeys, ["s7", "s9"]));
})();

// A line with more segments than stored names gains generic "Column N"
// sub-labels so no data is dropped.
(function () {
	var q = { sensors: [{ sid: 9, name: "S", csplit: 1, delimiter: "|", outcols: ["N", "V"] }] };
	var rows = [
		{ id: 0, count: 1, s9: "A|1|extra", s9_segs: 3, span: 1 }
	];
	var cfg = Q.buildConfig(q, rows);
	ok("config: extra segments gain generic Column N sub-labels",
		eq(cfg.columns[1].sub, ["N", "V", "Column 3"]));
	// No row exceeds the stored names -> no generic labels.
	var cfg2 = Q.buildConfig(q, [{ id: 0, count: 1, s9: "A|1", s9_segs: 2, span: 1 }]);
	ok("config: no generic labels when no line exceeds the names",
		eq(cfg2.columns[1].sub, ["N", "V"]));
})();

// A CSPLIT sensor without stored names (pre-OUTCOLS installs) renders as a
// plain column (no sub-labels to show).
(function () {
	var q = { sensors: [{ sid: 9, name: "S", csplit: 1, delimiter: "|", outcols: null }] };
	var cfg = Q.buildConfig(q, [{ id: 0, count: 1, s9: "A|1", span: 1 }]);
	ok("config: a split sensor without names is a plain column", !cfg.columns[1].sub);
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

// --- queryDone (the footer clock's stop condition) --------------------------------

(function () {
	var base = { status: 'SENT', deadline_ts: 1000, target_online: 3, answered: 1 };
	ok("done: a running query with answers outstanding is not done",
		Q.queryDone(base, 900 * 1000) === false);
	ok("done: the deadline passing stops the clock",
		Q.queryDone(base, 1000 * 1000) === true);
	ok("done: one millisecond before the deadline, not done",
		Q.queryDone(base, 999 * 1000) === false);
	ok("done: the TIMEDOUT status stops the clock",
		Q.queryDone(Object.assign({}, base, { status: 'TIMEDOUT' }), 500 * 1000) === true);
	ok("done: every online endpoint answered stops the clock",
		Q.queryDone(Object.assign({}, base, { answered: 3 }), 500 * 1000) === true);
	ok("done: one answer short of the online endpoints, not done",
		Q.queryDone(Object.assign({}, base, { answered: 2 }), 500 * 1000) === false);
	ok("done: no online endpoints is not a vacuous completion",
		Q.queryDone(Object.assign({}, base, { target_online: 0, answered: 0 }), 500 * 1000) === false);
	ok("done: a PENDING query (no deadline published yet) is not done",
		Q.queryDone({ status: 'PENDING', deadline_ts: null, target_online: 3, answered: 0 }, 500 * 1000) === false);
})();

// --- doneElapsed (the server-side duration of a finished query) -------------------

(function () {
	ok("elapsed: a timed-out query runs from SENT to the deadline",
		Q.doneElapsed({ status: 'TIMEDOUT', sent_ts: 100, created_ts: 90, deadline_ts: 130, last_answer_ts: null }) === 30);
	ok("elapsed: an answered query runs from SENT to the last answer",
		Q.doneElapsed({ status: 'ACKED', sent_ts: 100, created_ts: 90, deadline_ts: 220, last_answer_ts: 112 }) === 12);
	ok("elapsed: falls back to CREATED when SENT is null",
		Q.doneElapsed({ status: 'ACKED', sent_ts: null, created_ts: 90, deadline_ts: 220, last_answer_ts: 112 }) === 22);
	ok("elapsed: missing instants -> null",
		Q.doneElapsed({ status: 'ACKED', sent_ts: null, created_ts: 90, deadline_ts: 220, last_answer_ts: null }) === null);
	ok("elapsed: a timeout with no deadline -> null",
		Q.doneElapsed({ status: 'TIMEDOUT', sent_ts: 100, created_ts: 90, deadline_ts: null, last_answer_ts: null }) === null);
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
// The footer clock starts as "Processing Query... 0.00 Seconds" (the
// module flips the prefix to "Query Completed in" when the query finishes).
ok("page: the footer clock starts as 'Processing Query...'",
	pageSrc.indexOf('<span id="qrfootprefix">Processing Query...</span> <span id="queryms">0.00</span> Seconds') >= 0);

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
// label matches ?tab=saved. Copy to Builder starts disabled on the Saved
// tab (no saved query is selected yet) and the module keeps it in step.
ok("page: the form button's initial label matches ?tab=saved",
	/<button id="resetform" class="formgo" style="margin-right: 0;"<\?php print \$showsaved \? ' disabled="disabled"' : ''; \?>><\?php print \$showsaved \? 'Copy to Builder' : 'Reset Form'; \?><\/button>/.test(pageSrc));
ok("page: the form button starts disabled on the Saved tab",
	/<button id="resetform"[^>]*<\?php print \$showsaved \? ' disabled="disabled"' : ''; \?>/.test(pageSrc));
ok("page: switchTab swaps the form button label with the active tab",
	pageSrc.indexOf('document.getElementById("resetform").textContent = (configSect === "Saved") ? "Copy to Builder" : "Reset Form"') >= 0);
ok("page: the form button dispatches on the active tab",
	pageSrc.indexOf("if (document.getElementById('Saved').style.display !== 'none')") >= 0 &&
	pageSrc.indexOf("copyToBuilder();") >= 0);
// Delete Selected sits to the left of the form button: a Saved-tab-only
// button (hidden on the Query Builder tab, where it could never be
// enabled) that starts disabled and the module enables once a saved query
// is selected.
ok("page: Delete Selected sits to the left of the form button, starts disabled",
	/<button id="sqdelete" class="formgo" style="<\?php print \$showsaved \? '' : 'display: none;'; \?>margin-right: 0;" disabled="disabled">Delete Selected<\/button> <button id="resetform"/.test(pageSrc));
ok("page: switchTab shows Delete Selected only on the Saved tab",
	pageSrc.indexOf('document.getElementById("sqdelete").style.display = (configSect === "Saved") ? "" : "none"') >= 0);

// The Saved Queries tab carries the console's standard table (the old
// "No saved queries yet." placeholder is gone): the displayed-of-total
// count with the (N Selected) suffix span, the right-hand filter box, the
// selection / Name / Structure / Author / Create Date columns, and
// the empty state - saved queries have no storage yet, so the table
// renders 0 of 0. The selection column's header checkbox is a permanently
// disabled dummy (the rows are radio buttons, one selection); the
// Structure column renders the query's full text-based interpretation
// (LuminumQueryBuilder.queryStructure).
ok("page: the Saved tab's placeholder text is gone", pageSrc.indexOf("No saved queries yet.") < 0);
ok("page: the Saved tab's top row shows displayed of total items",
	pageSrc.indexOf('<span id="sqviscount">0</span> of <span id="sqtotcount">0</span> items <span id="sqselcount"></span>') >= 0);
ok("page: the Saved tab's top row carries the filter box", pageSrc.indexOf('id="savedqueriesfilter"') >= 0);
// The table is table-layout: fixed with a colgroup: the checkbox column is
// pinned to 32px (the console-wide standard), Author keeps its 100px width,
// Create Date is 120px (wide enough for the bold header label), and Name
// and Structure are the bare flexible columns that absorb the table's
// 100% width.
ok("page: the Saved tab's columns are Name, Structure, Author, Create Date",
	/<td>Name<\/td><td>Structure<\/td><td>Author<\/td><td>Create Date<\/td>/.test(pageSrc));
ok("page: the Saved tab's table pins its checkbox column in a colgroup",
	pageSrc.indexOf('<table style="margin-top: 10px; table-layout: fixed;">') >= 0 &&
	pageSrc.indexOf('<colgroup><col style="width: 32px;"><col><col><col style="width: 100px;"><col style="width: 120px;"></colgroup>') >= 0);
ok("page: the Saved tab's rows span the five columns",
	/<tr><td colspan="5" style="text-align: center; background-color: #494a69; font-weight: normal; font-style: italic;">No Results<\/td><\/tr>/.test(pageSrc));
// The table sits inside the blue content box with the standard module
// padding around it (the tab's module-content is padding: 0 for the tab bar).
ok("page: the Saved tab's table carries the standard module inset",
	pageSrc.indexOf('<div style="padding: 5px 20px 20px 20px;">') >= 0);
ok("page: the Saved tab renders the empty state", pageSrc.indexOf("No Results") >= 0);
ok("page: the Saved tab's filter keeps the displayed count in step",
	pageSrc.indexOf("LuminumTable.attachTextFilter('savedqueriesfilter'") >= 0 && pageSrc.indexOf("document.getElementById('sqviscount')") >= 0);
ok("page: the Saved tab's header selection is a disabled dummy checkbox",
	/<td><input type="checkbox" disabled="disabled"><\/td><td>Name<\/td>/.test(pageSrc));
ok("page: the Saved tab's selection maintains the (1 Selected) suffix",
	pageSrc.indexOf("document.getElementById(\"sqselcount\").textContent = document.querySelector('.savedqueryrow:checked') ? '(1 Selected)' : ''") >= 0);
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

// The live behaviour: the running query polls every second (the finished
// query slows to the console's standard five), the new answer rows are
// appended to the table instead of a full re-render, and the footer clock
// ticks "Processing Query..." until the stop condition, then reads
// "Query Completed in".
ok("module: the running query polls every second", qrSrc.indexOf('interval: 1000') >= 0);
ok("module: the finished query slows to the five-second poll", qrSrc.indexOf('interval: 5000') >= 0);
ok("module: new answer rows are appended, not re-rendered", qrSrc.indexOf("insertAdjacentHTML") >= 0);
ok("module: the footer clock ticks 'Processing Query...' while running",
	qrSrc.indexOf("'Processing Query...'") >= 0);
ok("module: the footer clock stops as 'Query Completed in'",
	qrSrc.indexOf("'Query Completed in'") >= 0);
ok("module: the clock stops on the queryDone condition", qrSrc.indexOf("queryDone(q, Date.now())") >= 0);
ok("module: the clock stops exactly on the published deadline",
	qrSrc.indexOf("deadlineMs") >= 0 && qrSrc.indexOf("q.deadline_ts * 1000") >= 0);
ok("module: an already-finished query shows the server-side duration",
	qrSrc.indexOf("doneElapsed(q)") >= 0);

if (failures > 0) {
	console.log("----------------------------------------");
	console.log(failures + " check(s) failed");
	process.exit(1);
}
console.log("All checks passed.");
