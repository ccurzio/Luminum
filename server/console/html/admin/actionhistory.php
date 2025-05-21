<?php
$starttime = microtime(true);

$endtime = microtime(true);
$duration = number_format((float)$endtime - $starttime, 2, '.', '');

$actioncount = 0;
?>
<div class="content">
	<h1>Action History</h1>

	<div class="module-content">
		<div style="display: block; width: 100%; text-align: right;">
			<button class="formgo" style="margin-top: 5px; margin-right: 0;" disabled="disabled">Reissue</button>
			<button class="formgo" style="margin-top: 5px; margin-right: 0;" disabled="disabled">Get Info</button>
		</div>
		<table style="margin-top: 10px;">
		<tr><td colspan="9"><div style="position: absolute; padding-top: 5px; padding-left: 5px;">0 of 0 items <img src="icons/refresh.png" style="cursor: pointer; margin-left: 2px; width: 20px; height: 20px; vertical-align: text-bottom;"></div><div style="float: right; text-align: right; padding-right: 5px;">Filter: <input type="text" style="font-size: 15px; padding: 3px; margin-top: 0;" <?php if ($actioncount == 0) { print "disabled=\"disabled\""; } ?>></div></td></tr>
		<tr><td style="width: 15px;">
		<?php
		if ($actioncount == 0) { print "<input type=\"checkbox\" disabled=\"disabled\">"; }
		else { print "<input type=\"checkbox\">"; }
		?>
		<td style="width: 30px;">Status</td><td style="width: 300px;">Name</td><td style="width: 75px;">Type</td><td style="width: 100px;">Issuer</td><td style="width: 175px;">Start Date</td><td style="width: 175px;">End Date</td><td style="width: 175px;">Last Modification</td><td style="width: 100px;">Modified By</tr>
		<tr><td colspan="9" style="text-align: center; background-color: #494a69; font-weight: normal; font-style: italic;">No Results</td></tr>
		<tr style="height: 35px;"><td colspan="9"><div style="position: absolute; padding-top: 5px;"></div><div style="float: right; text-align: right; padding-bottom: 2px; padding-right: 5px; font-weight: normal;">Query Completed in <?php print $duration; ?> Seconds</div></td></tr>
		</table>
	</div>
