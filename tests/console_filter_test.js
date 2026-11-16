//
// console_filter_test.js - offline test for LuminumTable.attachTextFilter,
// the live text filter used by the server-rendered console pages (Content
// Sets, Sensors, Packages, User Accounts, the group/action lists).
//
// attachTextFilter is a DOM helper, so this harness installs a minimal DOM
// shim (just enough of Element/document for the operations the helper uses)
// and drives the filter by setting the input value and dispatching "input".
//
// Usage: node tests/console_filter_test.js
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

// --- minimal DOM shim -------------------------------------------------------
// Supports exactly the operations attachTextFilter relies on: getElementById,
// createElement, closest, querySelector(All) for the selectors it uses,
// setAttribute, appendChild/insertBefore, style, textContent, addEventListener.
class El {
	constructor(tag) {
		this.tagName = String(tag).toLowerCase();
		this.id = "";
		this.attrs = {};
		this.children = [];
		this.parent = null;
		this.style = {};
		this._text = "";
		this.value = "";
		this.colSpan = 0;
		this._listeners = {};
	}
	get textContent() {
		let t = this._text;
		for (const c of this.children) { t += c.textContent; }
		return t;
	}
	set textContent(v) { this._text = String(v); this.children = []; }
	get parentNode() { return this.parent; }
	get nextSibling() {
		if (!this.parent) { return null; }
		const i = this.parent.children.indexOf(this);
		return (i >= 0 && i < this.parent.children.length - 1) ? this.parent.children[i + 1] : null;
	}
	setAttribute(n, v) { this.attrs[n] = String(v); if (n === "id") { this.id = String(v); } }
	getAttribute(n) { return (n in this.attrs) ? this.attrs[n] : null; }
	appendChild(c) { c.parent = this; this.children.push(c); return c; }
	insertBefore(c, ref) {
		c.parent = this;
		const i = ref ? this.children.indexOf(ref) : -1;
		if (i === -1) { this.children.push(c); } else { this.children.splice(i, 0, c); }
		return c;
	}
	closest(tag) {
		let n = this;
		while (n) { if (n.tagName === String(tag).toLowerCase()) { return n; } n = n.parent; }
		return null;
	}
	_matches(sel) {
		if (sel === "tr" || sel === "td" || sel === "input") { return this.tagName === sel; }
		if (sel === 'input[id^="ID"]') { return this.tagName === "input" && this.id.indexOf("ID") === 0; }
		if (sel === "tr[data-luminum-empty]") { return this.tagName === "tr" && ("data-luminum-empty" in this.attrs); }
		throw new Error("unsupported selector: " + sel);
	}
	querySelectorAll(sel) {
		const out = [];
		const walk = (n) => {
			for (const c of n.children) {
				if (c._matches(sel)) { out.push(c); }
				walk(c);
			}
		};
		walk(this);
		return out;
	}
	querySelector(sel) { const r = this.querySelectorAll(sel); return r.length ? r[0] : null; }
	addEventListener(type, fn) { (this._listeners[type] = this._listeners[type] || []).push(fn); }
	dispatch(type) { (this._listeners[type] || []).forEach((fn) => fn({ target: this })); }
}

