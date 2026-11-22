<?php
//
// Client Status. The table is rendered client-side by LuminumTable from the
// JSON served by /api/clients.php and kept live via AJAX polling. The PHP
// here is only the page shell; all data flows through the API.
//
?>

<div class="content">
	<h1>Client Status</h1>

	<div class="module-content" style="display: flex; justify-content: space-between; align-items: flex-start; width: 70%; float: left; margin-right: 0px;">
		<div style="display: block; width: 100%; text-align: right;">
			<button class="formgo" style="margin-top: 5px; margin-right: 0;" disabled="disabled" id="deploy">Deploy Action</button> <button class="formgo" id="investigate" style="margin-top: 5px; margin-right: 0;" disabled="disabled">Investigate</button> <button class="formgo" style="margin-top: 5px; margin-right: 0;" disabled="disabled" id="getinfo">Get Info</button>
			<table id="cstable" style="margin-top: 10px; text-align: left;">
			<tr><td colspan="8"><div style="position: absolute; padding-top: 5px; padding-left: 5px;"><img id="refresh" src="icons/refresh.png" style="cursor: pointer; width: 15px; height: 15px; vertical-align: top;" onclick="cstatusRefresh()">&nbsp;&nbsp;<span id="viscount">0</span> of <span id="totcount">0</span> Items <span id="selcount"></span></div><div style="float: right; text-align: right; padding-right: 5px;">Filter: <input type="text" id="cstatusfilter" style="font-size: 15px; padding: 3px; margin-top: 0;" maxlength="64"></div></td></tr>
			<tbody id="cstable-head"></tbody>
			<tbody data-luminum-body id="cstable-body"></tbody>
			<tr style="height: 35px;"><td colspan="8"><div style="position: absolute; padding-top: 5px;"></div><div style="float: right; text-align: right; padding-bottom: 2px; padding-right: 5px; font-weight: normal;"><i>Query Completed in <span id="queryms">0.00</span> Seconds</i></div></td></tr>
			</table>
		</div>
	</div>

	<div class="module-content" style="width: 21%; float: right; font-size: 13px;">
	<p>
		<b><input type="checkbox" id="checkinfilter" checked onclick="checkinform()"> Show systems checked in within:</b><br>
		<input id="intnum" type="text" style="font-size: 15px; padding: 5px; margin-top: 3px; width: 20px;" value="1" maxlength="2">
		<select name="filterint" id="filterint" style="font-size: 15px; height: 30px; margin-left: 2px;">
			 <option value="reg">Check-in Interval(s)</option>
			 <option value="minutes">Minute(s)</option>
			 <option value="hours">Hour(s)</option>
			 <option value="days">Day(s)</option>
		</select>
		<button id="fapply" class="formgo" style="margin-top: 5px; margin-right: 0; margin-left: 1px; height: 30px; padding-top: 5px;">Apply</button>
	</p>

	<hr style="margin-top: 20px;">

	<p style="margin-top: 20px;">
	<span style="font-size: 15px; font-weight: bold;">Filter by Operating System:</span>
	</p>
	<table style="margin-bottom: 40px; table-layout: fixed;">
	<colgroup><col style="width: 32px;"><col><col style="width: 120px;"><col style="width: 70px;"></colgroup>
	<tr><td></td><td>Platform</td><td style="text-align: center;">Percentage</td><td style="text-align: center;">Count</td></tr>
	<tr><td class="lfilter" style="background-color: #494a69;"><input type="checkbox" id="filterlinux"></td><td class="lfilter" style="background-color: #494a69;">Linux</td><td class="lfilter" style="background-color: #494a69; text-align: center;"><span id="linuxpct">0</span>%</td><td class="lfilter" style="background-color: #494a69; text-align: center;"><span id="linuxcount">0</span></td></tr>
	<tr><td class="mfilter" style="background-color: #494a69;"><input type="checkbox" id="filtermac"></td><td class="mfilter" style="background-color: #494a69;">macOS</td><td class="mfilter" style="background-color: #494a69; text-align: center;"><span id="macospct">0</span>%</td><td class="mfilter" style="background-color: #494a69; text-align: center;"><span id="macoscount">0</span></td></tr>
	<tr><td class="wfilter" style="background-color: #494a69;"><input type="checkbox" id="filterwin"></td><td class="wfilter" style="background-color: #494a69;">Windows</td><td class="wfilter" style="background-color: #494a69; text-align: center;"><span id="winpct">0</span>%</td><td class="wfilter" style="background-color: #494a69; text-align: center;"><span id="wincount">0</span></td></tr>
	</table>

	<p style="margin-top: 20px;">
	<span id="statfilter" style="font-size: 15px; font-weight: bold;">Filter by Status:</span>
	</p>
	<table style="margin-bottom: 40px; table-layout: fixed;">
	<colgroup><col style="width: 32px;"><col><col style="width: 120px;"><col style="width: 70px;"></colgroup>
	<tr><td></td><td style="text-align: center;">Status</td><td style="text-align: center;">Percentage</td><td style="text-align: center;">Count</td></tr>
	<tr><td class="gfilter" style="background-color: #494a69; text-align: center;"><input type="checkbox" id="filtergreen"></td><td class="gfilter" style="background-color: #494a69; text-align: center;"><img style="vertical-align: middle;" src="/icons/sysgreen.png"></td><td class="gfilter" style="background-color: #494a69; text-align: center;"><span id="greenpct">0</span>%</td><td class="gfilter" style="background-color: #494a69; text-align: center;"><span id="greencount">0</span></td></tr>
	<tr><td class="yfilter" style="background-color: #494a69; text-align: center;"><input type="checkbox" id="filteryellow"></td><td class="yfilter" style="background-color: #494a69; text-align: center;"><img style="vertical-align: middle;" src="/icons/sysyellow.png"></td><td class="yfilter" style="background-color: #494a69; text-align: center;"><span id="yellowpct">0</span>%</td><td class="yfilter" style="background-color: #494a69; text-align: center;"><span id="yellowcount">0</span></td></tr>
	<tr><td class="rfilter" style="background-color: #494a69; text-align: center;"><input type="checkbox" id="filterred"></td><td class="rfilter" style="background-color: #494a69; text-align: center;"><img style="vertical-align: middle;" src="/icons/sysred.png"></td><td class="rfilter" style="background-color: #494a69; text-align: center;"><span id="redpct">0</span>%</td><td class="rfilter" style="background-color: #494a69; text-align: center;"><span id="redcount">0</span></td></tr>
	<tr><td class="ofilter" style="background-color: #494a69; text-align: center;"><input type="checkbox" id="filteroffline"></td><td class="ofilter" style="background-color: #494a69; text-align: center;"><img style="vertical-align: middle;" src="/icons/sysgray.png"></td><td class="ofilter" style="background-color: #494a69; text-align: center;"><span id="offlinepct">0</span>%</td><td class="ofilter" style="background-color: #494a69; text-align: center;"><span id="offcount">0</span></td></tr>
	</table>

	<p style="margin-top: 20px;">
	<span id="verfilter" style="font-size: 15px; font-weight: bold;">Filter by Client Version:</span>
	</p>
	<table id="vertable" style="table-layout: fixed;">
	<colgroup><col style="width: 32px;"><col><col style="width: 120px;"><col style="width: 70px;"></colgroup>
	<tr><td></td><td>Version</td><td style="text-align: center;">Percentage</td><td style="text-align: center;">Count</td></tr>
	<tbody id="verrows"></tbody>
	</table>
	</div>

