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
// Supports the operations the querybuilder DOM helpers and the page's
// insertLogicalOperators use: children with parent links, classList,
// className, style, value, querySelector(All) for the selectors they use,
// appendChild/after/before/remove, and the sibling/parent accessors.
class El {
	constructor(tag, classes) {
		this.tagName = String(tag).toLowerCase();
		this.classes = classes || [];
		this.children = [];
		this.parent = null;
		this.attrs = {};
		this.value = "";
		this.style = {};
		this.textContent = "";
		this.id = "";
		this._listeners = {};
	}
	get classList() {
		const self = this;
		return { contains: (c) => self.classes.indexOf(c) >= 0 };
	}
	get className() { return this.classes.join(" "); }
	set className(v) { this.classes = String(v).split(/\s+/).filter((x) => x !== ""); }
	setAttribute(n, v) { this.attrs[n] = String(v); if (n === "id") { this.id = String(v); } }
	getAttribute(n) { return (n in this.attrs) ? this.attrs[n] : null; }
	appendChild(c) { c.parent = this; this.children.push(c); return c; }
	get parentElement() { return this.parent; }
	get nextElementSibling() {
		if (!this.parent) { return null; }
		const i = this.parent.children.indexOf(this);
		return (i >= 0 && i < this.parent.children.length - 1) ? this.parent.children[i + 1] : null;
	}
	get firstChild() { return this.children.length ? this.children[0] : null; }
	addEventListener(type, fn) { (this._listeners[type] = this._listeners[type] || []).push(fn); }
	remove() {
		if (!this.parent) { return; }
		const i = this.parent.children.indexOf(this);
		if (i >= 0) { this.parent.children.splice(i, 1); }
		this.parent = null;
	}
	after(el) {
		if (!this.parent) { return; }
		el.parent = this.parent;
		this.parent.children.splice(this.parent.children.indexOf(this) + 1, 0, el);
	}
	before(el) {
		if (!this.parent) { return; }
		el.parent = this.parent;
		this.parent.children.splice(this.parent.children.indexOf(this), 0, el);
	}
	_matches(sel) {
		if (sel === "input") { return this.tagName === "input"; }
		if (sel === 'select[name="fromop"]') { return this.tagName === "select" && this.attrs["name"] === "fromop"; }
		if (sel === "select.logical-operator") { return this.tagName === "select" && this.classes.indexOf("logical-operator") >= 0; }
		if (sel.charAt(0) === ".") { return this.classes.indexOf(sel.slice(1)) >= 0; }
		throw new Error("unsupported selector: " + sel);
	}
	*walk() { for (const c of this.children) { yield c; yield* c.walk(); } }
	querySelectorAll(sel) {
		if (sel === ":scope > .list-item") {
			return this.children.filter((c) => c.classes && c.classes.indexOf("list-item") >= 0);
		}
		const parts = sel.indexOf(",") >= 0 ? sel.split(",").map((s) => s.trim()) : [sel];
		const out = [];
		for (const n of this.walk()) {
			if (parts.some((p) => n._matches(p)) && out.indexOf(n) < 0) { out.push(n); }
		}
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
	{ id: 3, name: "CPU Load" },
	{ id: 4, name: "Uptime" }
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
group.appendChild(condRow("Deploy Test Sensor", "contains", "probe", null));
fromList.appendChild(r1);
fromList.appendChild(group);
// The group's trailing operator sits outside the group, as the siblings
// immediately after it (br, select, button)
const gbr = new El("br"); gbr.classes.push("logical-operator-br");
const gsel = new El("select", ["logical-operator"]); gsel.value = "AND";
const gbtn = new El("img", ["group-button"]);
fromList.appendChild(gbr);
fromList.appendChild(gsel);
fromList.appendChild(gbtn);
fromList.appendChild(condRow("Uptime", "greaterthan", "5", null));

const blocks = Q.collectCondBlocks(fromList, catalog);
ok("collect: three top-level blocks (row, group, row)",
	blocks.length === 3 && blocks[0].kind === "row" && blocks[1].kind === "group" && blocks[2].kind === "row");
ok("collect: row fields resolved",
	blocks[0].sid === 1 && blocks[0].op === "==" && blocks[0].value === "web-01" && blocks[0].opAfter === "AND");
ok("collect: group carries its rows and its trailing operator (outside the group)",
	blocks[1].blocks.length === 2 && blocks[1].blocks[0].sid === 3 && blocks[1].blocks[1].sid === 2 && blocks[1].opAfter === "AND");
ok("collect: the group's rows keep their inner operator; the last row has none",
	blocks[1].blocks[0].opAfter === "OR" && blocks[1].blocks[1].opAfter === null);
ok("collect: the row after the group", blocks[2].sid === 4 && blocks[2].opAfter === null);
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
ok("payload: conditions tree from the rows + group + trailing row",
	res.payload && eq(res.payload.conditions,
		{ logic: "AND",
			left: { logic: "AND",
				left: { sid: 1, op: "==", value: "web-01" },
				right: { logic: "OR", left: { sid: 3, op: ">", value: "10" }, right: { sid: 2, op: "=~", value: "probe" } } },
			right: { sid: 4, op: ">", value: "5" } }));

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

// --- the page's insertLogicalOperators (extracted from modules/query.php) ---
// The builder's inline JS is evaluated against the shim so the operator
// placement - in particular that a group's trailing operator sits OUTSIDE
// the group, below it - is covered offline.
const fs = require("fs");
const pageSrc = fs.readFileSync(path.join(__dirname, "..", "server", "console", "html", "modules", "query.php"), "utf8");
const inlineMatch = pageSrc.match(/<script>([\s\S]*?)<\/script>/);
ok("setup: the builder's inline script extracted", !!inlineMatch);
global.window = { addEventListener: () => {} };
global.Option = class Option extends El {
	constructor(text, value) { super("option"); this.text = text; this.value = value; }
};
// (the eval'd function declarations also land in this module's scope; the
// local binding is named differently to avoid the collision)
const pageInsertLogicalOperators = eval(inlineMatch[1] + "\n;insertLogicalOperators;");

function bareRow() {
	const el = new El("div", ["list-item"]);
	el.appendChild(new El("input"));
	const opSel = new El("select"); opSel.setAttribute("name", "fromop"); el.appendChild(opSel);
	el.appendChild(new El("input"));
	return el;
}
doc.byId["tsuffix"] = new El("span");

// Three plain rows: each operator sits inside the preceding row.
const fl1 = new El("div");
fl1.id = "from-list";
const a1 = bareRow(); const a2 = bareRow(); const a3 = bareRow();
fl1.appendChild(a1); fl1.appendChild(a2); fl1.appendChild(a3);
pageInsertLogicalOperators(fl1);
ok("page: a row's trailing operator sits inside the row",
	a1.children.length === 6 &&
	a1.children[3].classes.indexOf("logical-operator-br") >= 0 &&
	a1.children[4].classes.indexOf("logical-operator") >= 0 &&
	a1.children[5].classes.indexOf("group-button") >= 0);
ok("page: the last row carries no trailing operator", a3.children.length === 3);

// Row, group, row: the operator between the group and the last row must sit
// outside the group, below it (the reported bug: it rendered inside the
// group, on the group's last row).
const fl2 = new El("div");
fl2.id = "from-list";
const b1 = bareRow();
const g2 = new El("div", ["group-container"]);
const b2 = bareRow(); const b4 = bareRow();
g2.appendChild(b2); g2.appendChild(b4);
const b3 = bareRow();
fl2.appendChild(b1); fl2.appendChild(g2); fl2.appendChild(b3);
pageInsertLogicalOperators(fl2);
ok("page: the row above a group carries the collapse button inside the row",
	b1.children.length === 6 && b1.children[5].src === "/icons/collapsegroup.png");
ok("page: the group's trailing operator sits outside the group, below it",
	fl2.children[1] === g2 &&
	fl2.children[2].classes.indexOf("logical-operator-br") >= 0 &&
	fl2.children[3].classes.indexOf("logical-operator") >= 0 &&
	fl2.children[4].classes.indexOf("group-button") >= 0 &&
	fl2.children[5] === b3);
ok("page: the group's last row carries no trailing operator", b4.children.length === 3);
ok("page: the group's inner operator sits inside its first row", b2.children.length === 6);
ok("page: the sibling group button is the add button when a row follows",
	fl2.children[4].src === "/icons/addgroup.png");

// Group followed by group: the collapse button sits as a sibling after the
// first group.
const fl3 = new El("div");
fl3.id = "from-list";
const gA = new El("div", ["group-container"]);
gA.appendChild(bareRow()); gA.appendChild(bareRow());
const gB = new El("div", ["group-container"]);
gB.appendChild(bareRow()); gB.appendChild(bareRow());
fl3.appendChild(gA); fl3.appendChild(gB);
pageInsertLogicalOperators(fl3);
ok("page: group followed by group - the collapse button sits as a sibling after the first group",
	fl3.children[1].classes.indexOf("logical-operator-br") >= 0 &&
	fl3.children[2].classes.indexOf("logical-operator") >= 0 &&
	fl3.children[3].classes.indexOf("group-button") >= 0 &&
	fl3.children[3].src === "/icons/collapsegroup.png" &&
	fl3.children[4] === gB);

console.log("-".repeat(60));
if (failures) {
	console.log("FAILED: " + failures + " check(s) failed");
	process.exit(1);
}
console.log("All checks passed.");
process.exit(0);