// Build a table that mirrors a server-rendered page: a counter row holding the
// filter input, a header row (select-all checkbox), three data rows (each with
// an input id="IDn"), and a footer row. Returns { table, filter, dataRows }.
function buildTable() {
	const table = new El("table");

	const counterTr = new El("tr");
	const counterTd = new El("td");
	const filter = new El("input");
	filter.setAttribute("id", "csetsfilter");
	counterTd.appendChild(filter);
	counterTr.appendChild(counterTd);
	table.appendChild(counterTr);

	const headerTr = new El("tr");
	const headTd0 = new El("td");
	const selectall = new El("input");
	selectall.setAttribute("id", "selectall");
	headTd0.appendChild(selectall);
	headerTr.appendChild(headTd0);
	const headTd1 = new El("td"); headTd1.textContent = "Name"; headerTr.appendChild(headTd1);
	const headTd2 = new El("td"); headTd2.textContent = "Description"; headerTr.appendChild(headTd2);
	table.appendChild(headerTr);

	const dataRows = [];
	const names = [["Alpha", "First set"], ["Beta", "Second set"], ["Gamma", "Third set"]];
	names.forEach((pair, i) => {
		const tr = new El("tr");
		const td0 = new El("td");
		const cb = new El("input");
		cb.setAttribute("id", "ID" + (i + 1));
		td0.appendChild(cb);
		tr.appendChild(td0);
		const td1 = new El("td"); td1.textContent = pair[0]; tr.appendChild(td1);
		const td2 = new El("td"); td2.textContent = pair[1]; tr.appendChild(td2);
		table.appendChild(tr);
		dataRows.push(tr);
	});

	const footerTr = new El("tr");
	const footerTd = new El("td"); footerTd.textContent = "Query Completed in 0.00 Seconds";
	footerTr.appendChild(footerTd);
	table.appendChild(footerTr);

	return { table, filter, dataRows };
}

function visible(tr) { return tr.style.display !== "none"; }

// --- run --------------------------------------------------------------------
const doc = {
	_root: null,
	getElementById(id) {
		const find = (n) => {
			if (n.id === id) { return n; }
			for (const c of n.children) { const r = find(c); if (r) { return r; } }
			return null;
		};
		return this._root ? find(this._root) : null;
	},
	createElement(tag) { return new El(tag); }
};
global.document = doc;

const { table, filter, dataRows } = buildTable();
doc._root = table;

ok("setup: three data rows present", dataRows.length === 3);

LT.attachTextFilter("csetsfilter");

// A "No Results" row is created (hidden) because the table has data rows but
// no empty row in the markup.
let emptyRow = table.querySelector("tr[data-luminum-empty]");
ok("No Results row created", !!emptyRow);
ok("No Results row hidden initially", emptyRow && !visible(emptyRow));
ok("No Results row colspan matches data row", emptyRow && emptyRow.children[0].colSpan === 3);
ok("No Results row text", emptyRow && emptyRow.textContent === "No Results");

// All rows visible with an empty filter.
ok("empty filter: all rows visible", dataRows.every(visible));

// Case-insensitive substring match hides non-matching rows.
filter.value = "alpha";
filter.dispatch("input");
ok("filter 'alpha': only Alpha row visible",
	visible(dataRows[0]) && !visible(dataRows[1]) && !visible(dataRows[2]));
ok("filter 'alpha': No Results hidden", !visible(emptyRow));

// Uppercase input still matches (case-insensitive).
filter.value = "BETA";
filter.dispatch("input");
ok("filter 'BETA': only Beta row visible",
	!visible(dataRows[0]) && visible(dataRows[1]) && !visible(dataRows[2]));

// Matching a non-name column (description) also works.
filter.value = "third";
filter.dispatch("input");
ok("filter 'third': matches description column",
	!visible(dataRows[0]) && !visible(dataRows[1]) && visible(dataRows[2]));

// No match hides every row and shows "No Results".
filter.value = "zzz";
filter.dispatch("input");
ok("filter 'zzz': all rows hidden", dataRows.every((tr) => !visible(tr)));
ok("filter 'zzz': No Results shown", visible(emptyRow));

// Clearing the filter restores every row and hides "No Results".
filter.value = "";
filter.dispatch("input");
ok("cleared filter: all rows visible again", dataRows.every(visible));
ok("cleared filter: No Results hidden again", !visible(emptyRow));

// A filter id that does not exist is a safe no-op (stub pages render no rows).
ok("attachTextFilter: unknown id is a no-op", (function () {
	try { LT.attachTextFilter("does-not-exist"); return true; }
	catch (e) { return false; }
})());

console.log("-".repeat(60));
if (failures) {
	console.log("FAILED: " + failures + " check(s) failed");
	process.exit(1);
}
console.log("All checks passed.");
process.exit(0);
