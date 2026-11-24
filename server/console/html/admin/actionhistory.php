<?php
$starttime = microtime(true);

$endtime = microtime(true);
$duration = number_format((float)$endtime - $starttime, 2, '.', '');

$actioncount = 0;
?>
<div class="content">
	<h1>Action History</h1>

	<div class="module-content">
		<div class="pageactions">
			<button id="reissue" class="formgo" style="margin-top: 5px; margin-right: 0;" disabled="disabled">Reissue Selected</button>
			<button id="getinfo" class="formgo" style="margin-top: 5px; margin-right: 0;" disabled="disabled">Get Info</button>
		</div>
		<table id="ahtable" style="margin-top: 10px; table-layout: fixed;">
		<colgroup><col style="width: 32px;"><col style="width: 75px;"><col><col style="width: 75px;"><col style="width: 100px;"><col style="width: 150px;"><col style="width: 150px;"><col style="width: 150px;"><col style="width: 120px;"></colgroup>
		<tr class="luminum-bar"><td colspan="9"><div style="position: absolute; padding-top: 5px; padding-left: 5px;"><img id="refresh" src="icons/refresh.png" style="cursor: pointer; width: 15px; height: 15px; vertical-align: top;" onclick="reloadTable()">&nbsp;&nbsp;<span id="viscount"><?php print $actioncount; ?></span> of <span id="totcount"><?php print $actioncount; ?></span> Items <span id="selcount"></span></div><div style="float: right; text-align: right; padding-right: 5px;">Filter: <input type="text" id="actionhistoryfilter" style="font-size: 15px; padding: 3px; margin-top: 0;" <?php if ($actioncount == 0) { print "disabled=\"disabled\""; } ?> maxlength="64"></div></td></tr>
		<tr class="luminum-head"><td>
		<?php
		if ($actioncount == 0) { print "<input type=\"checkbox\" disabled=\"disabled\">"; }
		else { print "<input type=\"checkbox\">"; }
		?>
		</td><td>Status</td><td>Name</td><td>Type</td><td>Issuer</td><td>Start Date</td><td>End Date</td><td>Last Modification</td><td>Modified By</tr>
		<tr><td colspan="9" style="text-align: center; background-color: #494a69; font-weight: normal; font-style: italic;">No Results</td></tr>
		<tr class="luminum-bar" style="height: 35px;"><td colspan="9"><div style="position: absolute; padding-top: 5px;"></div><div style="float: right; text-align: right; padding-bottom: 2px; padding-right: 5px; font-weight: normal;"><i>Query Completed in <?php print $duration; ?> Seconds</i></div></td></tr>
		</table>
	</div>

<script src="layout/table.js"></script>
<script>
LuminumTable.attachTextFilter('actionhistoryfilter', function (visible) {
	document.getElementById('viscount').textContent = visible;
	});

// Column sort: a header click sorts the table by that column (ascending
// first, descending on the second click, cleared on the third); the arrow
// marker in the header shows the active column and direction.
var actionhistorySortTable = document.getElementById('actionhistoryfilter');
if (actionhistorySortTable) { LuminumTable.attachHeaderSort(actionhistorySortTable.closest('table')); }

function reloadTable() {
	var refreshButton = document.getElementById("refresh");
	if (refreshButton.className != "refresh") {
		refreshButton.className = "refresh";
		refreshButton.disabled = "disabled";
		refreshButton.style.cursor = "progress";
		document.getElementById('ahtable').style.cursor = "progress";
		}
	}
</script>
