<?php
mysqli_select_db($db, "CONTENT") or die( "<h5>Fatal Error</h5>\n\n<p>Unable to access database.\n</p>");

$starttime = microtime(true);
$sensorquery = mysqli_query($db, "select ID,NAME,DESCRIPTION,MAC,LIN,WIN,AUTHOR,CREATED,MODIFIED,EDITOR,REVISIONS from SENSORS order by ID");
$csets = mysqli_query($db, "select ID,NAME from SETS where NAME != 'Luminum Core' order by NAME");
$endtime = microtime(true);

$duration = number_format((float)$endtime - $starttime, 2, '.', '');
$sensorcount = mysqli_num_rows($sensorquery);
?>

<div class="content">

<?php if ($_GET["view"] == "sensors"): ?>
	<?php if (!isset($_GET["action"])): ?>
	<h1>Sensors</h1>

	<div class="module-content">
		<?php
		print "<div style=\"display: block; width: 100%; text-align: right;\">\n";
		if (isset($acctrole) && $acctrole <= 2) {
			print "<a href=\"/index.php?view=sensors&action=new\"><button class=\"formgo\" style=\"margin-top: 5px; margin-right: 0;\">Create New</button></a>\n";
			print "<button class=\"formgo\" style=\"margin-top: 5px; margin-right: 0;\" disabled=\"disabled\">Modify Selected</button>\n";
			print "<button class=\"formgo\" style=\"margin-top: 5px; margin-right: 0;\" disabled=\"disabled\">Delete Selected</button>\n";
			}
		print "<button class=\"formgo\" style=\"margin-top: 5px; margin-right: 0;\" disabled=\"disabled\">Get Info</button>\n";
		print "</div>\n";
		?>
		<table style="margin-top: 10px;">
		<tr><td colspan="8"><div style="position: absolute; padding-top: 7px; padding-left: 5px;">0 of 0 items</div><div style="float: right; text-align: right; padding-right: 5px;">Content Set: <select id="contentset" name="contentset" style="margin-left: 2px; margin-right: 30px; margin-top: 2px; width: 170px; height: 28px;" <?php if ($sensorcount == 0) { print "disabled=\"disabled\""; } ?>>
			<option value="all">All</option>
			<?php
			while ($csrow = mysqli_fetch_assoc($csets)) {
				print "<option value=\"" . $csrow["ID"] . "\">" . $csrow["NAME"] . "</option>\n";
				}
			?>
		</select> Filter: <input type="text" style="font-size: 15px; padding: 3px; margin-top: 0;" <?php if ($sensorcount == 0) { print "disabled=\"disabled\""; } ?>></div></td></tr>
		<tr><td style="width: 15px;">
		<?php
			if ($sensorcount == 0) { print "<input type=\"checkbox\" disabled=\"disabled\">"; }
			else { print "<input type=\"checkbox\">"; }
		?>
		</td><td style="width: 200px;">Name</td><td>Description</td><td style="width: 100px;">OS</td><td style="width: 100px;">Author</td><td style="width: 175px;">Create Date</td><td style="width: 175px;">Last Modification</td><td style="width: 100px;">Modified By</td></tr>
		<?php
		if ($sensorcount == 0) {
			print "<tr><td colspan=\"8\" style=\"text-align: center; background-color: #494a69; font-weight: normal; font-style: italic;\">No Results</td></tr>\n";
			}
		else {
			while($row = mysqli_fetch_assoc($sensorquery)) {
				print "<tr><td id=\"" . $row["ID"] . "A\" style=\"width: 15px; background-color: #494a69;\"><input id=\"ID" . $row["ID"] . "\" type=\"checkbox\" onclick=\"rowHighlight(" . $row["ID"] . ")\"></td><td id=\"" . $row["ID"] . "B\" style=\"width: 50px; background-color: #494a69; font-weight: normal;\">" . $row["NAME"] . "</td><td id=\"" . $row["ID"] . "C\" style=\"width: 75px; background-color: #494a69; font-weight: normal;\">" . $row["DESCRIPTION"] . "</td><td id=\"" . $row["ID"] . "D\" style=\"width: 120px; background-color: #494a69; font-weight: normal;\">" . "COMPAT" . "</td><td id=\"" . $row["ID"] . "E\" style=\"background-color: #494a69; font-weight: normal;\">" . "AUTHOR" . "</td><td id=\"" . $row["ID"] . "F\" style=\"width: 90px; background-color: #494a69; font-weight: normal;\">" . $row["CREATED"] . "</td>" . "<td id=\"" . $row["ID"] . "G\" style=\"width: 90px; background-color: #494a69; font-weight: normal;\">" . $row["MODIFIED"] . "</td><td id=\"" . $row["ID"] . "H\" style=\"background-color: #494a69; font-weight: normal;\">" . $row["EDITOR"] . "</td></tr>\n";
				}
			}
		?>
		<tr style="height: 35px;"><td colspan="8"><div style="position: absolute; padding-top: 5px;"></div><div style="float: right; text-align: right; padding-bottom: 2px; padding-right: 5px; font-weight: normal;"><i>Query Completed in <?php print $duration; ?> Seconds</i></div></td></tr>
		</table>
	</div>

	<?php elseif ($_GET["action"] == "new"): ?>

		<?php
		if (isset($acctrole) && $acctrole <= 2): ?>
		<h1>Create New Sensor</h1>

		<div class="module-content" style="overflow: auto; min-width: 1000px;">
			<div style="float: left;">
				<table style="margin-top: 10px; margin-bottom: 20px; border: 0;">
				<tr><td style="background-color: transparent; border: 0; color: #444;">Name: <span style="color: red;">*</span></td><td style="background-color: transparent; border: 0; color: #444;">Timeout: <span style="color: red;">*</span></td></tr>
				<tr><td style="background-color: transparent; border: 0; color: #444;"><input type="text" name="pkgname" style="width: 400px;"></td><td style="background-color: transparent; border: 0; color: #444;"><input id="timeout" type="text" style="width: 30px;" value="30"><select id="tint" style="width: 100px; margin-left: 10px; height: 33px;"><option value="sec">Second(s)</option><option value="min">Minute(s)</option></select></td></tr>
				<tr><td style="padding-top: 30px; background-color: transparent; border: 0; color: #444;">Description: <span style="color: red;">*</span></td><td style="padding-top: 30px; background-color: transparent; border: 0; color: #444;">Result Type:</td></tr>
				<tr><td style="background-color: transparent; border: 0; color: #444;"><input type="text" name="pkgdesc" style="width: 400px;"></td><td style="background-color: transparent; border: 0; color: #444;"><select id="rtype" style="font-size: 15px; height: 33px; width: 300px; margin-left: 2px; margin-right: 30px;"><option value="text">Text</option><option value="number">Number</option><option value="ipaddress">IP Address</option><option value="datetime">DateTime</option></td></tr>
				<tr><td style="padding-top: 30px; background-color: transparent; border: 0; color: #444;">Content Set: <span style="color: red;">*</span></td><td style="padding-top: 30px; background-color: transparent; border: 0; color: #444;">Category:</td></tr>
				<tr><td style="background-color: transparent; border: 0; color: #444;"><select id="contentset" name="contentset" style="font-size: 15px; height: 33px; width: 430px; margin-left: 2px; margin-right: 30px;">
				<?php
				while ($csrow = mysqli_fetch_assoc($csets)) {
					print "<option value=\"" . $csrow["ID"] . "\">" . $csrow["NAME"] . "</option>\n";
					}
				?>
				</select></td><td style="background-color: transparent; border: 0; color: #444;"><select id="category" style="font-size: 15px; height: 33px; width: 430px; margin-left: 2px; margin-right: 30px;"></select></td></tr>
				<tr><td style="padding-top: 30px; background-color: transparent; border: 0; color: #444; font-weight: normal;" colspan="2"><input type="checkbox" id="case"> Results are Case Sensitive</td></tr>
				<tr><td style="background-color: transparent; border: 0; color: #444; font-weight: normal;" colspan="2"><input type="checkbox" id="split" onclick="toggleSplit()"> Split Results into Columns <span class="delform" style="margin-left: 50px; opacity: 0;">Delimeter: </span><span class="delform" style="opacity: 0; color: red;">*</span><input class="delform" id="delimeter" type="text" style="opacity: 0; margin-left: 15px; width: 30px;"></td></tr>
				</table>

			</div>

			<div style="float: right; text-align: right; position: absolute; margin-top: 8px; width: 97%;">
				<button id="save" class="formgo" style="margin-top: 5px; margin-right: 0;" disabled="disabled">Save Sensor</button>
				<a href="/index.php?view=sensors"><button type="button" class="formgo" style="margin-top: 5px; margin-right: 0;">Cancel</button></a>
			</div>

		<hr style="width: 99%; margin-bottom: 20px;">

		<table style="border: 0; margin-bottom: 20px;">
		<tr><td style="background-color: transparent; border: 0; color: #444; font-weight: normal;"><input type="checkbox" id="useparams"> Parameter Inputs</td></tr>
		</table>

		<hr style="width: 99%; margin-bottom: 20px;">

		<div class="module-content" style="padding: 0 1px 1px 0; width: 600px; margin-left: auto; margin-right: auto;">
			<div class="tabbar tabbarback">
				<button type="button" class="tabbaritem tabbutton tablink tabbarsel" style="border-right: 1px solid #07f;" onclick="switchTab(event, 'Linux')">Linux</button>
				<button type="button" class="tabbaritem tabbutton tablink" style="border-right: 1px solid #07f;" onclick="switchTab(event, 'macOS')">macOS</button>
				<button type="button" class="tabbaritem tabbutton tablink" style="border-right: 1px solid #07f;" onclick="switchTab(event, 'Windows')">Windows</button>
			</div>

			<div style="margin: 8px 0 0 0; width: 100%;" id="Linux" class="configtab">
				<div style="text-align: left;">
					<input type="checkbox" style="margin-left: 8px;" onclick="leditor.textInput.getElement().disabled=true;"> Enabled &nbsp;&nbsp;&nbsp;&nbsp; Type: <select id="lstype"><option value="shell">Shell Script</option><option value="perl">Perl</option><option value="python">Python</option></select>
				</div>
				<div id="leditor" style="margin-top: 7px;"></div>
				<script src="/layout/src/ace.js" type="text/javascript" charset="utf-8"></script>
				<script>
					var leditor = ace.edit("leditor");
					leditor.getSession().setMode("ace/mode/sh");
				</script>
			</div>

			<div style="margin: 8px 0 0 0; width: 100%; display: none;" id="macOS" class="configtab">
				<div style="text-align: left;">
					<input type="checkbox" style="margin-left: 8px;"> Enabled &nbsp;&nbsp;&nbsp;&nbsp; Type: <select id="lstype"><option value="shell">Shell Script</option><option value="perl">Perl</option><option value="python">Python</option></select>
				</div>
				<div id="meditor" style="margin-top: 7px;"></div>
				<script>
					var meditor = ace.edit("meditor");
					meditor.getSession().setMode("ace/mode/sh");
				</script>
			</div>

			<div style="margin: 8px 0 0 0; width: 100%; display: none;" id="Windows" class="configtab">
				<div style="text-align: left;">
					<input type="checkbox" style="margin-left: 8px;"> Enabled &nbsp;&nbsp;&nbsp;&nbsp; Type: <select id="lstype"><option value="powershell">Powershell</option><option value="vbscript">VBScript</option><option value="python">Python</option></select>
				</div>
				<div id="weditor" style="margin-top: 7px;"></div>
				<script>
					var weditor = ace.edit("weditor");
					weditor.getSession().setMode("ace/mode/powershell");
				</script>
			</div>
		</div>
	</div>

<script>
function toggleSplit() {
	const delements = document.getElementsByClassName("delform");
	const checkBox = document.getElementById("split");
	var len = delements.length;

	if (checkBox.checked == true) { var ol = 1; }
	else { var ol = 0; }

	for (var i=0 ; i<len; i++) {
		delements[i].style.opacity = ol;
		}
	}

function switchTab(evt, configSect) {
	var i, x, tablinks;
	x = document.getElementsByClassName("configtab");

	for (i = 0; i < x.length; i++) {
		x[i].style.display = "none";
		}

	tablinks = document.getElementsByClassName("tablink");
	for (i = 0; i < x.length; i++) {
		tablinks[i].className = tablinks[i].className.replace(" tabbarsel", "");
		}

	document.getElementById(configSect).style.display = "block";
	evt.currentTarget.className += " tabbarsel";
	}
</script>

		<?php else: ?>

		<h1 style="color: red">Access Denied</h1>

		<?php endif; ?>
	<?php endif; ?>
<?php endif; ?>
