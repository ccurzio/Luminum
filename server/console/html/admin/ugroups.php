<?php
mysqli_select_db($db, "AUTH") or die( "<h5>Fatal Error</h5>\n\n<p>Unable to access database.\n</p>");

$starttime = microtime(true);
$ugquery = mysqli_query($db, "select ID,NAME,AUTHOR,CREATED,MODIFIED,EDITOR from GROUPS order by NAME");
$endtime = microtime(true);

$duration = number_format((float)$endtime - $starttime, 2, '.', '');
$ugcount = mysqli_num_rows($ugquery);
?>

<div class="content">

<?php if ($_GET["view"] == "ugroups"): ?>
        <?php if (!isset($_GET["action"])): ?>

        <h1>User Groups</h1>

        <div class="module-content">
		<div class="pageactions">
		<a href="/index.php?view=ugroups&action=new"><button class="formgo" style="margin-top: 5px; margin-right: 0;">Create New</button></a>
		<button class="formgo" style="margin-top: 5px; margin-right: 0;" disabled="disabled">Edit Selected</button>
		<button class="formgo" style="margin-top: 5px; margin-right: 0;" disabled="disabled">Delete Selected</button>
		<button class="formgo" style="margin-top: 5px; margin-right: 0;" disabled="disabled">Get Info</button>
		</div>

		<table style="margin-top: 10px; text-align: left; table-layout: fixed;">
		<colgroup><col style="width: 32px;"><col><col style="width: 100px;"><col style="width: 75px;"><col style="width: 120px;"><col style="width: 150px;"><col style="width: 120px;"></colgroup>
		<tr class="luminum-bar"><td colspan="7"><div style="position: absolute; padding-top: 5px; padding-left: 5px;">0 of <?php print $ugcount; ?> items</div><div style="float: right; text-align: right; padding-right: 5px;">Filter: <input type="text" id="ugroupsfilter" style="font-size: 15px; padding: 3px; margin-top: 0;" maxlength="64" <?php if ($ugcount == 0) { print "disabled=\"disabled\""; } ?>></div></td></tr>
		<tr class="luminum-head"><td style="text-align: center; padding: 0;"><?php
			if ($ugcount == 0) { print "<input type=\"checkbox\" disabled=\"disabled\">"; }
			else { print "<input id=\"selectall\" type=\"checkbox\" onclick=\"allToggle();\">"; }
		?></td>
		<td>Name</td><td>Members</td><td>Author</td><td>Create Date</td><td>Last Modification</td><td>Modified By</td></tr>
		<?php
			if ($ugcount == 0) {
				print "<tr><td colspan=\"8\" style=\"text-align: center; background-color: #494a69; font-weight: normal; font-style: italic;\">No Results</td></tr>\n";
				}
		?>
		<tr class="luminum-bar" style="height: 35px;"><td colspan="8"><div style="position: absolute; padding-top: 5px;"></div><div style="float: right; text-align: right; padding-bottom: 2px; padding-right: 5px; font-weight: normal;"><i>Query Completed in <?php print $duration; ?> Seconds</i></div></td></tr>
		</table>
	</div>

<script src="layout/table.js"></script>
<script>
LuminumTable.attachTextFilter('ugroupsfilter');
</script>

	<?php elseif ($_GET["action"] == "new"): ?>

	<h1>Create User Group</h1>

	<?php endif; ?>

<?php endif; ?>