</div>

<script src="layout/table.js"></script>
<script>
'use strict';

var cstatusConfig = {
	emptyMessage: 'No Results',
	searchKeys: ['hostname', 'ip', 'os', 'clientver', 'platform'],
	columns: [
		{ type: 'checkbox', width: '15px', inputClass: 'client', idPrefix: 'ID',
		  header: '<input id="selectall" type="checkbox">' },
		{ key: 'hostname', label: 'Computer Name' },
		{ key: 'ip', label: 'IP Address', width: '125px' },
		{ key: 'platform', label: 'Platform', width: '75px', align: 'center',
		  render: function (row) {
			return '<img src="images/' + LuminumTable.escapeHTML(row.platform).toLowerCase() + '.png" style="width: 24px; height: 24px; margin-top: 2px;">';
		  } },
		{ key: 'os', label: 'Operating System' },
		{ key: 'clientver', label: 'Client Version', width: '120px' },
		{ key: 'state', label: 'Status', width: '75px', align: 'center', padTop: '7px',
		  render: function (row) {
			var icon = { green: 'sysgreen.png', yellow: 'sysyellow.png', red: 'sysred.png', offline: 'sysgray.png' }[LuminumTable.stateBucket(row.state)];
			return '<img src="/icons/' + icon + '" title="' + LuminumTable.escapeHTML(row.state) + '">';
		  } },
		{ key: 'lastseen', label: 'Last Check-In', width: '175px' }
	]
};

