//
// LuminumTable — reusable client-side table renderer for the Luminum console.
//
// A table is described by a column config and rendered from JSON data served
// by the console API. This replaces the old statically-coded PHP table loops:
// the repetitive row markup is produced by a callable function from data +
// config, and the page polls the API to keep the table live.
//
// The pure functions (escapeHTML, headerHTML, rowHTML, rowsHTML, filterRows)
// are DOM-free so they can be unit-tested under Node. The DOM helpers
// (render, poll) only run in the browser.
//
(function (root, factory) {
	if (typeof module === 'object' && module.exports) {
		module.exports = factory();
	} else {
		root.LuminumTable = factory();
	}
}(typeof self !== 'undefined' ? self : this, function () {
	'use strict';

	var ROW_BASE = '#494a69';
	var ROW_SELECTED = '#686993';

	function escapeHTML(value) {
		if (value === null || value === undefined) { return ''; }
		return String(value)
			.replace(/&/g, '&amp;')
			.replace(/</g, '&lt;')
			.replace(/>/g, '&gt;')
			.replace(/"/g, '&quot;')
			.replace(/'/g, '&#39;');
	}

	// Build the style string for a data cell, including the selection colour.
	function cellStyle(col, bg) {
		var s = 'background-color: ' + bg + '; font-weight: normal;';
		if (col.width) { s += 'width: ' + col.width + ';'; }
		if (col.align) { s += 'text-align: ' + col.align + ';'; }
		if (col.whiteSpace) { s += 'white-space: ' + col.whiteSpace + ';'; }
		if (col.padTop) { s += 'padding-top: ' + col.padTop + ';'; }
		return s;
	}

	function headerCell(col) {
		var s = '';
		if (col.width) { s += 'width: ' + col.width + ';'; }
		if (col.align) { s += 'text-align: ' + col.align + ';'; }
		var style = s ? ' style="' + s + '"' : '';
		var inner = (col.header !== undefined) ? col.header : escapeHTML(col.label);
		var span = '';
		if (col.colspan) { span += ' colspan="' + col.colspan + '"'; }
		if (col.rowspan) { span += ' rowspan="' + col.rowspan + '"'; }
		return '<td' + span + style + '>' + inner + '</td>';
	}

	// The physical columns of a config: a column with `sub` (an array of
	// sub-labels) expands into one physical column per sub-label, every
	// other column is its own physical column. The header renders the
	// sub-labels as a second tier below the column's label, and a row's
	// sub values (row[<key>_<subRow>_<subCol>]) fill the sub-columns one
	// line per <tr> while the row's other cells span the <tr>s (see
	// rowHTML). Configs without sub columns expand to themselves, so the
	// plain pages render exactly as before.
	function physicalColumns(config) {
		var phys = [];
		config.columns.forEach(function (col) {
			if (col.sub && col.sub.length) {
				col.sub.forEach(function (label, j) {
					phys.push({ col: col, subIndex: j, label: label });
				});
			} else {
				phys.push({ col: col, subIndex: null, label: col.label });
			}
		});
		return phys;
	}

	// Render the header <tr> (or the two-tier header when a column carries
	// sub-labels) for a column config.
	function headerHTML(config) {
		var cols = config.columns;
		var hasSub = cols.some(function (c) { return c.sub && c.sub.length; });
		if (!hasSub) { return '<tr>' + cols.map(headerCell).join('') + '</tr>'; }
		var t1 = '<tr>';
		var t2 = '<tr>';
		cols.forEach(function (col) {
			if (col.sub && col.sub.length) {
				t1 += headerCell({ width: col.width, align: col.align, header: col.header, label: col.label, colspan: col.sub.length });
				t2 += col.sub.map(function (l) { return headerCell({ label: l }); }).join('');
			} else {
				t1 += headerCell(Object.assign({}, col, { rowspan: 2 }));
			}
		});
		return t1 + '</tr>' + t2 + '</tr>';
	}

	// The checkbox column's pinned total width. The global `table { width:
	// 100% }` rule makes every table fill its container, and under the
	// default auto layout the leftover width is spread across all columns -
	// so a 15px checkbox column stretches to 30-45px depending on the table
	// width. Pinning it to a fixed width (checkbox + the cell's padding, no
	// more) keeps the selection column the same size on every page.
	var CHECKBOX_COL_WIDTH = '32px';

	// Build the <col> elements for a column config. Under table-layout: fixed
	// a <col> width is the column's total width; a column with no width is
	// flexible and absorbs the table's leftover space (so the fixed columns,
	// including the checkbox, hold their width). Sub-columns are always
	// flexible: they share the width their parent column would have had.
	function colgroupCols(config) {
		return physicalColumns(config).map(function (p) {
			var col = p.col;
			if (col.type === 'checkbox') { return '<col style="width: ' + CHECKBOX_COL_WIDTH + ';">'; }
			if (p.subIndex === null && col.width) { return '<col style="width: ' + col.width + ';">'; }
			return '<col>';
		}).join('');
	}

	// The full <colgroup> for a column config (see colgroupCols).
	function colgroupHTML(config) {
		return '<colgroup>' + colgroupCols(config) + '</colgroup>';
	}

	// Render one <td> for a column. Columns with a render(row) function emit
	// raw HTML (icons, etc.); plain columns escape the row value. rowspan
	// spans the cell over the row's sub-<tr>s (see rowHTML).
	function cellHTML(col, row, bg, rowspan) {
		var inner = col.render ? col.render(row) : escapeHTML(row[col.key]);
		var span = rowspan ? ' rowspan="' + rowspan + '"' : '';
		return '<td' + span + ' style="' + cellStyle(col, bg) + '">' + inner + '</td>';
	}

	// The checkbox cell for a row (the plain and the spanning variants).
	function checkboxCell(col, row, bg, checked, rowspan) {
		var span = rowspan ? ' rowspan="' + rowspan + '"' : '';
		return '<td' + span + ' id="' + row.id + 'A" style="background-color: ' + bg + '; font-weight: normal;width: 15px;">' +
			'<input class="' + (col.inputClass || 'row') + '" id="' + (col.idPrefix || 'ID') + row.id +
			'" data-id="' + row.id + '" type="checkbox"' + (checked ? ' checked' : '') + '></td>';
	}

	// Render the data row(s) for a row. The checkbox column is
	// special-cased. When the config carries sub columns, the row renders
	// as row.span <tr>s: the sub values (row[<key>_<subRow>_<subCol>]) fill
	// the sub-columns one line per <tr>, and every other cell (checkbox,
	// plain, count) spans the <tr>s with rowspan. Rows without span and
	// configs without sub columns render a single <tr> as before.
	function rowHTML(config, row, state) {
		state = state || {};
		var selected = !!(state.selected && state.selected[row.id]);
		var bg = selected ? ROW_SELECTED : ROW_BASE;
		var hasSub = config.columns.some(function (c) { return c.sub && c.sub.length; });
		if (!hasSub) {
			var cells = config.columns.map(function (col) {
				if (col.type === 'checkbox') { return checkboxCell(col, row, bg, selected); }
				return cellHTML(col, row, bg);
			}).join('');
			return '<tr class="luminum-row" data-id="' + row.id + '">' + cells + '</tr>';
		}
		var span = (row.span && row.span > 1) ? row.span : 1;
		var phys = physicalColumns(config);
		var html = '';
		for (var r = 0; r < span; r++) {
			var cells = '';
			phys.forEach(function (p) {
				var col = p.col;
				if (p.subIndex !== null) {
					cells += cellHTML({ key: col.key + '_' + r + '_' + p.subIndex, width: col.width, align: col.align, whiteSpace: col.whiteSpace }, row, bg);
				} else if (r === 0) {
					// A span-1 row has no sub-<tr>s to span.
					var rs = span > 1 ? span : null;
					if (col.type === 'checkbox') { cells += checkboxCell(col, row, bg, selected, rs); }
					else { cells += cellHTML(col, row, bg, rs); }
				}
			});
			html += '<tr' + (r === 0 ? ' class="luminum-row" data-id="' + row.id + '"' : '') + '>' + cells + '</tr>';
		}
		return html;
	}

	// Render the data rows for a set of rows, or the empty-state row.
	function rowsHTML(config, rows, state) {
		if (!rows.length) {
			return '<tr><td colspan="' + physicalColumns(config).length +
				'" style="text-align: center; background-color: ' + ROW_BASE +
				'; font-weight: normal; font-style: italic;">' +
				escapeHTML(config.emptyMessage || 'No Results') + '</td></tr>';
		}
		return rows.map(function (row) { return rowHTML(config, row, state); }).join('\n');
	}

	// Map a client CSTATE to its status bucket (the Client Status page's
	// green/yellow/red/gray filter rows and icon column): OK is green, WARN
	// yellow, OFFLINE gray, and every other state (CRIT, DEACT, ...) red.
	function stateBucket(state) {
		if (state === 'OK') { return 'green'; }
		if (state === 'WARN') { return 'yellow'; }
		if (state === 'OFFLINE') { return 'offline'; }
		return 'red';
	}

	// Client-side filtering. state: { text, platforms: {linux,macos,windows},
	// states: {green,yellow,red,offline}, checkin: {cutoff},
	// subset: {field, checked: {value: true}} }.
	// A platform or state filter only applies when at least one of its boxes
	// is checked. checkin.cutoff is an epoch-seconds instant: rows whose
	// lastseen_ts is missing or earlier than it are dropped (the check-in
	// time filter). A subset filter (e.g. client version) only applies when
	// at least one value is checked: rows whose row[field] is not a checked
	// value are dropped.
	function filterRows(rows, config, state) {
		state = state || {};
		var text = (state.text || '').toLowerCase();
		var pf = state.platforms || {};
		var anyPlatform = pf.linux || pf.macos || pf.windows;
		var sf = state.states || {};
		var anyState = sf.green || sf.yellow || sf.red || sf.offline;
		var cutoff = (state.checkin && state.checkin.cutoff) || null;
		var sub = state.subset || null;
		var anySub = false;
		if (sub) {
			for (var v in sub.checked) { if (sub.checked[v]) { anySub = true; break; } }
		}
		var keys = config.searchKeys;
		return rows.filter(function (row) {
			if (anyPlatform) {
				if (!pf[String(row.platform).toLowerCase()]) { return false; }
			}
			if (anyState) {
				if (!sf[stateBucket(row.state)]) { return false; }
			}
			if (anySub) {
				if (!sub.checked[String(row[sub.field])]) { return false; }
			}
			if (cutoff !== null) {
				if (row.lastseen_ts === null || row.lastseen_ts === undefined || row.lastseen_ts < cutoff) { return false; }
			}
			if (text) {
				var hay = keys
					? keys.map(function (k) { return row[k]; }).join(' ').toLowerCase()
					: JSON.stringify(row).toLowerCase();
				if (hay.indexOf(text) === -1) { return false; }
			}
			return true;
		});
	}

	// --- DOM helpers (browser only) -----------------------------------------

	// Re-render the data rows of a <table> that contains a
	// <tbody data-luminum-body>. The toolbar/footer rows are left untouched.
	// Also pins the column widths: the table is switched to table-layout:
	// fixed and a <colgroup> is (re)generated from the config so the checkbox
	// column holds its fixed width instead of stretching with the table.
	function render(tableEl, config, data, state) {
		tableEl.style.tableLayout = 'fixed';
		var cg = tableEl.querySelector('colgroup');
		if (!cg) {
			cg = document.createElement('colgroup');
			tableEl.insertBefore(cg, tableEl.firstChild);
		}
		cg.innerHTML = colgroupCols(config);
		var tbody = tableEl.querySelector('tbody[data-luminum-body]');
		tbody.innerHTML = rowsHTML(config, filterRows(data.rows, config, state), state);
	}

	// Poll a JSON endpoint on an interval. Returns { stop, refresh }.
	function poll(url, opts) {
		opts = opts || {};
		var interval = opts.interval || 5000;
		var timer = null;
		var active = true;

		function fetchOnce() {
			return fetch(url, { credentials: 'same-origin', headers: { 'Accept': 'application/json' } })
				.then(function (r) {
					if (!r.ok) { throw new Error('HTTP ' + r.status); }
					return r.json();
				})
				.then(opts.onData, opts.onError);
		}

		function tick() {
			if (!active) { return; }
			fetchOnce().then(function () {
				if (active) { timer = setTimeout(tick, interval); }
			});
		}

		timer = setTimeout(tick, interval);
		return {
			stop: function () { active = false; if (timer) { clearTimeout(timer); } },
			// Returns the fetch promise (or undefined when stopped) so callers
			// can tell when the reload has settled.
			refresh: function () { if (active) { return fetchOnce(); } }
		};
	}

	// Attach a live text filter to a server-rendered table (the console pages
	// that print their rows in PHP instead of rendering them client-side). As
	// the user types, data rows whose visible text does not contain the
	// case-insensitive filter string are hidden, and a "No Results" row is
	// shown when every data row is filtered out — the same behaviour as the
	// Client Status page's filter.
	//
	//   filterId - id of the <input> to listen on; its enclosing <table> is the
	//              table that gets filtered.
	//   onFilter - optional callback invoked as onFilter(visible, total) after
	//              every re-apply (including the initial one), so the page can
	//              keep a "displayed of total" counter in step with the filter.
	//
	// Data rows are the <tr> elements that contain a row checkbox
	// (input[id^="ID"]); the header, counter and footer rows do not. When the
	// table has data rows but no "No Results" row in the markup, one is created
	// (hidden) and toggled as the filter changes.
	function attachTextFilter(filterId, onFilter) {
		var filterEl = document.getElementById(filterId);
		if (!filterEl) { return; }
		var tableEl = filterEl.closest('table');
		if (!tableEl) { return; }

		var rows = Array.prototype.filter.call(tableEl.querySelectorAll('tr'), function (tr) {
			return !!tr.querySelector('input[id^="ID"]');
		});

		var emptyRow = tableEl.querySelector('tr[data-luminum-empty]');
		if (!emptyRow && rows.length) {
			emptyRow = document.createElement('tr');
			emptyRow.setAttribute('data-luminum-empty', '');
			emptyRow.style.display = 'none';
			var td = document.createElement('td');
			td.colSpan = rows[0].querySelectorAll('td').length;
			td.setAttribute('style', 'text-align: center; background-color: ' + ROW_BASE + '; font-weight: normal; font-style: italic;');
			td.textContent = 'No Results';
			emptyRow.appendChild(td);
			rows[rows.length - 1].parentNode.insertBefore(emptyRow, rows[rows.length - 1].nextSibling);
		}
		var emptyRowDefault = emptyRow ? emptyRow.style.display : '';

		function apply() {
			var text = (filterEl.value || '').toLowerCase();
			var visible = 0;
			rows.forEach(function (tr) {
				var match = text === '' || tr.textContent.toLowerCase().indexOf(text) !== -1;
				tr.style.display = match ? '' : 'none';
				if (match) { visible++; }
			});
			if (emptyRow) {
				emptyRow.style.display = (text === '') ? emptyRowDefault : (visible === 0 ? '' : 'none');
			}
			if (typeof onFilter === 'function') { onFilter(visible, rows.length); }
		}

		filterEl.addEventListener('input', apply);
		apply();
	}

	return {
		ROW_BASE: ROW_BASE,
		ROW_SELECTED: ROW_SELECTED,
		CHECKBOX_COL_WIDTH: CHECKBOX_COL_WIDTH,
		escapeHTML: escapeHTML,
		physicalColumns: physicalColumns,
		headerHTML: headerHTML,
		colgroupHTML: colgroupHTML,
		rowHTML: rowHTML,
		rowsHTML: rowsHTML,
		stateBucket: stateBucket,
		filterRows: filterRows,
		render: render,
		poll: poll,
		attachTextFilter: attachTextFilter
	};
}));
