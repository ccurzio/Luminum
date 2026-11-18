//
// LuminumQueryResults — the results wiring for the query page's Results tab
// (modules/query.php).
//
// The query page is passed a query ID (?id=, the query command's
// COMMANDS.ID); the tab polls /api/queryresults.php?id=... and renders the
// query's results in the console's standard table layout (the same top row
// as the other pages - "N of M items" and the filter field - and the
// "Query Completed in X Seconds" footer). The table's header row reflects
// the sensors the query requested: one column per sensor, titled with the
// sensor's name, and one row per answering endpoint. When two or more
// endpoints return the same answer (the same values in every sensor
// column) a Count column is added at the end; each row shows how many
// endpoints returned that answer.
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

	// Pivot one query's flat per-sensor results into one row per answering
	// endpoint: { id, hostname, s<sid>: <cell>, count? }. The sensor cells
	// follow the query's requested sensor order (q.sensors: [{sid, name}]);
	// an endpoint that never answered a requested sensor gets an empty cell.
	//
	// Count is added only when two or more endpoints share an answer - the
	// same values in every sensor column - and shows, per row, how many
	// endpoints returned that answer.
	function pivotResults(q) {
		var sensors = q.sensors || [];
		var byUid = {};
		var order = [];
		(q.results || []).forEach(function (r) {
			if (!byUid[r.uid]) {
				byUid[r.uid] = { hostname: r.hostname, cells: {} };
				order.push(r.uid);
			}
			byUid[r.uid].cells[r.sensor] = cellValue(r);
		});
		// The answer signature joins the cell values with a NUL separator so
		// ("TR","UE") and ("T","RUE") cannot collide.
		var sigCount = {};
		order.forEach(function (uid) {
			var sig = sensors.map(function (s) {
				var v = byUid[uid].cells[s.sid];
				return v === undefined ? '' : v;
			}).join('\u0000');
			sigCount[sig] = (sigCount[sig] || 0) + 1;
		});
		var hasDup = false;
		Object.keys(sigCount).forEach(function (sig) {
			if (sigCount[sig] > 1) { hasDup = true; }
		});
		var rows = order.map(function (uid) {
			var e = byUid[uid];
			var row = { id: uid, hostname: e.hostname };
			var sig = [];
			sensors.forEach(function (s) {
				var v = e.cells[s.sid];
				row['s' + s.sid] = v === undefined ? '' : v;
				sig.push(v === undefined ? '' : v);
			});
			if (hasDup) { row.count = sigCount[sig.join('\u0000')]; }
			return row;
		});
		return { rows: rows, hasDup: hasDup };
	}

	// The LuminumTable column config for a pivoted query: Computer Name, one
	// column per requested sensor (titled with the sensor's name), and -
	// when answers are shared - the Count column at the end. The filter
	// searches the hostname and the sensor cells (not the count).
	function buildConfig(q, hasDup, rowCount) {
		var cols = [{ key: 'hostname', label: 'Computer Name' }];
		var keys = ['hostname'];
		(q.sensors || []).forEach(function (s) {
			cols.push({ key: 's' + s.sid, label: s.name });
			keys.push('s' + s.sid);
		});
		if (hasDup) { cols.push({ key: 'count', label: 'Count', width: '60px', align: 'center' }); }
		return {
			emptyMessage: rowCount === 0 ? 'No results yet' : 'No Results',
			searchKeys: keys,
			columns: cols
		};
	}

	// Wire the Results tab's table shell (the page's #qrtable with its top
	// and footer rows) to the results API for the given query ID: poll every
	// 5 seconds, render the query's status row, the sensor column header and
	// the endpoint rows, and keep the "N of M items" count and the filter
	// live. Returns { refresh } (the manual refresh button's promise source).
	function init(queryId) {
		var table = document.getElementById('qrtable');
		if (!table) { return null; }
		var esc = LuminumTable.escapeHTML;
		var config = null;
		var rows = [];
		var state = { text: '' };

		// PENDING/SENT: in flight; ACKED: answered; TIMEDOUT/EXPIRED: no answer.
		function statusIcon(status) {
			if (status === 'ACKED') { return 'sysgreen.png'; }
			if (status === 'TIMEDOUT' || status === 'EXPIRED') { return 'sysred.png'; }
			return 'sysyellow.png';
		}

		function applyRows() {
			if (!config) { return; }
			LuminumTable.render(table, config, { rows: rows }, state);
			var visible = LuminumTable.filterRows(rows, config, state).length;
			document.getElementById('qrcount').textContent = visible;
			document.getElementById('qrtotal').textContent = 'of ' + rows.length;
		}

		function render(data) {
			document.getElementById('queryms').textContent = data.query_ms;
			var topcell = document.getElementById('qrtopcell');
			var footcell = document.getElementById('qrfootcell');
			var qrow = document.getElementById('qrqueryrow');
			var qcell = document.getElementById('qrquerycell');
			var q = data.count > 0 ? data.queries[0] : null;

			if (!q) {
				config = null;
				rows = [];
				topcell.colSpan = 2;
				footcell.colSpan = 2;
				qrow.style.display = 'none';
				document.getElementById('qrtable-head').innerHTML = '';
				document.getElementById('qrtable-body').innerHTML = '<tr><td colspan="2" style="text-align: center; background-color: #494a69; font-weight: normal; font-style: italic;">No such query</td></tr>';
				document.getElementById('qrcount').textContent = '0';
				document.getElementById('qrtotal').textContent = 'of 0';
				return;
			}

			qrow.style.display = '';
			qcell.innerHTML = '<img src="/icons/' + statusIcon(q.status) + '" title="' + esc(q.status) + '" style="vertical-align: middle; margin-right: 6px;">'
				+ esc(q.created)
				+ ' &nbsp;&middot;&nbsp; ' + (q.target === 'all' ? 'all endpoints' : 'client ' + esc(q.target))
				+ (q.conditions ? ' &nbsp;&middot;&nbsp; condition-filtered' : '');

			var piv = pivotResults(q);
			rows = piv.rows;
			config = buildConfig(q, piv.hasDup, rows.length);
			var ncol = config.columns.length;
			topcell.colSpan = ncol;
			footcell.colSpan = ncol;
			qcell.colSpan = ncol;
			document.getElementById('qrtable-head').innerHTML = LuminumTable.headerHTML(config);
			applyRows();
		}

		document.getElementById('qrfilter').addEventListener('input', function (e) {
			state.text = e.target.value;
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