var cstatusState = {
	selected: {},
	text: '',
	platforms: { linux: false, macos: false, windows: false },
	states: { green: false, yellow: false, red: false, offline: false },
	// Client versions checked in the version filter (version -> true).
	versions: {},
	// The check-in time filter's setting; the cutoff (epoch seconds) is
	// derived from it and the latest poll in cstatusCheckinCutoff.
	checkin: { on: true, num: 1, unit: 'reg', cutoff: null }
};
// The version filter is the generic subset filter over the clientver field.
cstatusState.subset = { field: 'clientver', checked: cstatusState.versions };
var cstatusData = null;
var cstatusPoll = null;
var cstableEl = document.getElementById('cstable');
var cstableBody = cstableEl.querySelector('tbody[data-luminum-body]');

function cstatusSelectedCount() {
	var n = 0;
	for (var k in cstatusState.selected) { if (cstatusState.selected[k]) { n++; } }
	return n;
}

function cstatusButtons(n) {
	var inv = document.getElementById('investigate');
	var gi = document.getElementById('getinfo');
	var dep = document.getElementById('deploy');
	if (n >= 2) { inv.disabled = false; gi.disabled = true; dep.disabled = false; }
	else if (n === 1) { inv.disabled = false; gi.disabled = false; dep.disabled = false; }
	else { inv.disabled = true; gi.disabled = true; dep.disabled = true; }
}

// The filter tables' percentages and counts reflect the rows currently
// visible in the table (after every filter), not the full client list: a
// client hidden by the time filter contributes to neither.
function cstatusOSBreakdown(visible) {
	var total = visible.length;
	var counts = { linux: 0, macos: 0, windows: 0 };
	visible.forEach(function (r) {
		var k = String(r.platform).toLowerCase();
		if (counts.hasOwnProperty(k)) { counts[k]++; }
	});
	function setRow(prefix, count) {
		document.getElementById(prefix + 'pct').textContent = total > 0 ? Math.round((count / total) * 10000) / 100 : 0;
		document.getElementById(prefix + 'count').textContent = count;
	}
	setRow('linux', counts.linux);
	setRow('macos', counts.macos);
	setRow('win', counts.windows);
}

function cstatusStateBreakdown(visible) {
	var total = visible.length;
	var counts = { green: 0, yellow: 0, red: 0, offline: 0 };
	visible.forEach(function (r) { counts[LuminumTable.stateBucket(r.state)]++; });
	// The span ids in the markup (the offline row's count span is "offcount").
	function setRow(pctId, countId, count) {
		document.getElementById(pctId).textContent = total > 0 ? Math.round((count / total) * 10000) / 100 : 0;
		document.getElementById(countId).textContent = count;
	}
	setRow('greenpct', 'greencount', counts.green);
	setRow('yellowpct', 'yellowcount', counts.yellow);
	setRow('redpct', 'redcount', counts.red);
	setRow('offlinepct', 'offcount', counts.offline);
}

