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
		if (col.padTop) { s += 'padding-top: ' + col.padTop + ';'; }
		return s;
	}

	function headerCell(col) {
		var s = '';
		if (col.width) { s += 'width: ' + col.width + ';'; }
		if (col.align) { s += 'text-align: ' + col.align + ';'; }
		var style = s ? ' style="' + s + '"' : '';
		var inner = (col.header !== undefined) ? col.header : escapeHTML(col.label);
		return '<td' + style + '>' + inner + '</td>';
	}

	// Render the header <tr> for a column config.
	function headerHTML(config) {
		return '<tr>' + config.columns.map(headerCell).join('') + '</tr>';
	}

	// Render one <td> for a column. Columns with a render(row) function emit
	// raw HTML (icons, etc.); plain columns escape the row value.
	function cellHTML(col, row, bg) {
		var inner = col.render ? col.render(row) : escapeHTML(row[col.key]);
		return '<td style="' + cellStyle(col, bg) + '">' + inner + '</td>';
	}

	// Render one data row. The checkbox column is special-cased.
	function rowHTML(config, row, state) {
		state = state || {};
		var selected = !!(state.selected && state.selected[row.id]);
		var bg = selected ? ROW_SELECTED : ROW_BASE;
		var cells = config.columns.map(function (col) {
			if (col.type === 'checkbox') {
				var checked = selected ? ' checked' : '';
				return '<td id="' + row.id + 'A" style="background-color: ' + bg + '; font-weight: normal;width: 15px;">' +
					'<input class="' + (col.inputClass || 'row') + '" id="' + (col.idPrefix || 'ID') + row.id +
					'" data-id="' + row.id + '" type="checkbox"' + checked + '></td>';
			}
			return cellHTML(col, row, bg);
		}).join('');
		return '<tr data-id="' + row.id + '">' + cells + '</tr>';
	}

	// Render the data rows for a set of rows, or the empty-state row.
	function rowsHTML(config, rows, state) {
		if (!rows.length) {
			return '<tr><td colspan="' + config.columns.length +
				'" style="text-align: center; background-color: ' + ROW_BASE +
				'; font-weight: normal; font-style: italic;">' +
				escapeHTML(config.emptyMessage || 'No Results') + '</td></tr>';
		}
		return rows.map(function (row) { return rowHTML(config, row, state); }).join('\n');
	}

	// Client-side filtering. state: { text, platforms: {linux,macos,windows} }.
	// A platform filter only applies when at least one platform box is checked.
	function filterRows(rows, config, state) {
		state = state || {};
		var text = (state.text || '').toLowerCase();
		var pf = state.platforms || {};
		var anyPlatform = pf.linux || pf.macos || pf.windows;
		var keys = config.searchKeys;
		return rows.filter(function (row) {
			if (anyPlatform) {
				if (!pf[String(row.platform).toLowerCase()]) { return false; }
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
	function render(tableEl, config, data, state) {
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

	return {
		ROW_BASE: ROW_BASE,
		ROW_SELECTED: ROW_SELECTED,
		escapeHTML: escapeHTML,
		headerHTML: headerHTML,
		rowHTML: rowHTML,
		rowsHTML: rowsHTML,
		filterRows: filterRows,
		render: render,
		poll: poll
	};
}));
