//
// LuminumQueryResults — the results wiring for the query page's Results tab
// (modules/query.php).
//
// The query page is passed a query ID (?id=, the query command's
// COMMANDS.ID); the tab polls /api/queryresults.php?id=... and renders the
// query's results in the console's standard table layout (the same top row
// as the other pages - "N of M items" and the filter field - and the
// "Query Completed in X Seconds" footer). Like the other console tables,
// the first column is a select checkbox (select-all in the header). The
// table's header row reflects the sensors the query requested: one column
// per sensor, titled with the sensor's name. The rows are the query's
// unique answers - one row per
// combination of sensor values, with endpoints that answered identically in
// every sensor column sharing a row - and the Count column shows how many
// endpoints returned that answer (15 endpoints all answering TRUE -> a
// single row TRUE/15).
//
// The pure functions (cellValue, pivotResults, buildConfig) are DOM-free so
// they can be unit-tested under Node. The DOM helper (init) only runs in the
// browser.
//
(function (root, factory) {
	if (typeof module === 'object' && module.exports) {
		module.exports = factory();
	} else {
		root.LuminumQueryResults = factory();
	}
}(typeof self !== 'undefined' ? self : this, function () {
	'use strict';

	// The cell an endpoint's answer for one sensor renders as: OK -> the
	// output, ERR -> the error message (the status when there is none).
	function cellValue(r) {
		if (r.status === 'OK') { return r.output !== null ? r.output : ''; }
		return r.err !== null ? r.err : r.status;
	}

	// Collapse one query's flat per-sensor results into one row per unique
	// answer: { id, s<sid>: <cell>, count }. The sensor cells follow the
	// query's requested sensor order (q.sensors: [{sid, name}]); an endpoint
	// that never answered a requested sensor gets an empty cell. An answer
	// is the endpoint's values across every sensor column, so endpoints
	// share a row only when they answered identically in all of them. Rows
	// keep the order in which each answer first appeared.
	function pivotResults(q) {
		var sensors = q.sensors || [];
		var byUid = {};
		var uidOrder = [];
		(q.results || []).forEach(function (r) {
			if (!byUid[r.uid]) {
				byUid[r.uid] = { cells: {} };
				uidOrder.push(r.uid);
			}
			byUid[r.uid].cells[r.sensor] = cellValue(r);
		});
		// The answer signature joins the cell values with a NUL separator so
		// ("TR","UE") and ("T","RUE") cannot collide.
		var SEP = String.fromCharCode(0);
		var groups = {};
		var sigOrder = [];
		uidOrder.forEach(function (uid) {
			var cells = sensors.map(function (s) {
				var v = byUid[uid].cells[s.sid];
				return v === undefined ? '' : v;
			});
			var sig = cells.join(SEP);
			if (!groups[sig]) {
				groups[sig] = { cells: cells, count: 0 };
				sigOrder.push(sig);
			}
			groups[sig].count++;
		});
		return sigOrder.map(function (sig, i) {
			var g = groups[sig];
			var row = { id: i, count: g.count };
			sensors.forEach(function (s, j) {
				row['s' + s.sid] = g.cells[j];
			});
			return row;
		});
	}

	// The LuminumTable column config for a collapsed query: the select
	// checkbox column first (like the other console tables), one column per
	// requested sensor (titled with the sensor's name), and the Count column
	// at the end (how many endpoints returned the row's answer). The filter
	// searches the sensor cells (not the count).
	function buildConfig(q, rowCount) {
		var cols = [];
		var keys = [];
		cols.push({ type: 'checkbox', width: '15px', inputClass: 'qrrow', idPrefix: 'ID',
			header: '<input id="qrselectall" type="checkbox">' });
		(q.sensors || []).forEach(function (s) {
			cols.push({ key: 's' + s.sid, label: s.name });
			keys.push('s' + s.sid);
		});
		cols.push({ key: 'count', label: 'Count', width: '60px', align: 'center' });
		return {
			emptyMessage: rowCount === 0 ? 'No results yet' : 'No Results',
			searchKeys: keys,
			columns: cols
		};
	}

	// Wire the Results tab's table shell (the page's #qrtable with its top
	// and footer rows) to the results API for the given query ID: poll every
	// 5 seconds, render the sensor column header and the answer rows, and
	// keep the "N of M items" count and the filter live. Returns { refresh }
	// (the manual refresh button's promise source).
	function init(queryId) {
		var table = document.getElementById('qrtable');
		if (!table) { return null; }
		var config = null;
		var rows = [];
		var state = { selected: {}, text: '' };

		function applyRows() {
			if (!config) { return; }
			LuminumTable.render(table, config, { rows: rows }, state);
			var visible = LuminumTable.filterRows(rows, config, state);
			document.getElementById('qrcount').textContent = visible.length;
			document.getElementById('qrtotal').textContent = 'of ' + rows.length;
			// The header is re-rendered on every poll, recreating the
			// select-all box - restore its checked state from the visible
			// rows.
			var all = document.getElementById('qrselectall');
			if (all) {
				all.checked = visible.length > 0 && visible.every(function (r) { return state.selected[r.id]; });
			}
		}

		function render(data) {
			document.getElementById('queryms').textContent = data.query_ms;
			var topcell = document.getElementById('qrtopcell');
			var footcell = document.getElementById('qrfootcell');
			var q = data.count > 0 ? data.queries[0] : null;

			if (!q) {
				config = null;
				rows = [];
				topcell.colSpan = 3;
				footcell.colSpan = 3;
				document.getElementById('qrtable-head').innerHTML = '';
				document.getElementById('qrtable-body').innerHTML = '<tr><td colspan="3" style="text-align: center; background-color: #494a69; font-weight: normal; font-style: italic;">No such query</td></tr>';
				document.getElementById('qrcount').textContent = '0';
				document.getElementById('qrtotal').textContent = 'of 0';
				return;
			}

			rows = pivotResults(q);
			config = buildConfig(q, rows.length);
			var ncol = config.columns.length;
			topcell.colSpan = ncol;
			footcell.colSpan = ncol;
			document.getElementById('qrtable-head').innerHTML = LuminumTable.headerHTML(config);
			applyRows();
		}

		document.getElementById('qrfilter').addEventListener('input', function (e) {
			state.text = e.target.value;
			applyRows();
		});

		// Row selection (delegated): the body is re-rendered on every poll,
		// so listen on the stable tbody rather than each row.
		table.querySelector('tbody[data-luminum-body]').addEventListener('change', function (e) {
			if (!e.target.classList.contains('qrrow')) { return; }
			state.selected[e.target.dataset.id] = e.target.checked;
			applyRows();
		});

		// Select-all (delegated on the stable header tbody - the box itself
		// is recreated on every poll).
		document.getElementById('qrtable-head').addEventListener('change', function (e) {
			if (e.target.id !== 'qrselectall' || !config) { return; }
			LuminumTable.filterRows(rows, config, state).forEach(function (r) {
				state.selected[r.id] = e.target.checked;
			});
			applyRows();
		});

		var poll = LuminumTable.poll('/api/queryresults.php?id=' + queryId, {
			interval: 5000,
			onData: render,
			onError: function (err) { console.error('Query results poll failed:', err); }
		});
		poll.refresh();

		return {
			refresh: function () { return poll.refresh(); }
		};
	}

	return {
		cellValue: cellValue,
		pivotResults: pivotResults,
		buildConfig: buildConfig,
		init: init
	};
}));
