//
// console_query_test.js - offline test for layout/querybuilder.js, the
// query wiring of the query builder page (modules/query.php).
//
// The pure functions (resolveSensorId, condBlocksToTree) are tested
// directly; the DOM helpers (collectCondBlocks, condRowsStatus,
// buildQueryPayload) are driven through a minimal DOM shim (no jsdom in
// the container).
//
// Usage: node tests/console_query_test.js
// Exit code: 0 if all checks pass, 1 otherwise.

const path = require("path");
const Q = require(path.join(__dirname, "..", "server", "console", "html", "layout", "querybuilder.js"));

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

// --- minimal DOM shim -------------------------------------------------------
// Supports exactly the operations the querybuilder DOM helpers use:
// children, classList.contains, querySelector(All) for the selectors they
// use, setAttribute, and .value on inputs/selects.
class El {
	constructor(tag, classes) {
		this.tagName = String(tag).toLowerCase();
		this.classes = classes || [];
		this.children = [];
		this.attrs = {};
		this.value = "";
	}
	get classList() {
		const self = this;
		return { contains: (c) => self.classes.indexOf(c) >= 0 };
	}
	setAttribute(n, v) { this.attrs[n] = String(v); }
	getAttribute(n) { return (n in this.attrs) ? this.attrs[n] : null; }
	appendChild(c) { this.children.push(c); return c; }
	_matches(sel) {
		if (sel === "input") { return this.tagName === "input"; }
		if (sel === 'select[name="fromop"]') { return this.tagName === "select" && this.attrs["name"] === "fromop"; }
		if (sel === "select.logical-operator") { return this.tagName === "select" && this.classes.indexOf("logical-operator") >= 0; }
		throw new Error("unsupported selector: " + sel);
	}
	*walk() { for (const c of this.children) { yield c; yield* c.walk(); } }
	querySelectorAll(sel) {
		const out = [];
		for (const n of this.walk()) { if (n._matches(sel)) { out.push(n); } }
		return out;
	}
	querySelector(sel) { const r = this.querySelectorAll(sel); return r.length ? r[0] : null; }
}

const doc = {
	byId: {},
	getElementById(id) { return (id in this.byId) ? this.byId[id] : null; },
	createElement(tag) { return new El(tag); }
};
global.document = doc;

const catalog = [
	{ id: 1, name: "Hostname" },
	{ id: 2, name: "Deploy Test Sensor" },
	{ id: 3, name: "CPU Load" }
];

// --- resolveSensorId --------------------------------------------------------
ok("resolve: numeric ID match", Q.resolveSensorId(catalog, "2") === 2);
ok("resolve: name match", Q.resolveSensorId(catalog, "Hostname") === 1);
ok("resolve: name match case-insensitive", Q.resolveSensorId(catalog, "hostname") === 1);
ok("resolve: surrounding whitespace trimmed", Q.resolveSensorId(catalog, "  CPU Load  ") === 3);
ok("resolve: numeric text that is not an ID falls back to the name",
	Q.resolveSensorId([{ id: 5, name: "7" }], "7") === 5);
ok("resolve: unknown name -> null", Q.resolveSensorId(catalog, "Nope") === null);
ok("resolve: empty -> null", Q.resolveSensorId(catalog, "   ") === null);

// --- condBlocksToTree -------------------------------------------------------
const row = (sensor, op, value, opAfter) => ({
	kind: "row", sensor: sensor, value: value,
	sid: sensor === "" ? null : Q.resolveSensorId(catalog, sensor),
	op: op, opAfter: opAfter
});

ok("tree: single row is a leaf",
	eq(Q.condBlocksToTree([row("Hostname", "==", "web-01", null)]),
		{ sid: 1, op: "==", value: "web-01" }));
ok("tree: two rows fold AND by default",
	eq(Q.condBlocksToTree([row("Hostname", "==", "a", null), row("CPU Load", ">", "10", null)]),
		{ logic: "AND", left: { sid: 1, op: "==", value: "a" }, right: { sid: 3, op: ">", value: "10" } }));
