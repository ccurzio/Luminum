<?php
$starttime = microtime(true);

$endtime = microtime(true);
$duration = number_format((float)$endtime - $starttime, 2, '.', '');

$actioncount = 0;
?>
<div class="content">
	<h1>Scheduled Actions</h1>
	<div class="module-content">
		<div class="pageactions">
			<button class="formgo" style="margin-top: 5px; margin-right: 0;" disabled="disabled">Edit Selected</button>
			<button class="formgo" style="margin-top: 5px; margin-right: 0;" disabled="disabled">Delete Selected</button>
			<button class="formgo" style="margin-top: 5px; margin-right: 0;" disabled="disabled">Get Info</button>
		</div>
		<table id="satable" style="margin-top: 10px; table-layout: fixed;">
		<colgroup><col style="width: 32px;"><col style="width: 85px;"><col style="width: 75px;"><col><col style="width: 100px;"><col style="width: 150px;"><col style="width: 150px;"><col style="width: 100px;"><col style="width: 150px;"></colgroup>
		<tr><td colspan="9"><div style="position: absolute; padding-top: 5px; padding-left: 5px;"><img id="refresh" src="icons/refresh.png" style="cursor: pointer; width: 15px; height: 15px; vertical-align: top;" onclick="reloadTable()">&nbsp;&nbsp;<span id="viscount"><?php print $actioncount; ?></span> of <span id="totcount"><?php print $actioncount; ?></span> Items <span id="selcount"></span></div><div style="float: right; text-align: right; padding-right: 5px;">Filter: <input type="text" id="actionsfilter" style="font-size: 15px; padding: 3px; margin-top: 0;" <?php if ($actioncount == 0) { print "disabled=\"disabled\""; } ?> maxlength="64"></div></td></tr>
		<tr><td>
		<?php
		if ($actioncount == 0) { print "<input type=\"checkbox\" disabled=\"disabled\">"; }
		else { print "<input type=\"checkbox\">"; }
		?>
		</td><td style="text-align: center;">Enabled</td><td>Status</td><td>Name</td><td>Issuer</td><td>Start Date</td><td>End Date</td><td>Repeat</td><td>Next Run</td></tr>
		<tr><td colspan="9" style="text-align: center; background-color: #494a69; font-weight: normal; font-style: italic;">No Results</td></tr>
		<tr style="height: 35px;"><td colspan="9"><div style="position: absolute; padding-top: 5px;"></div><div style="float: right; text-align: right; padding-bottom: 2px; padding-right: 5px; font-weight: normal;"><i>Query Completed in <?php print $duration; ?> Seconds</i></div></td></tr>
		</table>
	</div>

<script src="layout/table.js"></script>
<script>
LuminumTable.attachTextFilter('actionsfilter', function (visible) {
	document.getElementById('viscount').textContent = visible;
	});

function reloadTable() {
	var refreshButton = document.getElementById("refresh");
	if (refreshButton.className != "refresh") {
		refreshButton.className = "refresh";
		refreshButton.disabled = "disabled";
		refreshButton.style.cursor = "progress";
		document.getElementById('satable').style.cursor = "progress";
		}
	}
</script>
