//
// console_sort_test.js - offline test for LuminumTable's column sort wiring
// (attachHeaderSort, reorderRows, setSortMarkers, headerCells), the
// click-to-sort behaviour of the console's list tables.
//
// attachHeaderSort is a DOM helper, so this harness installs a minimal DOM
// shim (just enough of Element/document for the operations the helpers use)
// and drives the sort by dispatching "click" on the header cells - the same
// way console_filter_test.js drives attachTextFilter.
//
// Usage: node tests/console_sort_test.js
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
// Supports the operations the sort helpers rely on: querySelector(All) for
// the selectors they use (tags, tag.class, .class, comma lists), closest,
// tr.cells, td.colSpan, className, createElement, appendChild/insertBefore/
// removeChild, nextSibling, addEventListener/dispatch.
class El {
	constructor(tag) {
		this.tagName = String(tag).toLowerCase();
		this.id = "";
		this.className = "";
		this.attrs = {};
		this.children = [];
		this.parent = null;
		this.style = {};
		this._text = "";
		this.colSpan = 1;
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
	get cells() { return this.children.filter((c) => c.tagName === "td"); }
	setAttribute(n, v) { this.attrs[n] = String(v); if (n === "id") { this.id = String(v); } }
	getAttribute(n) { return (n in this.attrs) ? this.attrs[n] : null; }
	appendChild(c) { c.parent = this; this.children.push(c); return c; }
	insertBefore(c, ref) {
		// Like the real DOM: the node is moved, not copied - it is removed
		// from its current position first.
		const at = this.children.indexOf(c);
		if (at !== -1) { this.children.splice(at, 1); }
		c.parent = this;
		const i = ref ? this.children.indexOf(ref) : -1;
		if (i === -1) { this.children.push(c); } else { this.children.splice(i, 0, c); }
		return c;
	}
	removeChild(c) {
		const i = this.children.indexOf(c);
		if (i !== -1) { this.children.splice(i, 1); c.parent = null; }
		return c;
	}
	closest(sel) {
		let n = this;
		while (n) { if (n._matches(sel)) { return n; } n = n.parent; }
		return null;
	}
	_matches(sel) {
		// Comma list: any part matching is a match.
		const parts = sel.split(",").map((s) => s.trim());
		return parts.some((p) => this._matchOne(p));
	}
	_matchOne(sel) {
		const m = sel.match(/^([a-z]*)(?:\.([a-z-]+))?$/i);
		if (!m || (!m[1] && !m[2])) { throw new Error("unsupported selector: " + sel); }
		if (m[1] && this.tagName !== m[1].toLowerCase()) { return false; }
		return m[2] ? this.className.split(/\s+/).indexOf(m[2]) !== -1 : true;
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
	dispatch(type, target) {
		(this._listeners[type] || []).forEach((fn) => fn({ target: target || this }));
	}
}

const doc = {
	createElement(tag) { return new El(tag) }
};
global.document = doc;

// --- build a server-rendered-style table ------------------------------------
// Counter row, a luminum-head header row (select-all checkbox cell first),
// three data rows, and a footer row - the shape of the static PHP list
// tables (Content Sets, Sensors, User Accounts, ...).
function buildTable() {
	const table = new El("table");

	const counterTr = new El("tr");
	const counterTd = new El("td"); counterTd.textContent = "3 of 3 items";
	counterTr.appendChild(counterTd);
	table.appendChild(counterTr);

	const headerTr = new El("tr");
	headerTr.className = "luminum-head";
	const headTd0 = new El("td");
	const selectall = new El("input");
	selectall.setAttribute("id", "selectall");
	headTd0.appendChild(selectall);
	headerTr.appendChild(headTd0);
	const headTd1 = new El("td"); headTd1.textContent = "Name"; headerTr.appendChild(headTd1);
	const headTd2 = new El("td"); headTd2.textContent = "Packages"; headerTr.appendChild(headTd2);
	const headTd3 = new El("td"); headTd3.textContent = "Owner"; headerTr.appendChild(headTd3);
	table.appendChild(headerTr);

	const dataRows = [];
	const data = [
		["Gamma", "3", "alice"],
		["Alpha", "10", "bob"],
		["Beta", "2", "alice"],
	];
	data.forEach((d, i) => {
		const tr = new El("tr");
		tr.className = "luminum-row";
		const td0 = new El("td");
		const cb = new El("input");
		cb.setAttribute("id", "ID" + (i + 1));
		td0.appendChild(cb);
		tr.appendChild(td0);
		d.forEach((v) => {
			const td = new El("td"); td.textContent = v; tr.appendChild(td);
		});
		table.appendChild(tr);
		dataRows.push(tr);
	});

	const footerTr = new El("tr");
	const footerTd = new El("td"); footerTd.textContent = "Query Completed in 0.00 Seconds";
	footerTr.appendChild(footerTd);
	table.appendChild(footerTr);

	return { table, headerTr, dataRows, footerTr };
}

function rowOrder(table) {
	return table.querySelectorAll("tr.luminum-row").map((tr) => tr.cells[1].textContent);
}
function markerIn(cell) {
	const m = cell.querySelector(".luminum-sort");
	return m ? m.textContent : null;
}

// --- run --------------------------------------------------------------------
const { table, headerTr, dataRows, footerTr } = buildTable();
const headCells = headerTr.cells;

LT.attachHeaderSort(table);

ok("initial: no sort marker", headCells.every((c) => markerIn(c) === null));
ok("initial: rows in server order", rowOrder(table).join(",") === "Gamma,Alpha,Beta");

// Click the Name header (physical column 1): ascending.
table.dispatch("click", headCells[1]);
ok("click Name: rows sorted ascending", rowOrder(table).join(",") === "Alpha,Beta,Gamma");
ok("click Name: up arrow in the Name header", markerIn(headCells[1]) === "\u25B2");
ok("click Name: no marker on the other headers",
	markerIn(headCells[0]) === null && markerIn(headCells[2]) === null && markerIn(headCells[3]) === null);
ok("click Name: the footer row stays last",
	table.children[table.children.length - 1] === footerTr);

// Click the same header again: descending.
table.dispatch("click", headCells[1]);
ok("repeat click Name: rows sorted descending", rowOrder(table).join(",") === "Gamma,Beta,Alpha");
ok("repeat click Name: down arrow", markerIn(headCells[1]) === "\u25BC");

// A third click on the same header clears the sort: the rows go back to
// the table's default (server-rendered) order and the marker is removed.
table.dispatch("click", headCells[1]);
ok("third click Name: sort cleared, default order restored",
	rowOrder(table).join(",") === "Gamma,Alpha,Beta");
ok("third click Name: no marker anywhere",
	headCells.every((c) => markerIn(c) === null));
// A fourth click starts the cycle fresh (ascending).
table.dispatch("click", headCells[1]);
ok("fourth click Name: fresh ascending sort",
	rowOrder(table).join(",") === "Alpha,Beta,Gamma" && markerIn(headCells[1]) === "\u25B2");

// Click a different header: fresh ascending sort, marker moves.
table.dispatch("click", headCells[2]);
ok("click Packages: ascending numeric (2 < 3 < 10)", rowOrder(table).join(",") === "Beta,Gamma,Alpha");
ok("click Packages: marker moved off Name",
	markerIn(headCells[1]) === null && markerIn(headCells[2]) === "\u25B2");

// And back down again.
table.dispatch("click", headCells[2]);
ok("repeat click Packages: descending", rowOrder(table).join(",") === "Alpha,Gamma,Beta");

// The select-all checkbox cell is not a sort column.
table.dispatch("click", headCells[0]);
ok("click the checkbox cell: no sort, no marker",
	rowOrder(table).join(",") === "Alpha,Gamma,Beta" &&
		headCells.every((c) => markerIn(c) === null || c === headCells[2]));

// A click outside the header row does nothing.
table.dispatch("click", dataRows[0]);
ok("click a data row: order and marker unchanged",
	rowOrder(table).join(",") === "Alpha,Gamma,Beta" && markerIn(headCells[2]) === "\u25BC");

// A third column: the ties (two rows owned by alice) keep their relative
// order from the previous sort.
table.dispatch("click", headCells[3]);
ok("click Owner: ascending, ties keep their relative order",
	rowOrder(table).join(",") === "Gamma,Beta,Alpha");
ok("click Owner: marker on the Owner header", markerIn(headCells[3]) === "\u25B2");
// ...and the cycle completes on this column too: descending (the tied
// alice rows keep their current relative order), then cleared back to the
// default order.
table.dispatch("click", headCells[3]);
ok("repeat click Owner: descending", rowOrder(table).join(",") === "Alpha,Gamma,Beta");
table.dispatch("click", headCells[3]);
ok("third click Owner: cleared, default order restored, marker gone",
	rowOrder(table).join(",") === "Gamma,Alpha,Beta" &&
		headCells.every((c) => markerIn(c) === null));

// Two-tier header (the query results page's split sensor): the physical
// order is the tier-1 spanning cells plus the tier-2 sub-label cells, and
// the marker lands on the sub-label cell.
const twoTierTable = new El("table");
const t1 = new El("tr"); t1.className = "luminum-head";
const t2 = new El("tr"); t2.className = "luminum-head";
const cbCell = new El("td");
const cbInput = new El("input"); cbInput.setAttribute("id", "qrselectall");
cbCell.appendChild(cbInput);
cbCell.colSpan = 1; cbCell.rowSpan = 2;
t1.appendChild(cbCell);
const nameCell = new El("td"); nameCell.textContent = "Computer Name"; nameCell.rowSpan = 2;
t1.appendChild(nameCell);
const splitCell = new El("td"); splitCell.textContent = "Installed Applications"; splitCell.colSpan = 2;
t1.appendChild(splitCell);
const countCell = new El("td"); countCell.textContent = "Count"; countCell.rowSpan = 2;
t1.appendChild(countCell);
const subName = new El("td"); subName.textContent = "Name"; t2.appendChild(subName);
const subVer = new El("td"); subVer.textContent = "Version"; t2.appendChild(subVer);
twoTierTable.appendChild(t1);
twoTierTable.appendChild(t2);

const phys = LT.headerCells(twoTierTable);
ok("headerCells: two-tier physical order (spanning cells + sub-labels)",
	phys.length === 5 &&
		phys[0] === cbCell && phys[1] === nameCell &&
		phys[2] === subName && phys[3] === subVer && phys[4] === countCell,
	phys.map((c) => c.textContent).join("|"));

LT.setSortMarkers(twoTierTable, { col: 3, dir: -1 });
ok("setSortMarkers: the marker lands on the sub-label cell",
	markerIn(subVer) === "\u25BC" &&
		markerIn(subName) === null && markerIn(nameCell) === null && markerIn(countCell) === null);
LT.setSortMarkers(twoTierTable, { col: 4, dir: 1 });
ok("setSortMarkers: re-sorting moves the marker",
	markerIn(subVer) === null && markerIn(countCell) === "\u25B2");
LT.setSortMarkers(twoTierTable, null);
ok("setSortMarkers: null clears every marker",
	[cbCell, nameCell, subName, subVer, countCell].every((c) => markerIn(c) === null));

// The onSort callback path (the data-driven tables): the callback receives
// the sort state and the DOM rows are left alone.
let lastSort = null;
const cbTable = buildTable().table;
LT.attachHeaderSort(cbTable, (sort) => { lastSort = sort; });
const cbHead = cbTable.querySelectorAll("tr.luminum-head")[0];
cbTable.dispatch("click", cbHead.cells[1]);
ok("onSort: the callback receives the sort state",
	lastSort && lastSort.col === 1 && lastSort.dir === 1);
ok("onSort: the DOM rows are not reordered (the page re-renders)",
	rowOrder(cbTable).join(",") === "Gamma,Alpha,Beta");
ok("onSort: the marker is still placed", markerIn(cbHead.cells[1]) === "\u25B2");
// The cycle continues through the callback: descending, then cleared -
// the callback receives null and the marker is removed.
cbTable.dispatch("click", cbHead.cells[1]);
ok("onSort: the repeat click receives the descending state",
	lastSort && lastSort.col === 1 && lastSort.dir === -1);
cbTable.dispatch("click", cbHead.cells[1]);
ok("onSort: the third click receives null (sort cleared)", lastSort === null);
ok("onSort: the marker is removed on clear", markerIn(cbHead.cells[1]) === null);

console.log("-".repeat(60));
if (failures) {
	console.log("FAILED: " + failures + " check(s) failed");
	process.exit(1);
}
console.log("All checks passed.");
process.exit(0);
