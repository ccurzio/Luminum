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
			<tr><td colspan="8"><div style="position: absolute; padding-top: 5px; padding-left: 5px;"><span id="selcount">0</span> <span id="totcount">of 0</span> items</span> <img id="refresh" src="icons/refresh.png" style="cursor: pointer; margin-left: 5px; width: 15px; height: 15px; vertical-align: top;" onclick="cstatusRefresh()"></div><div style="float: right; text-align: right; padding-right: 5px;">Filter: <input type="text" id="cstatusfilter" style="font-size: 15px; padding: 3px; margin-top: 0;" maxlength="64"></div></td></tr>
			<tbody id="cstable-head"></tbody>
			<tbody data-luminum-body id="cstable-body"></tbody>
			<tr style="height: 35px;"><td colspan="8"><div style="position: absolute; padding-top: 5px;"></div><div style="float: right; text-align: right; padding-bottom: 2px; padding-right: 5px; font-weight: normal;"><i>Query Completed in <span id="queryms">0.00</span> Seconds</i></div></td></tr>
			</table>
		</div>
	</div>

	<div class="module-content" style="width: 21%; float: right; font-size: 13px;">
	<p>
		<b><input type="checkbox" id="checkinfilter" onclick="checkinform()"> Show systems that have checked in within:</b><br>
		<input id="intnum" type="text" style="font-size: 15px; padding: 5px; margin-top: 3px; width: 20px;" value="1" maxlength="2" disabled="disabled">
		<select name="filterint" id="filterint" style="font-size: 15px; height: 30px; margin-left: 2px;" disabled="disabled">
			 <option value="reg">Registration Interval</option>
			 <option value="minutes">Minute(s)</option>
			 <option value="hours">Hour(s)</option>
			 <option value="days">Day(s)</option>
			 <option value="weeks">Week(s)</option>
			 <option value="months">Month(s)</option>
		</select>
		<button id="fapply" class="formgo" style="margin-top: 5px; margin-right: 0; margin-left: 1px; height: 30px; padding-top: 5px;" disabled="disabled">Apply</button>
	</p>

	<p style="margin-top: 20px;">
	<span style="font-size: 15px; font-weight: bold;">Filter by Operating System:</span>
	</p>
	<table style="margin-bottom: 20px;">
	<tr><td style="width: 15px;"></td><td>Platform</td><td style="text-align: center;">Percentage</td><td style="text-align: center;">Count</td></tr>
	<tr><td class="lfilter" style="background-color: #494a69; width: 15px;"><input type="checkbox" id="filterlinux"></td><td class="lfilter" style="background-color: #494a69;">Linux</td><td class="lfilter" style="background-color: #494a69; text-align: center;"><span id="linuxpct">0</span>%</td><td class="lfilter" style="background-color: #494a69; text-align: center;"><span id="linuxcount">0</span></td></tr>
	<tr><td class="mfilter" style="background-color: #494a69; width: 15px;"><input type="checkbox" id="filtermac"></td><td class="mfilter" style="background-color: #494a69;">macOS</td><td class="mfilter" style="background-color: #494a69; text-align: center;"><span id="macospct">0</span>%</td><td class="mfilter" style="background-color: #494a69; text-align: center;"><span id="macoscount">0</span></td></tr>
	<tr><td class="wfilter" style="background-color: #494a69; width: 15px;"><input type="checkbox" id="filterwin"></td><td class="wfilter" style="background-color: #494a69;">Windows</td><td class="wfilter" style="background-color: #494a69; text-align: center;"><span id="winpct">0</span>%</td><td class="wfilter" style="background-color: #494a69; text-align: center;"><span id="wincount">0</span></td></tr>
	</table>

	<span id="verfilter" style="font-size: 15px; font-weight: bold;">Filter by Client Version:</span>
	<p>
	</p>
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
		{ key: 'hostname', label: 'Hostname' },
		{ key: 'ip', label: 'IP Address', width: '125px' },
		{ key: 'platform', label: 'Platform', width: '50px', align: 'center',
		  render: function (row) {
			return '<img src="images/' + LuminumTable.escapeHTML(row.platform).toLowerCase() + '.png" style="width: 24px; height: 24px; margin-top: 2px;">';
		  } },
		{ key: 'os', label: 'Operating System', width: '150px' },
		{ key: 'clientver', label: 'Client Version', width: '120px' },
		{ key: 'state', label: 'Status', width: '60px', align: 'center', padTop: '7px',
		  render: function (row) {
			var icon = row.state === 'OK' ? 'sysgreen.png' : (row.state === 'WARN' ? 'sysyellow.png' : 'sysred.png');
			return '<img src="/icons/' + icon + '" title="' + LuminumTable.escapeHTML(row.state) + '">';
		  } },
		{ key: 'lastseen', label: 'Last Check-In', width: '175px' }
	]
};

var cstatusState = { selected: {}, text: '', platforms: { linux: false, macos: false, windows: false } };
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

function cstatusOSBreakdown() {
	var total = cstatusData.count;
	var p = cstatusData.platforms;
	function setRow(prefix, count) {
		document.getElementById(prefix + 'pct').textContent = total > 0 ? Math.round((count / total) * 10000) / 100 : 0;
		document.getElementById(prefix + 'count').textContent = count;
	}
	setRow('linux', p.linux);
	setRow('macos', p.macos);
	setRow('win', p.windows);
}

// Re-render the table body and every derived UI element from the current
// data + state. Called after any data update or state change.
function cstatusApply() {
	if (!cstatusData) { return; }
	LuminumTable.render(cstableEl, cstatusConfig, cstatusData, cstatusState);

	var selCount = cstatusSelectedCount();
	document.getElementById('selcount').textContent = selCount;
	document.getElementById('totcount').textContent = 'of ' + cstatusData.count;
	document.getElementById('queryms').textContent = cstatusData.query_ms;
	cstatusButtons(selCount);
	cstatusOSBreakdown();
	document.getElementById('verfilter').style.display = cstatusData.count > 0 ? '' : 'none';

	var visible = LuminumTable.filterRows(cstatusData.rows, cstatusConfig, cstatusState);
	var allChecked = visible.length > 0 && visible.every(function (r) { return cstatusState.selected[r.id]; });
	document.getElementById('selectall').checked = allChecked;
}

function cstatusOSPanelHighlight(fid, checked) {
	var bg = checked ? '#686993' : '#494a69';
	var ch = fid === 'filterlinux' ? 'lfilter' : (fid === 'filtermac' ? 'mfilter' : 'wfilter');
	document.querySelectorAll('.' + ch).forEach(function (el) { el.style.backgroundColor = bg; });
}

function cstatusRefresh() {
	var btn = document.getElementById('refresh');
	if (btn.className !== 'refresh') {
		btn.className = 'refresh';
		btn.style.cursor = 'progress';
		cstableEl.style.cursor = 'progress';
	}
	if (cstatusPoll) { cstatusPoll.refresh(); }
}

function checkinform() {
	var on = document.getElementById('checkinfilter').checked;
	['intnum', 'filterint', 'fapply'].forEach(function (id) {
		document.getElementById(id).disabled = on ? false : 'disabled';
	});
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

document.getElementById('intnum').addEventListener('input', function (e) {
	e.target.value = e.target.value.replace(/[^0-9]/g, '');
});

// --- polling ----------------------------------------------------------------

cstatusPoll = LuminumTable.poll('/api/clients.php', {
	interval: 5000,
	onData: function (data) { cstatusData = data; cstatusApply(); },
	onError: function (err) { console.error('Client Status poll failed:', err); }
});
cstatusPoll.refresh();
</script>
