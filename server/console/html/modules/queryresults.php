<?php
//
// Query Results. Renders the recent query commands and their per-sensor
// results (QUERYRESULTS, protocol 7.3) client-side from the JSON served by
// /api/queryresults.php, kept live via AJAX polling. The PHP here is only
// the page shell; all data flows through the API.
//
?>

<div class="content">
	<h1>Query Results</h1>

	<div class="module-content">
		<div style="position: absolute; padding-top: 5px; padding-left: 5px;"><span id="qrcount">0</span> queries</div>
		<div id="qrlist" style="margin-top: 10px;"></div>
	</div>

	<div style="height: 35px;"><div style="float: right; text-align: right; padding-bottom: 2px; padding-right: 5px; font-weight: normal;"><i>Query Completed in <span id="queryms">0.00</span> Seconds</i></div></div>
</div>

<script src="layout/table.js"></script>
<script>
'use strict';

var esc = LuminumTable.escapeHTML;

// PENDING/SENT: in flight; ACKED: answered; TIMEDOUT/EXPIRED: no answer.
function qrStatusIcon(status) {
	if (status === 'ACKED') { return 'sysgreen.png'; }
	if (status === 'TIMEDOUT' || status === 'EXPIRED') { return 'sysred.png'; }
	return 'sysyellow.png';
}

function qrResultRow(r) {
	var detail = r.status === 'OK'
		? (r.output !== null ? esc(r.output) : '')
		: esc(r.err !== null ? r.err : '');
	return '<tr>'
		+ '<td style="width: 200px; background-color: #494a69; font-weight: normal;">' + esc(r.hostname) + '</td>'
		+ '<td style="width: 200px; background-color: #494a69; font-weight: normal;">' + esc(r.sensor_name) + '</td>'
		+ '<td style="width: 80px; background-color: #494a69; font-weight: normal; text-align: center;">' + esc(r.status) + '</td>'
		+ '<td style="background-color: #494a69; font-weight: normal; white-space: pre-wrap; word-break: break-word;">' + detail + '</td>'
		+ '<td style="width: 160px; background-color: #494a69; font-weight: normal;">' + esc(r.ts) + '</td>'
		+ '</tr>';
}

function qrQueryBlock(q) {
	var head = '<tr>'
		+ '<td colspan="5" style="background-color: #34354f; font-weight: bold; padding-top: 8px;">'
		+ '<img src="/icons/' + qrStatusIcon(q.status) + '" title="' + esc(q.status) + '" style="vertical-align: middle; margin-right: 6px;">'
		+ esc(q.created)
		+ ' &nbsp;&middot;&nbsp; ' + (q.target === 'all' ? 'all endpoints' : 'client ' + esc(q.target))
		+ (q.conditions ? ' &nbsp;&middot;&nbsp; condition-filtered' : '')
		+ ' &nbsp;&middot;&nbsp; ' + esc(q.sensors.join(', '))
		+ '</td></tr>';
	var body;
	if (q.results.length === 0) {
		body = '<tr><td colspan="5" style="text-align: center; background-color: #494a69; font-weight: normal; font-style: italic;">No results yet</td></tr>';
	} else {
		body = q.results.map(qrResultRow).join('');
	}
	return '<table style="margin-bottom: 20px;">' + head + body + '</table>';
}

function qrRender(data) {
	var list = document.getElementById('qrlist');
	if (data.count === 0) {
		list.innerHTML = '<div style="text-align: center; background-color: #494a69; font-weight: normal; font-style: italic; padding: 10px;">No Results</div>';
	} else {
		list.innerHTML = data.queries.map(qrQueryBlock).join('');
	}
	document.getElementById('qrcount').textContent = data.count;
	document.getElementById('queryms').textContent = data.query_ms;
}

LuminumTable.poll('/api/queryresults.php', {
	interval: 5000,
	onData: qrRender,
	onError: function (err) { console.error('Query Results poll failed:', err); }
}).refresh();
</script>