// The version filter's rows are generated from the client versions of the
// rows currently visible in the table (first-appearance order): one row per
// unique version, checked when that version is selected in the filter. The
// rows are rebuilt on every apply, so checkbox state and the row highlight
// come from cstatusState.versions, and the change listener is delegated on
// the stable table element.
function cstatusVerBreakdown(visible) {
	var total = visible.length;
	var counts = {};
	var order = [];
	visible.forEach(function (r) {
		var v = String(r.clientver);
		if (!counts.hasOwnProperty(v)) { counts[v] = 0; order.push(v); }
		counts[v]++;
	});
	var html = '';
	order.forEach(function (v) {
		var checked = !!cstatusState.versions[v];
		var bg = checked ? '#686993' : '#494a69';
		var pct = total > 0 ? Math.round((counts[v] / total) * 10000) / 100 : 0;
		html += '<tr>' +
			'<td class="vfilter" style="background-color: ' + bg + '; text-align: center;"><input type="checkbox" class="verchk" data-ver="' + LuminumTable.escapeHTML(v) + '"' + (checked ? ' checked' : '') + '></td>' +
			'<td class="vfilter" style="background-color: ' + bg + ';">' + LuminumTable.escapeHTML(v) + '</td>' +
			'<td class="vfilter" style="background-color: ' + bg + '; text-align: center;">' + pct + '%</td>' +
			'<td class="vfilter" style="background-color: ' + bg + '; text-align: center;">' + counts[v] + '</td>' +
			'</tr>';
	});
	document.getElementById('verrows').innerHTML = html;
}

// The check-in time filter's cutoff (epoch seconds, or null when the filter
// is off): the server clock from the latest poll minus the selected number of
// check-in intervals (CHECKININT minutes, 5 when the config has no valid
// value), minutes, hours, or days.
function cstatusCheckinCutoff() {
	if (!cstatusState.checkin.on || !cstatusData.server_ts) { return null; }
	var num = cstatusState.checkin.num;
	var secs;
	if (cstatusState.checkin.unit === 'minutes') { secs = 60 * num; }
	else if (cstatusState.checkin.unit === 'hours') { secs = 3600 * num; }
	else if (cstatusState.checkin.unit === 'days') { secs = 86400 * num; }
	else { secs = (cstatusData.checkinint || 5) * 60 * num; }
	return cstatusData.server_ts - secs;
}

// Re-render the table body and every derived UI element from the current
// data + state. Called after any data update or state change.
function cstatusApply() {
	if (!cstatusData) { return; }
	cstatusState.checkin.cutoff = cstatusCheckinCutoff();
	var visible = LuminumTable.filterRows(cstatusData.rows, cstatusConfig, cstatusState);
	LuminumTable.render(cstableEl, cstatusConfig, cstatusData, cstatusState);

	var selCount = cstatusSelectedCount();
	document.getElementById('viscount').textContent = visible.length;
	document.getElementById('totcount').textContent = cstatusData.count;
	document.getElementById('selcount').textContent = selCount > 0 ? '(' + selCount + ' Selected)' : '';
	document.getElementById('queryms').textContent = cstatusData.query_ms;
	cstatusButtons(selCount);
	cstatusOSBreakdown(visible);
	cstatusStateBreakdown(visible);
	cstatusVerBreakdown(visible);
	var empty = cstatusData.count === 0;
	document.getElementById('statfilter').style.display = empty ? 'none' : '';
	document.getElementById('verfilter').style.display = empty ? 'none' : '';
	document.getElementById('vertable').style.display = empty ? 'none' : '';

	var allChecked = visible.length > 0 && visible.every(function (r) { return cstatusState.selected[r.id]; });
	document.getElementById('selectall').checked = allChecked;
}

function cstatusOSPanelHighlight(fid, checked) {
	var bg = checked ? '#686993' : '#494a69';
	var ch = fid === 'filterlinux' ? 'lfilter' : (fid === 'filtermac' ? 'mfilter' : 'wfilter');
	document.querySelectorAll('.' + ch).forEach(function (el) { el.style.backgroundColor = bg; });
}

function cstatusStatePanelHighlight(fid, checked) {
	var bg = checked ? '#686993' : '#494a69';
	var ch = fid === 'filtergreen' ? 'gfilter' : (fid === 'filteryellow' ? 'yfilter' : (fid === 'filterred' ? 'rfilter' : 'ofilter'));
	document.querySelectorAll('.' + ch).forEach(function (el) { el.style.backgroundColor = bg; });
}