ok("tree: the operator between rows is the first row's opAfter",
	eq(Q.condBlocksToTree([row("Hostname", "==", "a", "OR"), row("CPU Load", ">", "10", null)]),
		{ logic: "OR", left: { sid: 1, op: "==", value: "a" }, right: { sid: 3, op: ">", value: "10" } }));
ok("tree: three rows fold left-associatively",
	eq(Q.condBlocksToTree([row("Hostname", "==", "a", "AND"), row("CPU Load", ">", "10", "OR"), row("Hostname", "!=", "b", null)]),
		{ logic: "OR",
			left: { logic: "AND", left: { sid: 1, op: "==", value: "a" }, right: { sid: 3, op: ">", value: "10" } },
			right: { sid: 1, op: "!=", value: "b" } }));
ok("tree: a group is a subtree",
	eq(Q.condBlocksToTree([
		row("Hostname", "==", "a", "AND"),
		{ kind: "group", blocks: [row("CPU Load", ">", "10", "OR"), row("Hostname", "!=", "b", null)], opAfter: null }
	]),
		{ logic: "AND",
			left: { sid: 1, op: "==", value: "a" },
			right: { logic: "OR", left: { sid: 3, op: ">", value: "10" }, right: { sid: 1, op: "!=", value: "b" } } }));
ok("tree: an entirely empty row is skipped, its opAfter still applies",
	eq(Q.condBlocksToTree([row("Hostname", "==", "a", "AND"), row("", "==", "", "OR"), row("CPU Load", ">", "10", null)]),
		{ logic: "OR", left: { sid: 1, op: "==", value: "a" }, right: { sid: 3, op: ">", value: "10" } }));
ok("tree: all rows empty -> null",
	Q.condBlocksToTree([row("", "==", "", null)]) === null);
ok("tree: a group whose rows are all empty drops out",
	Q.condBlocksToTree([{ kind: "group", blocks: [row("", "==", "", null)], opAfter: null }]) === null);
ok("tree: a lone group is its subtree",
	eq(Q.condBlocksToTree([{ kind: "group", blocks: [row("Hostname", "==", "a", "AND"), row("CPU Load", ">", "10", null)], opAfter: null }]),
		{ logic: "AND", left: { sid: 1, op: "==", value: "a" }, right: { sid: 3, op: ">", value: "10" } }));

// --- DOM helpers (shim) -----------------------------------------------------
// A From row: sensor input, operator select, value input, optional
// trailing AND/OR select (the page's insertLogicalOperators anchor).
function condRow(sensor, op, value, opAfter) {
	const el = new El("div", ["list-item"]);
	const s = new El("input"); s.value = sensor; el.appendChild(s);
	const opSel = new El("select"); opSel.setAttribute("name", "fromop"); opSel.value = op; el.appendChild(opSel);
	const v = new El("input"); v.value = value; el.appendChild(v);
	if (opAfter) { const a = new El("select", ["logical-operator"]); a.value = opAfter; el.appendChild(a); }
	return el;
}

const fromList = new El("div");
const r1 = condRow("Hostname", "equals", "web-01", "AND");
const group = new El("div", ["group-container"]);
group.appendChild(condRow("CPU Load", "greaterthan", "10", "OR"));
const r3 = condRow("Deploy Test Sensor", "contains", "probe", null);
const r3after = new El("select", ["logical-operator"]); r3after.value = "AND";
r3.appendChild(r3after);
group.appendChild(r3);
fromList.appendChild(r1);
fromList.appendChild(group);

const blocks = Q.collectCondBlocks(fromList, catalog);
ok("collect: two top-level blocks (row + group)",
	blocks.length === 2 && blocks[0].kind === "row" && blocks[1].kind === "group");
ok("collect: row fields resolved",
	blocks[0].sid === 1 && blocks[0].op === "==" && blocks[0].value === "web-01" && blocks[0].opAfter === "AND");
ok("collect: group carries its rows and its trailing operator",
	blocks[1].blocks.length === 2 && blocks[1].blocks[0].sid === 3 && blocks[1].blocks[1].sid === 2 && blocks[1].opAfter === "AND");
