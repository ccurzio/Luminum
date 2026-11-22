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
// every sensor column sharing a row. The Count column shows how many
// endpoints returned that answer (15 endpoints all answering TRUE -> a
// single row TRUE/15); it appears only when at least one answer is shared
// by more than one endpoint (a duplicate row) - when every answer is
// unique the count would be 1 in every row and the column carries nothing.
//
// A sensor with CSPLIT and named output columns (the SENSORS OUTCOLS
// value, split on the sensor's DELIMITER) expands its column: the header
// carries the column names as a second tier, and each line of the sensor's
// output renders as its own <tr> with the line's delimiter-separated
// segments in the sub-columns, while the row's other cells (the checkbox,
// the non-split sensors, the Count) span the <tr>s.
//
// When that split sensor is the query's only sensor, the pivot itself
// changes: the output is the data, so the results are not split by
// endpoint. The rows are the sensor's unique output lines (one row per
// line, the line's segments in the sub-columns, each row with its own
// checkbox), and the Count is how many endpoints' output carried the line
// (duplicates grouped). With more than one sensor the pivot stays
// per-endpoint as above.
//
// The rows appear as the answers arrive: while the query is running the
// page polls every second and appends each new answer row to the table
// (updating a shared row's Count in place) instead of re-rendering the
// whole table; once the query finishes the poll slows to the console's
// standard five seconds. The footer clock starts when the page loads (the
// query goes out to the endpoints as the page opens) and ticks
// "Processing Query... X.XX Seconds" until the soonest of the command's
// deadline (the query timeout) or every online endpoint in the target
// having answered, then reads "Query Completed in X.XX Seconds". A page
// opened on an already-finished query shows the server-side duration
// instead of ticking.
//
// The pure functions (cellValue, pivotResults, expandRow, buildConfig,
// queryDone, doneElapsed) are DOM-free so they can be unit-tested under
// Node. The DOM helper (init) only runs in the browser.
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

	// Split a sensor's output into lines: a trailing newline (a script that
	// ends its output with one) does not add an empty last line.
	function splitLines(v) {
		var lines = String(v === undefined || v === null ? '' : v).split('\n');
		if (lines.length > 1 && lines[lines.length - 1] === '') { lines.pop(); }
		return lines;
	}

	// The query's sole sensor when it is a CSPLIT sensor with named output
	// columns, else null: such a query pivots on the sensor's output lines
	// (one row per unique line) instead of on the endpoints' full answers -
	// the output is the data, so the endpoints are the duplicates to count.
	function singleSplitSensor(sensors) {
		if (sensors.length !== 1) { return null; }
		var s = sensors[0];
		if (s.csplit && s.outcols && s.outcols.length) { return s; }
		return null;
	}

	// The pivot for a single-split query: one row per unique output line,
	// the Count the number of endpoints whose output carried the line (an
	// endpoint carrying the line twice counts once). The row's cell is the
	// raw line - expandRow splits it into the sub values, and the filter
	// searches it. Rows keep the order in which each line first appeared.
	function pivotSplitLines(q, sensor) {
		var key = 's' + sensor.sid;
		var groups = {};
		var order = [];
		(q.results || []).forEach(function (r) {
			var seen = {};
			splitLines(cellValue(r)).forEach(function (line) {
				if (seen[line]) { return; }
				seen[line] = true;
				if (!groups[line]) {
					groups[line] = 0;
					order.push(line);
				}
				groups[line]++;
			});
		});
		return order.map(function (line, i) {
			var row = { id: i, count: groups[line] };
			row[key] = line;
			return row;
		});
	}

	// Collapse one query's flat per-sensor results into one row per unique
	// answer: { id, s<sid>: <cell>, count }. The sensor cells follow the
	// query's requested sensor order (q.sensors: [{sid, name}]); an endpoint
	// that never answered a requested sensor gets an empty cell. An answer
	// is the endpoint's values across every sensor column, so endpoints
	// share a row only when they answered identically in all of them. Rows
	// keep the order in which each answer first appeared. A query whose only
	// sensor is a split sensor pivots on the output lines instead (see
	// pivotSplitLines).
	function pivotResults(q) {
		var sensors = q.sensors || [];
		var split = singleSplitSensor(sensors);
		if (split) { return pivotSplitLines(q, split); }
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

	// Expand a pivot row for the table: a sensor with CSPLIT and named
	// output columns (outcols) renders one <tr> per line of its output,
	// each line split on the sensor's delimiter into the sensor's
	// sub-columns. The row's span is the largest line count across its
	// split cells (1 when the query has no split sensor), the sub values
	// are stored as row[<key>_<line>_<col>], and row[<key>_segs] carries
	// the largest segment count (buildConfig names any segments past the
	// stored column names generically).
	function expandRow(row, sensors) {
		var span = 1;
		(sensors || []).forEach(function (s) {
			if (!s.csplit || !s.outcols || !s.outcols.length) { return; }
			var key = 's' + s.sid;
			var v = row[key];
			var delim = (s.delimiter !== null && s.delimiter !== undefined && s.delimiter !== '') ? s.delimiter : '|';
			var lines = splitLines(v);
			if (lines.length > span) { span = lines.length; }
			var segs = 0;
			lines.forEach(function (line, i) {
				var parts = line.split(delim);
				if (parts.length > segs) { segs = parts.length; }
				parts.forEach(function (p, j) {
					row[key + '_' + i + '_' + j] = p;
				});
			});
			row[key + '_segs'] = segs;
		});
		row.span = span;
		return row;
	}

	// The LuminumTable column config for a collapsed query: the select
	// checkbox column first (like the other console tables), one column per
	// requested sensor (titled with the sensor's name), and - only when at
	// least one row is a duplicate (more than one endpoint returned the
	// answer) - the Count column at the end (how many endpoints returned
	// the row's answer). A CSPLIT sensor's column carries its stored column
	// names as sub-labels (the header's second tier); a line with more
	// segments than stored names gains generic "Column N" sub-labels so no
	// data is dropped. The filter searches the sensor cells (not the
	// count).
	function buildConfig(q, rows) {
		var rowCount = rows.length;
		var hasDuplicate = rows.some(function (r) { return r.count > 1; });
		var cols = [];
		var keys = [];
		cols.push({ type: 'checkbox', width: '15px', inputClass: 'qrrow', idPrefix: 'ID',
			header: '<input id="qrselectall" type="checkbox">' });
		(q.sensors || []).forEach(function (s) {
			var key = 's' + s.sid;
			if (s.csplit && s.outcols && s.outcols.length) {
				var sub = s.outcols.slice();
				rows.forEach(function (row) {
					var segs = row[key + '_segs'];
					if (segs !== undefined && segs > sub.length) {
						for (var n = sub.length; n < segs; n++) { sub.push('Column ' + (n + 1)); }
					}
				});
				cols.push({ key: key, label: s.name, sub: sub, whiteSpace: 'pre-wrap' });
			} else {
				// pre-wrap: a sensor's output is often multi-line formatted
				// text, and the cell must render its newlines instead of
				// collapsing them into spaces.
				cols.push({ key: key, label: s.name, whiteSpace: 'pre-wrap' });
			}
			keys.push(key);
		});
		if (hasDuplicate) {
			cols.push({ key: 'count', label: 'Count', width: '60px', align: 'center' });
		}
		return {
			emptyMessage: rowCount === 0 ? 'No results yet' : 'No Results',
			searchKeys: keys,
			columns: cols
		};
	}

	// Whether a query has finished (the footer clock's stop condition): the
	// command timed out (the worker marked it TIMEDOUT, or its deadline -
	// now() + CMDTIMEOUT - has passed), or every online endpoint in the
	// target has answered. A conditional query's non-matching endpoints
	// never answer (protocol 7.3), so such a query always runs to its
	// deadline. No online endpoints in the target is not a completion (the
	// query would otherwise finish vacuously before anything could answer).
	// now is milliseconds since the epoch (Date.now()).
	function queryDone(q, now) {
		now = now || Date.now();
		if (q.status === 'TIMEDOUT') { return true; }
		if (q.deadline_ts !== null && q.deadline_ts !== undefined && now >= q.deadline_ts * 1000) { return true; }
		if (q.target_online > 0 && q.answered >= q.target_online) { return true; }
		return false;
	}

	// The server-side elapsed seconds for a query that is already finished
	// (the results page opened on a completed query - ticking from page
	// load would read ~0): from when the command went out to the endpoints
	// (SENT, falling back to CREATED) to when it finished (the deadline for
	// a timeout, the last answer otherwise). Null when the instants are
	// missing.
	function doneElapsed(q) {
		var start = (q.sent_ts !== null && q.sent_ts !== undefined) ? q.sent_ts : q.created_ts;
		var done = q.status === 'TIMEDOUT' ? q.deadline_ts : q.last_answer_ts;
		if (start === null || start === undefined || done === null || done === undefined) { return null; }
		return Math.max(0, done - start);
	}

	// Wire the Results tab's table shell (the page's #qrtable with its top
	// and footer rows) to the results API for the given query ID: poll
	// every second while the query is running (five seconds once it
	// finishes), append the answer rows as they arrive, keep the "N of M
	// items" count and the filter live, and run the footer clock (see the
	// module header). Returns { refresh } (the manual refresh button's
	// promise source).
	function init(queryId) {
		var table = document.getElementById('qrtable');
		if (!table) { return null; }
		var config = null;
		var rows = [];
		var state = { selected: {}, text: '' };

		// --- the footer clock --------------------------------------------
		// Starts when the page loads and ticks "Processing Query... X.XX
		// Seconds" (100 ms) until render() reports the stop condition,
		// then reads "Query Completed in X.XX Seconds". Once the first poll
		// has published the command's deadline, the ticker stops the clock
		// exactly on it rather than on the next poll.
		var t0 = Date.now();
		var clockRunning = true;
		var deadlineMs = null;
		var firstRender = true;
		var prefixEl = document.getElementById('qrfootprefix');
		var msEl = document.getElementById('queryms');

		function setFooter(prefix, seconds) {
			if (prefixEl) { prefixEl.textContent = prefix; }
			if (msEl) { msEl.textContent = seconds.toFixed(2); }
		}
		function stopClock(seconds) {
			if (!clockRunning) { return; }
			clockRunning = false;
			if (ticker) { clearInterval(ticker); ticker = null; }
			setFooter('Query Completed in', seconds);
		}
		var ticker = setInterval(function () {
			if (!clockRunning) { return; }
			if (deadlineMs !== null && Date.now() >= deadlineMs) {
				stopClock((deadlineMs - t0) / 1000);
				return;
			}
			setFooter('Processing Query...', (Date.now() - t0) / 1000);
		}, 100);

		function updateCounts() {
			var visible = LuminumTable.filterRows(rows, config, state);
			// The row IDs are positional, so count only the selections that
			// exist in the current rows.
			var sel = 0;
			rows.forEach(function (r) { if (state.selected[r.id]) { sel++; } });
			document.getElementById('qrcount').textContent = visible.length;
			document.getElementById('qrtotal').textContent = rows.length;
			document.getElementById('qrselcount').textContent = sel > 0 ? '(' + sel + ' Selected)' : '';
			// The header is re-rendered when the columns change, recreating
			// the select-all box - restore its checked state from the
			// visible rows.
			var all = document.getElementById('qrselectall');
			if (all) {
				all.checked = visible.length > 0 && visible.every(function (r) { return state.selected[r.id]; });
			}
		}

		function applyRows() {
			if (!config) { return; }
			LuminumTable.render(table, config, { rows: rows }, state);
			updateCounts();
		}

		function render(data) {
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
				document.getElementById('qrtotal').textContent = '0';
				document.getElementById('qrselcount').textContent = '';
				stopClock((Date.now() - t0) / 1000);
				slowPoll();
				return;
			}

			if (q.deadline_ts !== null && q.deadline_ts !== undefined) {
				deadlineMs = q.deadline_ts * 1000;
			}

			// The clock: stop at the soonest stop condition. A page opened
			// on an already-finished query (the first render reports it
			// done) shows the server-side duration; a live query stops at
			// now (the ticker already stopped it exactly on the deadline
			// when that was the cause).
			if (clockRunning && queryDone(q, Date.now())) {
				var secs = firstRender ? doneElapsed(q) : null;
				if (secs === null) { secs = (Date.now() - t0) / 1000; }
				stopClock(secs);
				slowPoll();
			}
			firstRender = false;

			var newRows = pivotResults(q);
			newRows.forEach(function (r) { expandRow(r, q.sensors); });
			var newConfig = buildConfig(q, newRows);

			// Incremental update: the pivot rows are append-only (a group's
			// cells are fixed when its first answer arrives, its count only
			// grows, and a new group appends at the end), so while the
			// column set is unchanged and no filter is active, update the
			// changed Count cells in place and append the new rows - the
			// rows appear as the answers arrive, without a full repaint.
			// A structural change (the Count column appearing, a split
			// sensor gaining a generic sub-column) or an active filter
			// falls back to the full re-render. The comparison is on the
			// physical column count (a sub-column counts as one).
			var structural = !config ||
				LuminumTable.physicalColumns(config).length !== LuminumTable.physicalColumns(newConfig).length;
			if (structural || state.text !== '') {
				config = newConfig;
				rows = newRows;
				var ncol = LuminumTable.physicalColumns(config).length;
				topcell.colSpan = ncol;
				footcell.colSpan = ncol;
				document.getElementById('qrtable-head').innerHTML = LuminumTable.headerHTML(config);
				applyRows();
				return;
			}

			var changed = false;
			var tbody = table.querySelector('tbody[data-luminum-body]');
			for (var i = 0; i < rows.length && i < newRows.length; i++) {
				if (newRows[i].count !== rows[i].count) {
					var tr = tbody.querySelector('tr[data-id="' + i + '"]');
					if (tr && tr.lastElementChild) { tr.lastElementChild.textContent = newRows[i].count; }
					changed = true;
				}
			}
			if (newRows.length > rows.length) {
				var html = LuminumTable.rowsHTML(config, newRows.slice(rows.length), state);
				if (rows.length === 0) { tbody.innerHTML = html; }
				else { tbody.insertAdjacentHTML('beforeend', html); }
				changed = true;
			}
			rows = newRows;
			config = newConfig;
			if (changed) { updateCounts(); }
		}

		document.getElementById('qrfilter').addEventListener('input', function (e) {
			state.text = e.target.value;
			applyRows();
		});

		// Row selection (delegated): the body is re-rendered when the
		// columns change or the filter is used, so listen on the stable
		// tbody rather than each row.
		table.querySelector('tbody[data-luminum-body]').addEventListener('change', function (e) {
			if (!e.target.classList.contains('qrrow')) { return; }
			state.selected[e.target.dataset.id] = e.target.checked;
			applyRows();
		});

		// Select-all (delegated on the stable header tbody - the box itself
		// is recreated when the columns change).
		document.getElementById('qrtable-head').addEventListener('change', function (e) {
			if (e.target.id !== 'qrselectall' || !config) { return; }
			LuminumTable.filterRows(rows, config, state).forEach(function (r) {
				state.selected[r.id] = e.target.checked;
			});
			applyRows();
		});

		// Poll every second while the query is running so the rows appear
		// as the answers arrive; once it finishes the results are static
		// (answers past the deadline are dropped server-side, duplicates
		// deduplicated), so the poll slows to the console's standard five
		// seconds.
		var url = '/api/queryresults.php?id=' + queryId;
		var poll = LuminumTable.poll(url, {
			interval: 1000,
			onData: render,
			onError: function (err) { console.error('Query results poll failed:', err); }
		});
		var slow = false;
		function slowPoll() {
			if (slow) { return; }
			slow = true;
			poll.stop();
			poll = LuminumTable.poll(url, {
				interval: 5000,
				onData: render,
				onError: function (err) { console.error('Query results poll failed:', err); }
			});
		}
		poll.refresh();

		return {
			refresh: function () { return poll.refresh(); }
		};
	}

	return {
		cellValue: cellValue,
		pivotResults: pivotResults,
		expandRow: expandRow,
		buildConfig: buildConfig,
		queryDone: queryDone,
		doneElapsed: doneElapsed,
		init: init
	};
}));
