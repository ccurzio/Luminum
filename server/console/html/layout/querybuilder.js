//
// LuminumQueryBuilder — the query wiring for the query builder page
// (modules/query.php).
//
// The builder's markup and its own JS (row add/remove, drag-sort, grouping,
// the AND/OR operators between the condition rows) live on the page; this
// module turns what the operator typed into the /api/commands.php query
// statement (protocol 7.3): the retrieve sensors (the typed sensor fields,
// resolved to sensor IDs), the condition tree (the From rows, groups folded
// in), and the broadcast target. Only the endpoints on which the condition
// tree evaluates true answer. It also drives the sensor autocomplete (a
// dropdown of sensors whose name starts with the text being typed) and
// re-points each condition row's operator options at the chosen sensor's
// result type (CONTENT.SENSORS.RTYPE): text/ipaddress compare as strings,
// number/datetime numerically. A condition row's operator dropdown and
// value field stay disabled until the row's sensor field resolves to a
// valid sensor, and queryStructure renders a query payload as the full
// text-based interpretation the Saved Queries table's Structure column
// shows. Copy to Builder (the Saved Queries tab's form button) copies the
// selected saved query back into the builder form and switches to the
// Query Builder tab: the selected row's checkbox carries the query's JSON
// payload in data-payload, condTreeToRows turns the condition tree back
// into the builder's row sequence, and populateBuilder rebuilds the
// retrieve rows, the target, and the condition rows.
//
// The pure functions (findSensor, resolveSensorId, filterSensors,
// opsForType, condBlocksToTree, condTreeToRows, findUnresolved,
// findUnresolvedAll, queryStructure) are DOM-free so they can be
// unit-tested under Node. The DOM helpers (applyOpsToSelect, applyRowType,
// normalizeRows, collectCondBlocks, condRowsStatus, invalidSensorNames,
// submitEnabled, buildQueryPayload, populateBuilder, copyToBuilder, init)
// only run in the browser.
//
(function (root, factory) {
	if (typeof module === 'object' && module.exports) {
		module.exports = factory();
	} else {
		root.LuminumQueryBuilder = factory();
	}
}(typeof self !== 'undefined' ? self : this, function () {
	'use strict';

	// The builder's operator dropdown values -> the protocol's operators (7.3).
	const COND_OPS = {
		equals: '==', notequals: '!=', contains: '=~', notcontains: '!~',
		greaterthan: '>', greaterorequal: '>=', lessthan: '<', lessorequal: '<='
	};

	// The protocol's operators (7.3) -> the builder's operator dropdown
	// values (COND_OPS reversed) - Copy to Builder re-points a saved
	// query's condition operators at the dropdown.
	const PROTOCOL_OP_KEYS = {
		'==': 'equals', '!=': 'notequals', '=~': 'contains', '!~': 'notcontains',
		'>': 'greaterthan', '>=': 'greaterorequal', '<': 'lessthan', '<=': 'lessorequal'
	};

	// The condition operator options, by the sensor's result type
	// (CONTENT.SENSORS.RTYPE). The option VALUES stay the COND_OPS keys so
	// collectCondBlocks maps them to the protocol operators; only the labels
	// and which options are offered change with the type. text and ipaddress
	// compare as strings (word labels); number and datetime compare
	// numerically (the comparison symbols). DEFAULT_OPS is the full set shown
	// before a row's sensor resolves (or for an unknown type).
	const DEFAULT_OPS = [
		{ value: 'equals', label: '==' },
		{ value: 'notequals', label: '!=' },
		{ value: 'contains', label: '=~' },
		{ value: 'notcontains', label: '!~' },
		{ value: 'greaterthan', label: '>' },
		{ value: 'greaterorequal', label: '>=' },
		{ value: 'lessthan', label: '<' },
		{ value: 'lessorequal', label: '<=' }
	];
	const TEXT_OPS = [
		{ value: 'equals', label: 'matches' },
		{ value: 'notequals', label: 'does not match' },
		{ value: 'contains', label: 'contains' },
		{ value: 'notcontains', label: 'does not contain' }
	];
	const NUMERIC_OPS = [
		{ value: 'equals', label: '==' },
		{ value: 'notequals', label: '!=' },
		{ value: 'greaterthan', label: '>' },
		{ value: 'greaterorequal', label: '>=' },
		{ value: 'lessthan', label: '<' },
		{ value: 'lessorequal', label: '<=' }
	];

	// The operator options for a sensor's result type (CONTENT.SENSORS.RTYPE):
	// text and ipaddress compare as strings, number and datetime numerically.
	// An unknown or missing type keeps the full default set.
	function opsForType(rtype) {
		switch (String(rtype === null || rtype === undefined ? '' : rtype).toLowerCase()) {
			case 'text':
			case 'ipaddress': return TEXT_OPS;
			case 'number':
			case 'datetime': return NUMERIC_OPS;
			default: return DEFAULT_OPS;
		}
	}

	// Resolve the text the operator typed in a Sensor field to the sensor
	// object (or null): a numeric field that matches a sensor ID wins,
	// otherwise the sensor name (case-insensitive).
	function findSensor(catalog, text) {
		const t = String(text === null || text === undefined ? '' : text).trim();
		if (t === '') { return null; }
		if (/^[0-9]+$/.test(t)) {
			const id = parseInt(t, 10);
			for (const s of catalog) { if (s.id === id) { return s; } }
		}
		const lt = t.toLowerCase();
		for (const s of catalog) { if (String(s.name).toLowerCase() === lt) { return s; } }
		return null;
	}

	// Resolve the typed sensor text to a sensor ID (null when nothing matches).
	function resolveSensorId(catalog, text) {
		const s = findSensor(catalog, text);
		return s ? s.id : null;
	}

	// The sensors whose name starts with the typed text (case-insensitive) -
	// the autocomplete dropdown's matches. An empty text matches every sensor.
	function filterSensors(catalog, text) {
		const t = String(text === null || text === undefined ? '' : text).trim().toLowerCase();
		if (t === '') { return catalog.slice(); }
		return catalog.filter((s) => String(s.name).toLowerCase().indexOf(t) === 0);
	}

	// Build the protocol condition tree (7.3) from a normalized block list:
	//   { kind: 'row', sensor, value, sid, op, opAfter }
	//   { kind: 'group', blocks: [...], opAfter }
	// opAfter is the AND/OR that joins the block to the next one (null =
	// AND). Rows left entirely empty are skipped (their opAfter still
	// applies to the next real row); a group whose rows are all empty drops
	// out. The tree folds left-associatively, matching how the page lays
	// the operators out between the blocks.
	function condBlocksToTree(blocks) {
		let tree = null;
		let op = 'AND';
		for (const b of blocks) {
			const nextOp = b.opAfter || 'AND';
			let node = null;
			if (b.kind === 'group') {
				node = condBlocksToTree(b.blocks);
			} else if (b.sensor !== '' || b.value !== '') {
				node = { sid: b.sid, op: b.op, value: b.value };
			}
			if (node !== null) {
				if (tree === null) { tree = node; }
				else { tree = { logic: op, left: tree, right: node }; }
			}
			op = nextOp;
		}
		return tree;
	}

	// The condition tree's in-order row sequence - what Copy to Builder
	// reconstructs in the builder's From list: one entry per leaf, in the
	// order the builder's rows lay them out (the tree folds
	// left-associatively, so the in-order traversal is the row sequence),
	// each carrying the AND/OR that joins it to the next row (opAfter,
	// null on the last row).
	function condTreeToRows(tree) {
		const rows = [];
		(function walk(node) {
			if (!node) { return; }
			if (node.logic) {
				walk(node.left);
				// node.logic joins the last row emitted so far (the left
				// subtree's last leaf) to the next one (the right subtree's
				// first leaf)
				if (rows.length) { rows[rows.length - 1].opAfter = node.logic; }
				walk(node.right);
			} else {
				rows.push({ sid: node.sid, op: node.op, value: node.value, opAfter: null });
			}
		})(tree);
		return rows;
	}

	// Walk the From list (rows and group containers, recursively) into the
	// normalized block list condBlocksToTree builds from. The trailing
	// AND/OR of a row sits inside the row; the trailing AND/OR of a group
	// sits outside the group, as the siblings immediately after it (br,
	// select, button) - the page's insertLogicalOperators puts them there.
	function collectCondBlocks(container, catalog) {
		const blocks = [];
		const kids = Array.from(container.children);
		for (let i = 0; i < kids.length; i++) {
			const el = kids[i];
			if (!el.classList) { continue; }
			if (el.classList.contains('list-item')) {
				const inputs = el.querySelectorAll('input');
				const sensor = inputs.length > 0 ? String(inputs[0].value).trim() : '';
				// A bool row (tagged by applyRowType) holds its value in the
				// TRUE/FALSE <select> and always compares with "=="; any other
				// row reads the value <input> and the operator <select>.
				let value;
				let op;
				if (el.classList.contains('bool-row')) {
					const bv = el.querySelector('select.bool-value');
					value = bv ? String(bv.value).trim() : '';
					op = '==';
				} else {
					value = inputs.length > 1 ? String(inputs[1].value).trim() : '';
					const opSel = el.querySelector('select[name="fromop"]');
					op = COND_OPS[opSel ? opSel.value : 'equals'] || '==';
				}
				const afterSel = el.querySelector('select.logical-operator');
				blocks.push({
					kind: 'row',
					sensor: sensor,
					value: value,
					sid: sensor === '' ? null : resolveSensorId(catalog, sensor),
					op: op,
					opAfter: afterSel ? afterSel.value : null
				});
			} else if (el.classList.contains('group-container')) {
				let afterSel = null;
				const br = kids[i + 1];
				if (br && br.classList && br.classList.contains('logical-operator-br')) {
					const sel = kids[i + 2];
					if (sel && sel.classList && sel.classList.contains('logical-operator')) { afterSel = sel; }
				}
				blocks.push({
					kind: 'group',
					blocks: collectCondBlocks(el, catalog),
					opAfter: afterSel ? afterSel.value : null
				});
			}
		}
		return blocks;
	}

	// The first non-empty row whose sensor text resolves to no sensor.
	function findUnresolved(blocks) {
		for (const b of blocks) {
			if (b.kind === 'group') {
				const r = findUnresolved(b.blocks);
				if (r !== null) { return r; }
			} else if (b.sensor !== '' && b.sid === null) {
				return b.sensor;
			}
		}
		return null;
	}

	// Every non-empty sensor text in a normalized block list that resolves
	// to no sensor (findUnresolved returns only the first) - deduplicated,
	// in first-occurrence order, groups walked recursively.
	function findUnresolvedAll(blocks) {
		const out = [];
		for (const b of blocks) {
			if (b.kind === 'group') {
				for (const n of findUnresolvedAll(b.blocks)) {
					if (out.indexOf(n) < 0) { out.push(n); }
				}
			} else if (b.sensor !== '' && b.sid === null) {
				if (out.indexOf(b.sensor) < 0) { out.push(b.sensor); }
			}
		}
		return out;
	}

	// 'empty' | 'incomplete' | 'ok' for the From list: a row with a value
	// but no sensor is incomplete; a group is incomplete when any of its
	// rows is.
	function condRowsStatus(container) {
		let status = 'empty';
		for (const el of Array.from(container.children)) {
			if (!el.classList) { continue; }
			let s;
			if (el.classList.contains('group-container')) {
				s = condRowsStatus(el);
			} else if (el.classList.contains('list-item')) {
				const inputs = el.querySelectorAll('input');
				const sensor = inputs.length > 0 ? String(inputs[0].value).trim() : '';
				// A bool row's value is the TRUE/FALSE <select> (always set);
				// any other row's value is the value <input>.
				let value;
				if (el.classList.contains('bool-row')) {
					const bv = el.querySelector('select.bool-value');
					value = bv ? String(bv.value).trim() : '';
				} else {
					value = inputs.length > 1 ? String(inputs[1].value).trim() : '';
				}
				if (sensor === '' && value === '') { s = 'empty'; }
				else if (sensor === '') { s = 'incomplete'; }
				else { s = 'ok'; }
			} else { continue; }
			if (s === 'incomplete') { return 'incomplete'; }
			if (s === 'ok') { status = 'ok'; }
		}
		return status;
	}

	// Replace a condition operator <select>'s options with the given set,
	// keeping the current selection when it is still offered (otherwise the
	// first option). The select element itself (name, class, styles) is left
	// untouched - only its <option> children are rebuilt.
	function applyOpsToSelect(select, ops) {
		if (!select) { return; }
		const prev = select.value;
		while (select.children.length) { select.children[0].remove(); }
		for (const op of ops) { select.appendChild(new Option(op.label, op.value)); }
		select.value = ops.some((o) => o.value === prev) ? prev : ops[0].value;
	}

	// Configure a condition row's operator and value controls for the sensor
	// its field currently names. A bool sensor (CONTENT.SENSORS.RTYPE 'bool')
	// shows a static "==" and a TRUE/FALSE value dropdown: the operator
	// <select> and the value <input> are hidden, the row is tagged "bool-row",
	// and the bool controls are shown. Any other sensor (or an empty/unknown
	// field) shows the operator <select> (its options set to the sensor's
	// result type) and the value <input>. The operator <select> and the value
	// <input> are disabled while the field is empty or names no sensor -
	// they only take a value for a row whose sensor resolves - and enabled
	// once it does. collectCondBlocks and condRowsStatus read the "bool-row"
	// class to know which controls hold the row's value and op. Retrieve rows
	// carry none of these controls, so this is a no-op.
	function applyRowType(catalog, input) {
		let row = input;
		while (row && !(row.classList && row.classList.contains('list-item'))) { row = row.parentElement || null; }
		if (!row || !row.querySelector) { return; }
		const opSel = row.querySelector('select[name="fromop"]');
		const boolOp = row.querySelector('span.bool-op');
		const valInp = row.querySelector('input[placeholder="Value"]');
		const boolVal = row.querySelector('select.bool-value');
		if (!opSel && !boolOp && !valInp && !boolVal) { return; }
		const text = String(input.value === null || input.value === undefined ? '' : input.value).trim();
		const sensor = text === '' ? null : findSensor(catalog, text);
		const isBool = !!sensor && String(sensor.rtype === null || sensor.rtype === undefined ? '' : sensor.rtype).toLowerCase() === 'bool';

		if (isBool) {
			if (!row.classList.contains('bool-row')) { row.classList.add('bool-row'); }
			if (opSel) { opSel.style.display = 'none'; opSel.disabled = !sensor; }
			if (valInp) { valInp.style.display = 'none'; valInp.disabled = !sensor; }
			if (boolOp) { boolOp.style.display = 'inline-block'; }
			if (boolVal) { boolVal.style.display = ''; }
		} else {
			if (row.classList.contains('bool-row')) { row.classList.remove('bool-row'); }
			if (opSel) { opSel.style.display = ''; opSel.disabled = !sensor; }
			if (valInp) { valInp.style.display = ''; valInp.disabled = !sensor; }
			if (boolOp) { boolOp.style.display = 'none'; }
			if (boolVal) { boolVal.style.display = 'none'; }
			if (opSel) { applyOpsToSelect(opSel, sensor ? opsForType(sensor.rtype) : DEFAULT_OPS); }
		}
	}

	// Read the builder (the retrieve fields, the From dropdown, the
	// condition rows) and build the /api/commands.php query statement.
	// Returns { payload } or { error }.
	function buildQueryPayload(catalog) {
		const sensors = [];
		const getContainer = document.getElementById('get-list');
		if (getContainer) {
			for (const row of Array.from(getContainer.children)) {
				if (!row.classList || !row.classList.contains('list-item')) { continue; }
				const inp = row.querySelector('input');
				const t = inp ? String(inp.value).trim() : '';
				if (t === '') { continue; }
				const sid = resolveSensorId(catalog, t);
				if (sid === null) { return { error: 'No such sensor: ' + t }; }
				if (!sensors.some((s) => s.sid === sid)) { sensors.push({ sid: sid }); }
			}
		}
		if (sensors.length === 0) {
			return { error: 'Name at least one sensor to retrieve.' };
		}

		// The query always goes to the all-endpoints broadcast; the
		// conditions decide which endpoints answer (protocol 7.3).
		const payload = { target: 'all', action: 'query', sensors: sensors };
		const targets = document.getElementById('targets');
		if (targets && targets.value === 'matching') {
			const fromContainer = document.getElementById('from-list');
			const blocks = fromContainer ? collectCondBlocks(fromContainer, catalog) : [];
			const unresolved = findUnresolved(blocks);
			if (unresolved !== null) {
				return { error: 'No such sensor: ' + unresolved };
			}
			const tree = condBlocksToTree(blocks);
			if (tree === null) {
				return { error: 'Add a condition sensor to filter the endpoints.' };
			}
			payload.conditions = tree;
		}
		return { payload: payload };
	}

	// The full text-based interpretation of a query payload (the
	// /api/commands.php statement buildQueryPayload builds) - the content of
	// the Saved Queries table's Structure column:
	//   "Retrieve Hostname, CPU Load from all endpoints"
	//   "Retrieve Hostname from endpoints matching: Hostname matches web-01 AND CPU Load > 10"
	// The condition tree is walked in-order: it folds left-associatively
	// from the builder's rows, so the in-order traversal is exactly the row
	// sequence with the AND/OR between the rows. Each leaf renders as
	// "<sensor> <operator> <value>", the operator as the sensor's
	// result-type word label where the builder offers one (text/ipaddress:
	// matches / does not match / contains / does not contain), the
	// comparison symbol for number/datetime, and "is" for a bool sensor's
	// "==" (its value is TRUE/FALSE). A sid missing from the catalog
	// renders as "Sensor <id>".
	function queryStructure(catalog, payload) {
		if (!payload) { return ''; }
		const byId = {};
		for (const s of catalog) { byId[s.id] = s; }
		const name = (sid) => {
			const s = byId[sid];
			return s ? s.name : 'Sensor ' + sid;
		};
		const opLabel = (sid, op) => {
			const s = byId[sid];
			const rt = s ? String(s.rtype === null || s.rtype === undefined ? '' : s.rtype).toLowerCase() : '';
			if (rt === 'bool') { return 'is'; }
			if (rt === 'text' || rt === 'ipaddress') {
				switch (op) {
					case '==': return 'matches';
					case '!=': return 'does not match';
					case '=~': return 'contains';
					case '!~': return 'does not contain';
					default: return op;
				}
			}
			return op;
		};
		const parts = [];
		(function walk(node) {
			if (!node) { return; }
			if (node.logic) {
				walk(node.left);
				parts.push(node.logic);
				walk(node.right);
			} else {
				parts.push(name(node.sid) + ' ' + opLabel(node.sid, node.op) + ' ' + node.value);
			}
		})(payload.conditions);
		const sensors = (payload.sensors || []).map((s) => name(s.sid)).join(', ');
		const head = 'Retrieve ' + sensors + ' from ';
		if (payload.conditions) {
			const cond = parts.join(' ');
			return head + 'endpoints matching' + (cond !== '' ? ': ' + cond : '');
		}
		return head + 'all endpoints';
	}

	// Every query error is shown through the forced-focus overlay with an
	// OK button that hides it and returns the operator to the form.
	function showError(title, message) {
		LuminumOverlay.show({
			title: title,
			message: message,
			buttons: [{ label: 'OK', onclick: function () { LuminumOverlay.hide(); } }]
		});
	}

	// Populate the (pristine) builder form from a query payload: one
	// retrieve row per requested sensor (resolved to its name), the target
	// dropdown (endpoints matching when the payload carries conditions, all
	// endpoints otherwise), and the condition rows reconstructed from the
	// tree's in-order row sequence - the operator dropdown re-pointed at
	// the protocol operator, the value field filled, and the AND/OR between
	// the rows set on the trailing operator selects. Rows are added through
	// the last row's own add button (the page's addRow) so the remove
	// buttons, drag handles, and handlers stay consistent; normalizeRows
	// then re-points each row's operator options and disabled state at the
	// sensor it now names (a bool row swaps to its TRUE/FALSE select). A
	// sid missing from the catalog renders as "Sensor <id>" (the builder
	// then flags it as an unknown sensor and keeps Run Query disabled).
	function populateBuilder(catalog, payload) {
		const byId = {};
		for (const s of catalog) { byId[s.id] = s; }
		const name = (sid) => {
			const s = byId[sid];
			return s ? s.name : 'Sensor ' + sid;
		};
		const getContainer = document.getElementById('get-list');
		const fromContainer = document.getElementById('from-list');
		if (!getContainer || !fromContainer) { return; }
		const getRows = () => Array.from(getContainer.querySelectorAll('.list-item'));
		const fromRows = () => Array.from(fromContainer.querySelectorAll('.list-item'));

		// Retrieve sensors: the first template row takes the first sensor,
		// each further sensor is added through the last row's add button
		const sensors = payload.sensors || [];
		if (sensors.length > 0) {
			getRows()[0].querySelector('input').value = name(sensors[0].sid);
			for (let i = 1; i < sensors.length; i++) {
				const last = getRows()[getRows().length - 1];
				last.querySelector('.add').click();
				getRows()[getRows().length - 1].querySelector('input').value = name(sensors[i].sid);
			}
		}

		// Target: conditions present -> endpoints matching (the reset
		// default), otherwise all endpoints
		const targets = document.getElementById('targets');
		if (targets) {
			targets.value = payload.conditions ? 'matching' : 'all';
			if (typeof selectSuffix === 'function') { selectSuffix(); }
		}

		// Conditions: the tree's in-order row sequence - the first template
		// row takes the first condition, each further row is added through
		// the last row's add button
		const rows = payload.conditions ? condTreeToRows(payload.conditions) : [];
		if (rows.length > 0) {
			const setRow = (rowEl, r) => {
				const inputs = rowEl.querySelectorAll('input');
				if (inputs.length > 0) { inputs[0].value = name(r.sid); }
				const opSel = rowEl.querySelector('select[name="fromop"]');
				if (opSel) { opSel.value = PROTOCOL_OP_KEYS[r.op] || 'equals'; }
				const valInp = rowEl.querySelector('input[placeholder="Value"]');
				if (valInp) { valInp.value = r.value; }
				const boolVal = rowEl.querySelector('select.bool-value');
				if (boolVal) { boolVal.value = r.value; }
			};
			setRow(fromRows()[0], rows[0]);
			for (let i = 1; i < rows.length; i++) {
				const last = fromRows()[fromRows().length - 1];
				last.querySelector('.add').click();
				setRow(fromRows()[fromRows().length - 1], rows[i]);
			}
			// The AND/OR between the rows: insertLogicalOperators (run by
			// each add) created the trailing selects, so set them once all
			// rows exist
			fromRows().forEach((rowEl, i) => {
				if (i >= rows.length - 1) { return; }
				const sel = rowEl.querySelector('select.logical-operator');
				if (sel && rows[i].opAfter) { sel.value = rows[i].opAfter; }
			});
			// Re-point each row's operator options and disabled state at
			// the sensor it now names
			normalizeRows(catalog);
		}

		// Lead with the first retrieve field, like the page does on load
		const firstField = getContainer.querySelector('input');
		if (firstField && typeof firstField.focus === 'function') { firstField.focus(); }
	}

	// Copy the selected saved query into the builder form and switch to the
	// Query Builder tab (the "Copy to Builder" button on the Saved Queries
	// tab). Exactly one saved query must be selected: its row's checkbox
	// (class "savedqueryrow") carries the query's JSON payload in
	// data-payload (the /api/commands.php statement). Zero or multiple
	// selections, or an unreadable payload, show an overlay and leave the
	// builder untouched.
	function copyToBuilder(catalog) {
		const checked = Array.from(document.querySelectorAll('.savedqueryrow'))
			.filter((cb) => cb.checked);
		if (checked.length === 0) {
			showError('No Query Selected', 'Select a saved query to copy.');
			return;
		}
		if (checked.length > 1) {
			showError('Multiple Queries Selected', 'Select exactly one saved query to copy.');
			return;
		}
		const raw = checked[0].getAttribute('data-payload');
		let payload = null;
		if (raw) {
			try { payload = JSON.parse(raw); } catch (e) { payload = null; }
		}
		if (!payload) {
			showError('Copy Failed', 'The selected saved query could not be read.');
			return;
		}
		// Reset to the pristine builder first (the page's resetForm
		// restores the template rows, the matching target, and the
		// singular suffix, and re-inits the sortable lists)
		if (typeof resetForm === 'function') { resetForm(); }
		// Switch to the Query Builder tab (its tab button runs switchTab,
		// which also swaps the form button back to Reset Form) - before the
		// populate, so the populate's final focus on the first retrieve
		// field is not stolen by the tab button click
		for (const t of Array.from(document.querySelectorAll('.tablink'))) {
			if (t.textContent === 'Query Builder') { t.click(); break; }
		}
		populateBuilder(catalog, payload);
	}

	// Every sensor the operator typed (the retrieve fields and, when the
	// conditions are part of the query, the condition rows - groups
	// included) that resolves to no sensor - deduplicated, retrieve list
	// first, in first-occurrence order. Empty when the builder names only
	// real sensors (or none at all). The condition rows are only scanned
	// for the "endpoints matching" target, mirroring buildQueryPayload
	// (for "all endpoints" the rows are ignored by the query).
	function invalidSensorNames(catalog) {
		const out = [];
		const getContainer = document.getElementById('get-list');
		if (getContainer) {
			for (const row of Array.from(getContainer.children)) {
				if (!row.classList || !row.classList.contains('list-item')) { continue; }
				const inp = row.querySelector('input');
				const t = inp ? String(inp.value).trim() : '';
				if (t === '') { continue; }
				if (resolveSensorId(catalog, t) === null && out.indexOf(t) < 0) { out.push(t); }
			}
		}
		const targets = document.getElementById('targets');
		if (targets && targets.value === 'matching') {
			const fromContainer = document.getElementById('from-list');
			if (fromContainer) {
				for (const n of findUnresolvedAll(collectCondBlocks(fromContainer, catalog))) {
					if (out.indexOf(n) < 0) { out.push(n); }
				}
			}
		}
		return out;
	}

	// Whether the Submit button is enabled: at least one retrieve sensor,
	// the condition rows complete when conditions are required, and no
	// typed sensor (retrieve or condition) fails to resolve.
	function submitEnabled(catalog) {
		const getContainer = document.getElementById('get-list');
		let count = 0;
		if (getContainer) {
			for (const row of Array.from(getContainer.children)) {
				if (!row.classList || !row.classList.contains('list-item')) { continue; }
				const inp = row.querySelector('input');
				if (inp && String(inp.value).trim() !== '') { count++; }
			}
		}
		const targets = document.getElementById('targets');
		const all = !targets || targets.value === 'all';
		const fromContainer = document.getElementById('from-list');
		const cs = (all || !fromContainer) ? 'ok' : condRowsStatus(fromContainer);
		return count > 0 && cs === 'ok' && invalidSensorNames(catalog).length === 0;
	}

	// Re-point every condition row at the sensor its field currently holds:
	// the operator <select>'s options follow the sensor's result type, and
	// the operator/value disabled state follows whether the sensor resolves.
	// A freshly added condition row is a clone of an existing one, so its
	// operator <select> carries the source row's options; every row addition
	// (the add button, the group button, Reset) is a click, so normalizing
	// on the document click covers them all - and it re-reads the live
	// from-list each time, so it survives the page's Sortable init replacing
	// the container with a clone.
	function normalizeRows(catalog) {
		const fl = document.getElementById('from-list');
		if (!fl || !fl.querySelectorAll) { return; }
		for (const r of Array.from(fl.querySelectorAll('.list-item'))) {
			const inp = r.querySelector('input');
			if (inp) { applyRowType(catalog, inp); }
		}
	}

	// The sensor autocomplete: one floating list, repositioned under the
	// sensor field being typed in, listing the sensors whose name starts with
	// the text so far (it narrows as the operator types). Driven by
	// document-level delegation - the page's Sortable init replaces the list
	// containers and rows are added/removed at runtime, so per-field
	// listeners would be lost. A sensor field is any input with
	// placeholder "Sensor" (the retrieve rows and the condition rows both
	// use it); the condition rows additionally get their operator options
	// re-pointed at the chosen sensor's result type.
	function initAutocomplete(catalog) {
		let dropdown = null;
		let activeInput = null;
		let items = [];
		let highlight = -1;
		let hideTimer = null;

		function isSensorInput(el) {
			return !!el && el.tagName === 'INPUT' &&
				typeof el.getAttribute === 'function' && el.getAttribute('placeholder') === 'Sensor';
		}

		function ensureDropdown() {
			if (dropdown) { return dropdown; }
			dropdown = document.createElement('div');
			dropdown.style.position = 'absolute';
			dropdown.style.zIndex = '1100';
			dropdown.style.maxHeight = '240px';
			dropdown.style.overflowY = 'auto';
			dropdown.style.background = '#fff';
			dropdown.style.border = '1px solid #888';
			dropdown.style.boxShadow = '0 2px 6px rgba(0,0,0,0.25)';
			dropdown.style.fontFamily = 'inherit';
			dropdown.style.display = 'none';
			document.body.appendChild(dropdown);
			return dropdown;
		}

		function paint() {
			for (let i = 0; i < dropdown.children.length; i++) {
				dropdown.children[i].style.background = (i === highlight) ? '#cfe3ff' : '#fff';
			}
		}

		function positionUnder(input) {
			const rect = input.getBoundingClientRect();
			dropdown.style.top = (rect.bottom + window.scrollY) + 'px';
			dropdown.style.left = (rect.left + window.scrollX) + 'px';
			dropdown.style.width = Math.max(rect.width, 160) + 'px';
		}

		function scrollHighlight() {
			const el = dropdown.children[highlight];
			if (el && typeof el.scrollIntoView === 'function') { el.scrollIntoView({ block: 'nearest' }); }
		}

		function hide() {
			if (hideTimer) { clearTimeout(hideTimer); hideTimer = null; }
			if (dropdown) { dropdown.style.display = 'none'; }
			activeInput = null;
			highlight = -1;
		}

		function selectItem(idx) {
			const input = activeInput;
			const s = items[idx];
			if (!input || !s) { return; }
			input.value = s.name;
			hide();
			applyRowType(catalog, input);
			// A programmatic value set does not fire the input event the
			// document submit-state listener waits for, so dispatch one.
			if (typeof input.dispatchEvent === 'function') {
				input.dispatchEvent(new Event('change', { bubbles: true }));
			}
		}

		function show(input) {
			const text = String(input.value === null || input.value === undefined ? '' : input.value).trim();
			if (text === '') { hide(); return; }
			items = filterSensors(catalog, text);
			if (items.length === 0) { hide(); return; }
			const dd = ensureDropdown();
			while (dd.children.length) { dd.children[0].remove(); }
			for (let i = 0; i < items.length; i++) {
				const it = document.createElement('div');
				it.textContent = items[i].name;
				it.style.padding = '6px 8px';
				it.style.cursor = 'pointer';
				it.style.fontSize = '14px';
				it.style.whiteSpace = 'nowrap';
				it.style.overflow = 'hidden';
				it.style.textOverflow = 'ellipsis';
				(function (idx) {
					it.addEventListener('mousedown', function (e) {
						e.preventDefault(); // keep focus on the input
						selectItem(idx);
					});
					it.addEventListener('mouseover', function () {
						if (highlight !== idx) { highlight = idx; paint(); }
					});
				})(i);
				dd.appendChild(it);
			}
			// No row is highlighted until the operator picks one (mouseover or
			// an arrow key), so the list reads as a plain white dropdown.
			highlight = -1;
			paint();
			positionUnder(input);
			dd.style.display = 'block';
		}

		function onInput(e) {
			if (!isSensorInput(e.target)) { return; }
			activeInput = e.target;
			applyRowType(catalog, e.target);
			show(e.target);
		}

		function onFocusIn(e) {
			if (!isSensorInput(e.target)) { return; }
			activeInput = e.target;
			show(e.target);
		}

		function onFocusOut(e) {
			if (!isSensorInput(e.target)) { return; }
			hideTimer = setTimeout(hide, 150);
		}

		function onKeyDown(e) {
			if (!isSensorInput(e.target) || !dropdown || dropdown.style.display === 'none') { return; }
			if (e.key === 'ArrowDown') {
				// From no selection, the first row; otherwise wrap forward.
				if (items.length) { highlight = highlight < 0 ? 0 : (highlight + 1) % items.length; paint(); scrollHighlight(); e.preventDefault(); }
			} else if (e.key === 'ArrowUp') {
				// From no selection, the last row; otherwise wrap backward.
				if (items.length) { highlight = highlight < 0 ? items.length - 1 : (highlight - 1 + items.length) % items.length; paint(); scrollHighlight(); e.preventDefault(); }
			} else if (e.key === 'Enter') {
				if (highlight >= 0 && items[highlight]) { selectItem(highlight); e.preventDefault(); }
			} else if (e.key === 'Escape') {
				hide(); e.preventDefault();
			}
		}

		function onDocMouseDown(e) {
			if (dropdown && dropdown.style.display === 'block' &&
				!dropdown.contains(e.target) && !isSensorInput(e.target)) {
				hide();
			}
		}

		document.addEventListener('input', onInput);
		document.addEventListener('focusin', onFocusIn);
		document.addEventListener('focusout', onFocusOut);
		document.addEventListener('keydown', onKeyDown);
		document.addEventListener('mousedown', onDocMouseDown);

		// Clicks that open a native <select> are skipped so a select's
		// options are never rewritten mid-choice.
		function onDocClick(e) {
			if (e.target && e.target.closest && e.target.closest('select')) { return; }
			normalizeRows(catalog);
		}
		document.addEventListener('click', onDocClick);
	}

	// Wire the Submit button and the live enable/disable state. The page's
	// Sortable init replaces the list containers with clones and rows are
	// added/removed at runtime, so the state is recomputed on document-level
	// input/change/click events rather than per-field listeners.
	function init(catalog) {
		const btn = document.getElementById('querygo');
		if (!btn) { return; }
		initAutocomplete(catalog);
		// The condition rows' operator dropdowns and value fields start
		// disabled (the page's template row carries disabled="disabled"):
		// applyRowType enables them once a row's sensor resolves. Normalize
		// once on load so the initial row's state matches its (empty) field.
		normalizeRows(catalog);

		function updateSubmitState() {
			btn.disabled = !submitEnabled(catalog);
		}

		btn.addEventListener('click', function () {
			// The button is disabled while any typed sensor fails to
			// resolve; this is the backstop for a force-submitted form -
			// every invalid sensor is named, not just the first.
			const invalid = invalidSensorNames(catalog);
			if (invalid.length > 0) {
				showError('Invalid Sensor(s)', 'The following sensor(s) are not valid: ' + invalid.join(', '));
				return;
			}
			const result = buildQueryPayload(catalog);
			if (result.error) {
				showError('Query Error', result.error);
				return;
			}
			fetch('/api/commands.php', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify(result.payload)
			})
			.then(function (resp) {
				return resp.json().catch(function () { return {}; }).then(function (data) {
					return { ok: resp.ok, data: data };
				});
			})
			.then(function (r) {
				// The results live on the query page itself: pass the query
				// command's ID (the "command" value in the response) so the
				// page opens on the Results tab for this query.
				if (r.ok) { window.location.href = '/modules.php?view=query&id=' + r.data.command; }
				else {
					showError('Query Error', r.data.error || 'The query could not be submitted.');
				}
			})
			.catch(function () {
				showError('Query Error', 'The query could not be submitted.');
			});
		});

		document.addEventListener('input', updateSubmitState);
		document.addEventListener('change', updateSubmitState);
		document.addEventListener('click', updateSubmitState);
		updateSubmitState();
	}

	return {
		COND_OPS: COND_OPS,
		PROTOCOL_OP_KEYS: PROTOCOL_OP_KEYS,
		DEFAULT_OPS: DEFAULT_OPS,
		TEXT_OPS: TEXT_OPS,
		NUMERIC_OPS: NUMERIC_OPS,
		opsForType: opsForType,
		findSensor: findSensor,
		resolveSensorId: resolveSensorId,
		filterSensors: filterSensors,
		applyOpsToSelect: applyOpsToSelect,
		applyRowType: applyRowType,
		normalizeRows: normalizeRows,
		condBlocksToTree: condBlocksToTree,
		condTreeToRows: condTreeToRows,
		collectCondBlocks: collectCondBlocks,
		findUnresolved: findUnresolved,
		findUnresolvedAll: findUnresolvedAll,
		condRowsStatus: condRowsStatus,
		invalidSensorNames: invalidSensorNames,
		submitEnabled: submitEnabled,
		buildQueryPayload: buildQueryPayload,
		queryStructure: queryStructure,
		populateBuilder: populateBuilder,
		copyToBuilder: copyToBuilder,
		init: init
	};
}));
