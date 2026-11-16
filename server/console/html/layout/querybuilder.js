//
// LuminumQueryBuilder — the query wiring for the query builder page
// (modules/query.php).
//
// The builder's markup and its own JS (row add/remove, drag-sort, grouping,
// the AND/OR operators between the condition rows) live on the page; this
// module only turns what the operator typed into the /api/commands.php
// query statement (protocol 7.3): the retrieve sensors (the typed sensor
// fields, resolved to sensor IDs), the condition tree (the From rows,
// groups folded in), and the broadcast target. Only the endpoints on which
// the condition tree evaluates true answer.
//
// The pure functions (resolveSensorId, condBlocksToTree) are DOM-free so
// they can be unit-tested under Node. The DOM helpers (collectCondBlocks,
// condRowsStatus, buildQueryPayload, init) only run in the browser.
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

	// Resolve the text the operator typed in a Sensor field to a sensor ID:
	// a numeric field that matches a sensor ID wins, otherwise the sensor
	// name (case-insensitive). null when nothing matches.
	function resolveSensorId(catalog, text) {
		const t = String(text === null || text === undefined ? '' : text).trim();
		if (t === '') { return null; }
		if (/^[0-9]+$/.test(t)) {
			const id = parseInt(t, 10);
			for (const s of catalog) { if (s.id === id) { return id; } }
		}
		const lt = t.toLowerCase();
		for (const s of catalog) { if (String(s.name).toLowerCase() === lt) { return s.id; } }
		return null;
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
	// AND/OR of a block sits on the block's anchor row - the row itself, or
	// the group's last direct row (the page's insertLogicalOperators puts
	// it there).
	function collectCondBlocks(container, catalog) {
		const blocks = [];
		for (const el of Array.from(container.children)) {
			if (!el.classList) { continue; }
			if (el.classList.contains('list-item')) {
				const inputs = el.querySelectorAll('input');
				const sensor = inputs.length > 0 ? String(inputs[0].value).trim() : '';
				const value = inputs.length > 1 ? String(inputs[1].value).trim() : '';
				const opSel = el.querySelector('select[name="fromop"]');
				const afterSel = el.querySelector('select.logical-operator');
				blocks.push({
					kind: 'row',
					sensor: sensor,
					value: value,
					sid: sensor === '' ? null : resolveSensorId(catalog, sensor),
					op: COND_OPS[opSel ? opSel.value : 'equals'] || '==',
					opAfter: afterSel ? afterSel.value : null
				});
			} else if (el.classList.contains('group-container')) {
				let lastRow = null;
				for (const c of Array.from(el.children)) {
					if (c.classList && c.classList.contains('list-item')) { lastRow = c; }
				}
				const afterSel = lastRow ? lastRow.querySelector('select.logical-operator') : null;
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
				const value = inputs.length > 1 ? String(inputs[1].value).trim() : '';
				if (sensor === '' && value === '') { s = 'empty'; }
				else if (sensor === '') { s = 'incomplete'; }
				else { s = 'ok'; }
			} else { continue; }
			if (s === 'incomplete') { return 'incomplete'; }
			if (s === 'ok') { status = 'ok'; }
		}
		return status;
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

	// Wire the Submit button and the live enable/disable state. The page's
	// Sortable init replaces the list containers with clones and rows are
	// added/removed at runtime, so the state is recomputed on document-level
	// input/change/click events rather than per-field listeners.
	function init(catalog) {
		const btn = document.getElementById('querygo');
		if (!btn) { return; }

		function updateSubmitState() {
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
			btn.disabled = !(count > 0 && cs === 'ok');
		}

		btn.addEventListener('click', function () {
			const result = buildQueryPayload(catalog);
			if (result.error) {
				LuminumOverlay.show({ title: 'Query Error', message: result.error });
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
				if (r.ok) { window.location.href = '/modules.php?view=queryresults'; }
				else {
					LuminumOverlay.show({ title: 'Query Error', message: r.data.error || 'The query could not be submitted.' });
				}
			})
			.catch(function () {
				LuminumOverlay.show({ title: 'Query Error', message: 'The query could not be submitted.' });
			});
		});

		document.addEventListener('input', updateSubmitState);
		document.addEventListener('change', updateSubmitState);
		document.addEventListener('click', updateSubmitState);
		updateSubmitState();
	}

	return {
		COND_OPS: COND_OPS,
		resolveSensorId: resolveSensorId,
		condBlocksToTree: condBlocksToTree,
		collectCondBlocks: collectCondBlocks,
		findUnresolved: findUnresolved,
		condRowsStatus: condRowsStatus,
		buildQueryPayload: buildQueryPayload,
		init: init
	};
}));
