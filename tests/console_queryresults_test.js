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

// The motivating case: one sensor, 15 endpoints all answering TRUE - every
// row carries count 15.
(function () {
	var results = [];
	for (var uid = 1; uid <= 15; uid++) { results.push(res(uid, 7, "OK", "TRUE", null)); }
	var piv = Q.pivotResults({ sensors: [{ sid: 7, name: "Is Windows" }], results: results });
	ok("pivot: 15 identical answers -> 15 rows", piv.rows.length === 15);
	ok("pivot: identical answers set hasDup", piv.hasDup === true);
	ok("pivot: every row shows the shared count", piv.rows.every(function (r) { return r.count === 15; }));
	ok("pivot: the cell is the sensor's answer", piv.rows.every(function (r) { return r.s7 === "TRUE"; }));
})();

// All answers unique -> no Count column at all.
(function () {
	var piv = Q.pivotResults({
		sensors: [{ sid: 7, name: "Is Windows" }],
		results: [res(1, 7, "OK", "TRUE", null), res(2, 7, "OK", "FALSE", null), res(3, 7, "OK", "MAYBE", null)]
	});
	ok("pivot: unique answers -> hasDup false", piv.hasDup === false);
	ok("pivot: unique answers -> no count field", piv.rows.every(function (r) { return !("count" in r); }));
})();

// Two sensors: the answer is the whole row (every sensor column).
(function () {
	var piv = Q.pivotResults({
		sensors: [{ sid: 7, name: "Is Windows" }, { sid: 9, name: "CPU Load" }],
		results: [
			res(1, 7, "OK", "TRUE", null), res(1, 9, "OK", "1", null),
			res(2, 7, "OK", "TRUE", null), res(2, 9, "OK", "1", null),
			res(3, 7, "OK", "FALSE", null), res(3, 9, "OK", "2", null)
		]
	});
	ok("pivot: two sensors -> one row per endpoint", piv.rows.length === 3);
	ok("pivot: same full answer -> count 2", piv.rows[0].count === 2 && piv.rows[1].count === 2);
	ok("pivot: different full answer -> count 1", piv.rows[2].count === 1);
})();

// Equal in one sensor column but not the other is NOT the same answer.
(function () {
	var piv = Q.pivotResults({
		sensors: [{ sid: 7, name: "Is Windows" }, { sid: 9, name: "CPU Load" }],
		results: [
			res(1, 7, "OK", "TRUE", null), res(1, 9, "OK", "1", null),
			res(2, 7, "OK", "TRUE", null), res(2, 9, "OK", "2", null)
		]
	});
	ok("pivot: one column equal, the other not -> not the same answer", piv.hasDup === false);
})();

// An endpoint that never answered a requested sensor gets an empty cell,
// which still takes part in the answer signature.
(function () {
	var piv = Q.pivotResults({
		sensors: [{ sid: 7, name: "Is Windows" }, { sid: 9, name: "CPU Load" }],
		results: [
			res(1, 7, "OK", "TRUE", null),
			res(2, 7, "OK", "TRUE", null), res(2, 9, "OK", "1", null),
			res(3, 7, "OK", "TRUE", null)
		]
	});
	ok("pivot: a missing sensor answer is an empty cell", piv.rows[0].s9 === "");
	ok("pivot: the empty cell still takes part in the answer", piv.rows[0].count === 2 && piv.rows[1].count === 1);
})();

// Error answers render the error message and count like any other answer.
(function () {
	var piv = Q.pivotResults({
		sensors: [{ sid: 7, name: "Is Windows" }, { sid: 9, name: "Mac Sensor" }],
		results: [
			res(1, 7, "OK", "TRUE", null), res(1, 9, "ERR", null, "UNKNOWN_SENSOR"),
			res(2, 7, "OK", "TRUE", null), res(2, 9, "ERR", null, "UNKNOWN_SENSOR")
		]
	});
	ok("pivot: an ERR answer renders the error in the cell", piv.rows[0].s9 === "UNKNOWN_SENSOR");
	ok("pivot: two identical error answers share a count", piv.rows[0].count === 2);
})();