function cstatusRefresh() {
	var btn = document.getElementById('refresh');
	if (btn.className === 'refresh') { return; }
	btn.className = 'refresh';
	btn.style.cursor = 'progress';
	cstableEl.style.cursor = 'progress';
	var done = function () {
		btn.className = '';
		btn.style.cursor = 'pointer';
		cstableEl.style.cursor = '';
	};
	var p = cstatusPoll ? cstatusPoll.refresh() : null;
	if (p && p.then) { p.then(done, done); } else { done(); }
}

function checkinform() {
	var on = document.getElementById('checkinfilter').checked;
	['intnum', 'filterint', 'fapply'].forEach(function (id) {
		document.getElementById(id).disabled = on ? false : 'disabled';
	});
	if (on) {
		document.getElementById('intnum').value = '1';
		document.getElementById('filterint').value = 'reg';
		cstatusState.checkin.on = true;
		cstatusState.checkin.num = 1;
		cstatusState.checkin.unit = 'reg';
	} else {
		document.getElementById('intnum').value = '';
		cstatusState.checkin.on = false;
	}
	cstatusApply();
}

// --- render the static header (contains the select-all checkbox) ----------
// Must run before the event wiring below, which attaches to #selectall.

document.getElementById('cstable-head').innerHTML = LuminumTable.headerHTML(cstatusConfig);

// --- event wiring ----------------------------------------------------------

// Row selection (delegated): the body is re-rendered on every poll, so listen
// on the stable tbody rather than each row.
cstableBody.addEventListener('change', function (e) {
	if (e.target.classList.contains('client')) {
		cstatusState.selected[e.target.dataset.id] = e.target.checked;
		cstatusApply();
	}
});

document.getElementById('selectall').addEventListener('change', function (e) {
	var visible = cstatusData ? LuminumTable.filterRows(cstatusData.rows, cstatusConfig, cstatusState) : [];
	visible.forEach(function (r) { cstatusState.selected[r.id] = e.target.checked; });
	cstatusApply();
});

document.getElementById('cstatusfilter').addEventListener('input', function (e) {
	cstatusState.text = e.target.value;
	cstatusApply();
});

[['filterlinux', 'linux'], ['filtermac', 'macos'], ['filterwin', 'windows']].forEach(function (pair) {
	document.getElementById(pair[0]).addEventListener('change', function (e) {
		cstatusState.platforms[pair[1]] = e.target.checked;
		cstatusOSPanelHighlight(pair[0], e.target.checked);
		cstatusApply();
	});
});

[['filtergreen', 'green'], ['filteryellow', 'yellow'], ['filterred', 'red'], ['filteroffline', 'offline']].forEach(function (pair) {
	document.getElementById(pair[0]).addEventListener('change', function (e) {
		cstatusState.states[pair[1]] = e.target.checked;
		cstatusStatePanelHighlight(pair[0], e.target.checked);
		cstatusApply();
	});
});

// Version filter (delegated): the version rows are re-rendered on every
// apply, so listen on the stable table element rather than each row.
document.getElementById('vertable').addEventListener('change', function (e) {
	if (e.target.classList.contains('verchk')) {
		cstatusState.versions[e.target.dataset.ver] = e.target.checked;
		cstatusApply();
	}
});

document.getElementById('intnum').addEventListener('input', function (e) {
	e.target.value = e.target.value.replace(/[^0-9]/g, '');
});

document.getElementById('fapply').addEventListener('click', function () {
	var num = parseInt(document.getElementById('intnum').value, 10);
	if (!(num > 0)) { num = 1; }
	cstatusState.checkin.num = num;
	cstatusState.checkin.unit = document.getElementById('filterint').value;
	cstatusApply();
});

// --- polling ----------------------------------------------------------------

cstatusPoll = LuminumTable.poll('/api/clients.php', {
	interval: 5000,
	onData: function (data) { cstatusData = data; cstatusApply(); },
	onError: function (err) { console.error('Client Status poll failed:', err); }
});
cstatusPoll.refresh();
</script>
