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
// number/datetime numerically.
//
// The pure functions (findSensor, resolveSensorId, filterSensors,
// opsForType, condBlocksToTree, findUnresolved, findUnresolvedAll) are
// DOM-free so they can be unit-tested under Node. The DOM helpers
// (applyOpsToSelect, applyRowType, collectCondBlocks, condRowsStatus,
// invalidSensorNames, submitEnabled, buildQueryPayload, init) only run in
// the browser.
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
	// result type) and the value <input>. collectCondBlocks and condRowsStatus
	// read the "bool-row" class to know which controls hold the row's value
	// and op. Retrieve rows carry none of these controls, so this is a no-op.
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
			if (opSel) { opSel.style.display = 'none'; }
			if (valInp) { valInp.style.display = 'none'; }
			if (boolOp) { boolOp.style.display = 'inline-block'; }
			if (boolVal) { boolVal.style.display = ''; }
		} else {
			if (row.classList.contains('bool-row')) { row.classList.remove('bool-row'); }
			if (opSel) { opSel.style.display = ''; }
			if (valInp) { valInp.style.display = ''; }
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

		// A freshly added condition row is a clone of an existing one, so its
		// operator <select> carries the source row's options; re-point every
		// row at the set for the sensor its field holds. Every row addition
		// (the add button, the group button, Reset) is a click, so normalizing
		// on the document click covers them all - and it re-reads the live
		// from-list each time, so it survives the page's Sortable init
		// replacing the container with a clone. Clicks that open a native
		// <select> are skipped so a select's options are never rewritten
		// mid-choice.
		function normalizeRows() {
			const fl = document.getElementById('from-list');
			if (!fl || !fl.querySelectorAll) { return; }
			for (const r of Array.from(fl.querySelectorAll('.list-item'))) {
				const inp = r.querySelector('input');
				if (inp) { applyRowType(catalog, inp); }
			}
		}
		function onDocClick(e) {
			if (e.target && e.target.closest && e.target.closest('select')) { return; }
			normalizeRows();
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

		function updateSubmitState() {
			btn.disabled = !submitEnabled(catalog);
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
		DEFAULT_OPS: DEFAULT_OPS,
		TEXT_OPS: TEXT_OPS,
		NUMERIC_OPS: NUMERIC_OPS,
		opsForType: opsForType,
		findSensor: findSensor,
		resolveSensorId: resolveSensorId,
		filterSensors: filterSensors,
		applyOpsToSelect: applyOpsToSelect,
		applyRowType: applyRowType,
		condBlocksToTree: condBlocksToTree,
		collectCondBlocks: collectCondBlocks,
		findUnresolved: findUnresolved,
		findUnresolvedAll: findUnresolvedAll,
		condRowsStatus: condRowsStatus,
		invalidSensorNames: invalidSensorNames,
		submitEnabled: submitEnabled,
		buildQueryPayload: buildQueryPayload,
		init: init
	};
}));