ok("collect: the group's rows keep their operators (the last row's is the group's trailing one)",
	blocks[1].blocks[0].opAfter === "OR" && blocks[1].blocks[1].opAfter === "AND");
ok("collect: unknown sensor resolves to a null sid",
	Q.collectCondBlocks((function () {
		const c = new El("div");
		c.appendChild(condRow("Nope", "equals", "x", null));
		return c;
	})(), catalog)[0].sid === null);

ok("status: complete rows -> ok", Q.condRowsStatus(fromList) === "ok");
ok("status: a value without a sensor -> incomplete", (function () {
	const c = new El("div");
	c.appendChild(condRow("", "equals", "x", null));
	return Q.condRowsStatus(c) === "incomplete";
})());
ok("status: a lone empty row -> empty", (function () {
	const c = new El("div");
	c.appendChild(condRow("", "equals", "", null));
	return Q.condRowsStatus(c) === "empty";
})());
ok("status: a group with an incomplete row -> incomplete", (function () {
	const g = new El("div", ["group-container"]);
	g.appendChild(condRow("Hostname", "equals", "a", null));
	g.appendChild(condRow("", "equals", "x", null));
	const c = new El("div");
	c.appendChild(g);
	return Q.condRowsStatus(c) === "incomplete";
})());

// --- buildQueryPayload ------------------------------------------------------
function getRow(text) {
	const el = new El("div", ["list-item"]);
	const inp = new El("input"); inp.value = text; el.appendChild(inp);
	return el;
}

const getList = new El("div");
getList.appendChild(getRow("Hostname"));
getList.appendChild(getRow("hostname")); // duplicate, case-insensitive
getList.appendChild(getRow("Deploy Test Sensor"));

doc.byId["get-list"] = getList;
doc.byId["targets"] = { value: "matching" };
doc.byId["from-list"] = fromList;

let res = Q.buildQueryPayload(catalog);
ok("payload: no error", !res.error, res.error);
ok("payload: broadcast target + deduped sensors",
	res.payload && res.payload.target === "all" && res.payload.action === "query" &&
	JSON.stringify(res.payload.sensors) === JSON.stringify([{ sid: 1 }, { sid: 2 }]));
ok("payload: conditions tree from the rows + group",
	res.payload && eq(res.payload.conditions,
		{ logic: "AND",
			left: { sid: 1, op: "==", value: "web-01" },
			right: { logic: "OR", left: { sid: 3, op: ">", value: "10" }, right: { sid: 2, op: "=~", value: "probe" } } }));

doc.byId["targets"] = { value: "all" };
res = Q.buildQueryPayload(catalog);
ok("payload: all endpoints -> no conditions field",
	res.payload && !("conditions" in res.payload));

doc.byId["targets"] = { value: "matching" };
const getListBad = new El("div");
getListBad.appendChild(getRow("Nope"));
doc.byId["get-list"] = getListBad;
res = Q.buildQueryPayload(catalog);
ok("payload: unknown retrieve sensor -> error", res.error === "No such sensor: Nope", res.error);

doc.byId["get-list"] = getList;
const fromBad = new El("div");
fromBad.appendChild(condRow("Nope", "equals", "x", null));
doc.byId["from-list"] = fromBad;
res = Q.buildQueryPayload(catalog);
ok("payload: unknown condition sensor -> error", res.error === "No such sensor: Nope", res.error);

const fromEmpty = new El("div");
fromEmpty.appendChild(condRow("", "equals", "", null));
doc.byId["from-list"] = fromEmpty;
res = Q.buildQueryPayload(catalog);
ok("payload: matching with no conditions -> error",
	res.error === "Add a condition sensor to filter the endpoints.", res.error);

const getEmpty = new El("div");
getEmpty.appendChild(getRow(""));
doc.byId["get-list"] = getEmpty;
res = Q.buildQueryPayload(catalog);
ok("payload: no retrieve sensors -> error",
	res.error === "Name at least one sensor to retrieve.", res.error);

console.log("-".repeat(60));
if (failures) {
	console.log("FAILED: " + failures + " check(s) failed");
	process.exit(1);
}
console.log("All checks passed.");
process.exit(0);
