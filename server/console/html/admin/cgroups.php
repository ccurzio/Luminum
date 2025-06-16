<?php
mysqli_select_db($db, "CLIENTS") or die( "<h5>Fatal Error</h5>\n\n<p>Unable to access database.\n</p>");

$starttime = microtime(true);
$cgquery = mysqli_query($db, "select ID,NAME,AUTHOR,CREATED,MODIFIED,EDITOR from GROUPS order by NAME");
$endtime = microtime(true);

$duration = number_format((float)$endtime - $starttime, 2, '.', '');
$cgcount = mysqli_num_rows($cgquery);
?>

<div class="content">

<?php if ($_GET["view"] == "cgroups"): ?>
        <?php if (!isset($_GET["action"])): ?>

        <h1>Computer Groups</h1>

        <div class="module-content">
		<div style="display: block; width: 100%; text-align: right;">
		<a href="/index.php?view=cgroups&action=new"><button class="formgo" style="margin-top: 5px; margin-right: 0;">Create New</button></a>
		<button class="formgo" style="margin-top: 5px; margin-right: 0;" disabled="disabled">Modify Selected</button>
		<button class="formgo" style="margin-top: 5px; margin-right: 0;" disabled="disabled">Delete Selected</button>
		<button class="formgo" style="margin-top: 5px; margin-right: 0;" disabled="disabled">Get Info</button>

		<table style="margin-top: 10px; text-align: left;">
		<tr><td colspan="7"><div style="position: absolute; padding-top: 5px; padding-left: 5px;">0 of <?php print $cgcount; ?> items</div><div style="float: right; text-align: right; padding-right: 5px;">Filter: <input type="text" style="font-size: 15px; padding: 3px; margin-top: 0;" maxlength="64" <?php if ($cgcount == 0) { print "disabled=\"disabled\""; } ?>></div></td></tr>
		<tr><td style="width: 15px; text-align: center; padding: 0;"><?php
			if ($cgcount == 0) { print "<input type=\"checkbox\" disabled=\"disabled\">"; }
			else { print "<input id=\"selectall\" type=\"checkbox\" onclick=\"allToggle();\">"; }
		?></td>
		<td style="width: 400px;">Name</td><td style="width: 50px;">Members</td><td style="width: 50px;">Author</td><td style="width: 175px;">Create Date</td><td style="width: 175px;">Last Modification</td><td style="width: 50px;">Modified By</td></tr>
		<?php
			if ($cgcount == 0) {
				print "<tr><td colspan=\"8\" style=\"text-align: center; background-color: #494a69; font-weight: normal; font-style: italic;\">No Results</td></tr>\n";
				}
		?>
		<tr style="height: 35px;"><td colspan="8"><div style="position: absolute; padding-top: 5px;"></div><div style="float: right; text-align: right; padding-bottom: 2px; padding-right: 5px; font-weight: normal;"><i>Query Completed in <?php print $duration; ?> Seconds</i></div></td></tr>
		</table>
	</div>

	<?php endif; ?>

<?php endif; ?>
