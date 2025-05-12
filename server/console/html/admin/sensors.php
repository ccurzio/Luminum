<div class="content">

<?php if ($_GET["view"] == "sensors"): ?>
	<?php if (!isset($_GET["action"])): ?>
	<h1>Sensors</h1>

	<div class="module-content">
		<?php
		print "<div style=\"display: block; width: 100%; text-align: right;\">\n";
		if (isset($acctrole) && $acctrole <= 2) {
			print "<a href=\"/index.php?view=sensors&action=new\"><button class=\"formgo\" style=\"margin-top: 5px; margin-right: 0;\">Create New</button></a>\n";
			print "<button class=\"formgo\" style=\"margin-top: 5px; margin-right: 0;\">Modify Selected</button>\n";
			print "<button class=\"formgo\" style=\"margin-top: 5px; margin-right: 0;\">Delete Selected</button>\n";
			}
		print "<button class=\"formgo\" style=\"margin-top: 5px; margin-right: 0;\">Get Info</button>\n";
		print "</div>\n";
		?>
		<table style="margin-top: 10px;">
		<tr><td colspan="8"><div style="position: absolute; padding-top: 5px;">0 of 0 items</div><div style="float: right; text-align: right">Content Set: <select id="contentset" name="contentset" style="font-size: 15px; height: 28px; margin-left: 2px; margin-right: 30px;"><option value="all">All</option><option value="core">Luminum Core</option></select> Filter: <input type="text" style="font-size: 12px; padding: 5px;"></div></td></tr>
		<tr><td style="width: 15px;"><input type="checkbox"></td><td style="width: 200px;">Name</td><td>Description</td><td style="width: 120px;">Compatibility</td><td style="width: 100px;">Author</td><td style="width: 175px;">Create Date</td><td style="width: 175px;">Last Modification</td><td style="width: 100px;">Modified By</tr>
		<tr><td colspan="8" style="text-align: center; background-color: #494a69; font-weight: normal; font-style: italic;">No Results</td></tr>
		</table>
	</div>

	<?php elseif ($_GET["action"] == "new"): ?>
	<h1>Create New Sensor</h1>

	<div class="module-content">
		<div style="display: block; width: 100%; text-align: right;">
			<button class="formgo" style="margin-top: 5px; margin-right: 0;">Save</button>
			<a href="/index.php?view=sensors"><button class="formgo" style="margin-top: 5px; margin-right: 0;">Cancel</button></a>
		</div>
		<table style="margin-top: 10px; border: 0;">
		<tr><td style="background-color: transparent; border: 0; color: #444;">Name: <span style="color: red;">*</span></td></tr>
		<tr><td style="background-color: transparent; border: 0; color: #444;"><input type="text" name="pkgname" style="width: 400px;"></td></tr>
		<tr><td style="padding-top: 30px; background-color: transparent; border: 0; color: #444;">Description: <span style="color: red;">*</span></td></tr>
		<tr><td style="background-color: transparent; border: 0; color: #444;"><input type="text" name="pkgdesc" style="width: 400px;"></td></tr>
		<tr><td style="padding-top: 30px; background-color: transparent; border: 0; color: #444;">Content Set: <span style="color: red;">*</span></td></tr>
		<tr><td style="background-color: transparent; border: 0; color: #444;"><select id="contentset" name="contentset" style="font-size: 15px; height: 30px; width: 430px; margin-left: 2px; margin-right: 30px;"></select></td></tr>
		</table>
	</div>

	<?php endif; ?>
<?php endif; ?>
