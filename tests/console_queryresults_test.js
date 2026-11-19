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
	var cfg = Q.buildConfig(q, 3);
	ok("config: the first column is the select checkbox",
		cfg.columns[0].type === "checkbox" && cfg.columns[0].header.indexOf('id="qrselectall"') >= 0);
	ok("config: the sensors in query order, Count last",
		eq(cfg.columns.slice(1).map(function (c) { return c.label; }), ["Is Windows", "CPU Load", "Count"]));
	ok("config: the Count column is centered",
		cfg.columns[3].key === "count" && cfg.columns[3].align === "center");
	ok("config: the filter searches the sensor cells, not the count",
		eq(cfg.searchKeys, ["s7", "s9"]));
	ok("config: rows present -> 'No Results' empty message", cfg.emptyMessage === "No Results");
})();

(function () {
	var q = { sensors: [{ sid: 7, name: "Is Windows" }] };
	var cfg = Q.buildConfig(q, 0);
	ok("config: a single sensor -> checkbox, one column plus Count",
		eq(cfg.columns.slice(1).map(function (c) { return c.label; }), ["Is Windows", "Count"]));
	ok("config: no rows yet -> 'No results yet' empty message", cfg.emptyMessage === "No results yet");
})();

// --- the page wiring (static) -----------------------------------------------------

const pageSrc = fs.readFileSync(path.join(__dirname, "..", "server", "console", "html", "modules", "query.php"), "utf8");
ok("page: the results tab loads the module", pageSrc.indexOf('/layout/queryresults.js') >= 0);
ok("page: the results tab boots the module with the query ID",
	/LuminumQueryResults\.init\(\s*<\?php print \$queryid; \?>\s*\)/.test(pageSrc));
["qrtable", "qrtopcell", "qrcount", "qrtotal", "qrrefresh", "qrfilter", "qrtable-head", "qrtable-body", "qrfootcell"].forEach(function (id) {
	ok("page: the table shell carries #" + id, pageSrc.indexOf('id="' + id + '"') >= 0);
});

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

if (failures > 0) {
	console.log("----------------------------------------");
	console.log(failures + " check(s) failed");
	process.exit(1);
}
console.log("All checks passed.");