// No answers yet (the query is still in flight) -> no rows.
(function () {
	var piv = Q.pivotResults({ sensors: [{ sid: 7, name: "Is Windows" }], results: [] });
	ok("pivot: no answers -> no rows", piv.rows.length === 0 && piv.hasDup === false);
})();

// Answers that concatenate to the same string but differ per column must not
// collide (the signature's NUL separator).
(function () {
	var piv = Q.pivotResults({
		sensors: [{ sid: 7, name: "A" }, { sid: 9, name: "B" }],
		results: [
			res(1, 7, "OK", "TR", null), res(1, 9, "OK", "UE", null),
			res(2, 7, "OK", "T", null), res(2, 9, "OK", "RUE", null),
			res(3, 7, "OK", "TR", null), res(3, 9, "OK", "UE", null)
		]
	});
	ok("pivot: concatenated-equal answers do not collide",
		piv.rows[0].count === 2 && piv.rows[1].count === 1 && piv.rows[2].count === 2);
})();

// Rows keep the order in which the endpoints first answered.
(function () {
	var piv = Q.pivotResults({
		sensors: [{ sid: 7, name: "Is Windows" }, { sid: 9, name: "CPU Load" }],
		results: [
			res(2, 7, "OK", "A", null),
			res(1, 7, "OK", "B", null), res(1, 9, "OK", "1", null),
			res(2, 9, "OK", "2", null)
		]
	});
	ok("pivot: rows keep the endpoints' first-answer order", piv.rows[0].id === 2 && piv.rows[1].id === 1);
})();

// --- buildConfig ----------------------------------------------------------------

(function () {
	var q = { sensors: [{ sid: 7, name: "Is Windows" }, { sid: 9, name: "CPU Load" }] };
	var cfg = Q.buildConfig(q, true, 3);
	ok("config: Computer Name first, then the sensors in query order, Count last",
		eq(cfg.columns.map(function (c) { return c.label; }), ["Computer Name", "Is Windows", "CPU Load", "Count"]));
	ok("config: the Count column is centered",
		cfg.columns[3].key === "count" && cfg.columns[3].align === "center");
	ok("config: the filter searches hostname and sensor cells, not the count",
		eq(cfg.searchKeys, ["hostname", "s7", "s9"]));
	ok("config: rows present -> 'No Results' empty message", cfg.emptyMessage === "No Results");
})();

(function () {
	var q = { sensors: [{ sid: 7, name: "Is Windows" }] };
	var cfg = Q.buildConfig(q, false, 0);
	ok("config: unique answers -> no Count column",
		eq(cfg.columns.map(function (c) { return c.label; }), ["Computer Name", "Is Windows"]));
	ok("config: no rows yet -> 'No results yet' empty message", cfg.emptyMessage === "No results yet");
})();

// --- the page wiring (static) -----------------------------------------------------

const pageSrc = fs.readFileSync(path.join(__dirname, "..", "server", "console", "html", "modules", "query.php"), "utf8");
ok("page: the results tab loads the module", pageSrc.indexOf('/layout/queryresults.js') >= 0);
ok("page: the results tab boots the module with the query ID",
	/LuminumQueryResults\.init\(\s*<\?php print \$queryid; \?>\s*\)/.test(pageSrc));
["qrtable", "qrtopcell", "qrcount", "qrtotal", "qrrefresh", "qrfilter", "qrqueryrow", "qrtable-head", "qrtable-body", "qrfootcell"].forEach(function (id) {
	ok("page: the table shell carries #" + id, pageSrc.indexOf('id="' + id + '"') >= 0);
});

if (failures > 0) {
	console.log("----------------------------------------");
	console.log(failures + " check(s) failed");
	process.exit(1);
}
console.log("All checks passed.");
