<?php
mysqli_select_db($db, "CONTENT") or die( "<h5>Fatal Error</h5>\n\n<p>Unable to access database.\n</p>");

$starttime = microtime(true);
$sensorquery = mysqli_query($db, "select ID,NAME,DESCRIPTION,!ifnull(MSCRIPT,1) as MAC,!ifnull(LSCRIPT,1) as LIN,!ifnull(WSCRIPT,1) as WIN,AUTHOR,CREATED,MODIFIED,EDITOR from SENSORS order by ID");
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
		</td><td style="width: 200px;">Name</td><td>Description</td><td style="width: 100px;">Supports</td><td style="width: 100px;">Author</td><td style="width: 175px;">Create Date</td><td style="width: 175px;">Last Modification</td><td style="width: 100px;">Modified By</td></tr>
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
				<tr><td style="background-color: transparent; border: 0; color: #444;"><input type="text" name="pkgdesc" style="width: 400px;"></td><td style="background-color: transparent; border: 0; color: #444;"><select id="rtype" style="font-size: 15px; height: 33px; width: 300px; margin-left: 2px; margin-right: 30px;"><option value="text">Text</option><option value="number">Number</option><option value="ipaddress">IP Address</option><option value="datetime">Date/Time Stamp</option></td></tr>
				<tr><td style="padding-top: 30px; background-color: transparent; border: 0; color: #444;">Content Set: <span style="color: red;">*</span></td><td style="padding-top: 30px; background-color: transparent; border: 0; color: #444;">Category:</td></tr>
				<tr><td style="background-color: transparent; border: 0; color: #444;"><select id="contentset" name="contentset" style="font-size: 15px; height: 33px; width: 430px; margin-left: 2px; margin-right: 30px;">
				<?php
				while ($csrow = mysqli_fetch_assoc($csets)) {
					print "<option value=\"" . $csrow["ID"] . "\">" . $csrow["NAME"] . "</option>\n";
					}
				?>
				</select></td><td style="background-color: transparent; border: 0; color: #444;"><select id="category" style="font-size: 15px; height: 33px; width: 430px; margin-left: 2px; margin-right: 30px;">
				<option value="none">(None)</option>
				</select></td></tr>
				<tr><td style="padding-top: 30px; background-color: transparent; border: 0; color: #444; font-weight: normal;" colspan="2"><input type="checkbox" id="case"><span style="cursor: normal; user-select: none;" onclick="caseToggle()"> Results are Case Sensitive</span></td></tr>
				<tr><td style="background-color: transparent; border: 0; color: #444; font-weight: normal;" colspan="2"><input type="checkbox" id="split" onclick="toggleSplit()"><span style="cursor: normal; user-select: none;" onclick="csToggle()"> Split Results into Columns</span> <span class="delform" style="margin-left: 50px; opacity: 0;">Delimeter: </span><span class="delform" style="opacity: 0; color: red;">*</span><input class="delform" id="delimeter" type="text" style="opacity: 0; margin-left: 15px; width: 5px;" maxlength="1" value="|"></td></tr>
				</table>

			</div>

			<div style="float: right; text-align: right; position: absolute; margin-top: 8px; width: 97%;">
				<button id="save" class="formgo" style="margin-top: 5px; margin-right: 0;" disabled="disabled">Save Sensor</button>
				<a href="/index.php?view=sensors"><button type="button" class="formgo" style="margin-top: 5px; margin-right: 0;">Cancel</button></a>
			</div>

		<hr style="width: 99%; margin-bottom: 20px;">

		<!-- Query Parameters are on the back burner for now.
		<table style="border: 0; margin-bottom: 20px;">
		<tr><td style="background-color: transparent; border: 0; color: #444; font-weight: normal;"><input type="checkbox" id="useparams"><span style="cursor: normal; user-select: none;" onclick="paramToggle()"> Accepts Query Parameters</span></td></tr>
		</table>

		<hr style="width: 99%;">
		-->

		<div style="float: left; margin-left: 10px;">
			<table style="width: 250px; margin-left: auto; margin-right: auto; margin-top: 20px;">
			<tr><td style="width: 80px;">OS</td><td>Enabled</td><td style="text-align: center; width: 80px;">Size</td></tr>
			<tr><td style="background-color: #494a69; font-weight: normal;">Linux</td><td id="len" style="text-align: center; background-color: #494a69; font-weight: normal;"><span style=\"font-weight: bold; font-size: 13px; color: #cf1104;\">&#10060;</span></td><td id="lsize" style="background-color: #494a69; font-weight: normal;"></td></tr>
			<tr><td style="background-color: #494a69; font-weight: normal;">Mac</td><td id="men" style="text-align: center; background-color: #494a69; font-weight: normal;"><span style=\"font-weight: bold; font-size: 13px; color: #cf1104;\">&#10060;</span></td><td id="msize" style="background-color: #494a69; font-weight: normal;"></tr>
			<tr><td style="background-color: #494a69; font-weight: normal;">Windows</td><td id="wen" style="text-align: center; background-color: #494a69; font-weight: normal;"><span style=\"font-weight: bold; font-size: 13px; color: #cf1104;\">&#10060;</span></td><td id="wsize" style="background-color: #494a69; font-weight: normal;"></tr>
			</table>
		</div>

		<div class="module-content" style="padding: 0 1px 1px 0; width: 600px; margin-left: auto; margin-right: auto; margin-top: 40px;">
			<div class="tabbar tabbarback">
				<button type="button" class="tabbaritem tabbutton tablink tabbarsel" style="border-right: 1px solid #07f;" onclick="switchTab(event, 'Linux')">Linux</button>
				<button type="button" class="tabbaritem tabbutton tablink" style="border-right: 1px solid #07f;" onclick="switchTab(event, 'macOS')">macOS</button>
				<button type="button" class="tabbaritem tabbutton tablink" style="border-right: 1px solid #07f;" onclick="switchTab(event, 'Windows')">Windows</button>
			</div>

			<div style="margin: 8px 0 0 0; width: 100%;" id="Linux" class="configtab">
				<div style="text-align: left; color: #444;">
					<input id="leselect" type="checkbox" style="margin-left: 8px;" onclick="editorToggle('Linux');"> <span style="cursor: normal; user-select: none;" onclick="labelToggle('Linux')">Enabled</span> &nbsp;&nbsp;&nbsp;&nbsp; <span id="lstlabel" style="color: #777;">Type:</span> <select id="lstype" onchange="lsformat(document.getElementById('lstype').value);" disabled="disabled"><option value="shell">Shell Script</option><option value="perl">Perl</option><option value="python">Python</option></select>
				</div>
				<div id="leditor" style="margin-top: 7px;"></div>
				<script src="/layout/src/ace.js" type="text/javascript" charset="utf-8"></script>
				<script>
					var leditor = ace.edit("leditor");
					leditor.getSession().setMode("ace/mode/sh");
					leditor.getSession().on('change', function() {
						document.getElementById('lsize').innerHTML = formatBytes(leditor.session.getValue().length,1);
						});
				</script>
			</div>

			<div style="margin: 8px 0 0 0; width: 100%; display: none;" id="macOS" class="configtab">
				<div style="text-align: left; color: #444;"">
					<input id="meselect" type="checkbox" style="margin-left: 8px;" onclick="editorToggle('Mac');"> <span style="cursor: normal; user-select: none;" onclick="labelToggle('Mac');">Enabled</span> &nbsp;&nbsp;&nbsp;&nbsp; <span id="mstlabel" style="color: #777;">Type: <select id="mstype" onchange="msformat(document.getElementById('mstype').value)" disabled="disabled"><option value="shell">Shell Script</option><option value="perl">Perl</option><option value="python">Python</option></select>
				</div>
				<div id="meditor" style="margin-top: 7px;"></div>
				<script>
					var meditor = ace.edit("meditor");
					meditor.getSession().setMode("ace/mode/sh");
					meditor.getSession().on('change', function() {
						document.getElementById('msize').innerHTML = formatBytes(meditor.session.getValue().length,1);
						});
				</script>
			</div>

			<div style="margin: 8px 0 0 0; width: 100%; display: none;" id="Windows" class="configtab">
				<div style="text-align: left; color: #444;"">
					<input id="weselect" type="checkbox" style="margin-left: 8px;" onclick="editorToggle('Windows');"> <span style="cursor: normal; user-select: none;" onclick="labelToggle('Windows');">Enabled</span> &nbsp;&nbsp;&nbsp;&nbsp; <span id="wstlabel" style="color: #777;">Type:</span> <select id="wstype" onchange="wsformat(document.getElementById('wstype').value)" disabled="disabled"><option value="powershell">PowerShell</option><option value="vbscript">VBScript</option><option value="batch">Batch File</option><option value="python">Python</option></select>
				</div>
				<div id="weditor" style="margin-top: 7px;"></div>
				<script>
					var weditor = ace.edit("weditor");
					weditor.getSession().setMode("ace/mode/powershell");
					weditor.getSession().on('change', function() {
						document.getElementById('wsize').innerHTML = formatBytes(weditor.session.getValue().length,1);
						});
				</script>
			</div>
		</div>
	</div>

<script>
function caseToggle() {
	const checkBox = document.getElementById("case");

	if (checkBox.checked == true) { checkBox.checked = false; }
	else { checkBox.checked = true; }
	}

function csToggle() {
	const checkBox = document.getElementById("split");

	if (checkBox.checked == true) { checkBox.checked = false; }
	else { checkBox.checked = true; }
	toggleSplit();
	}

function paramToggle() {
	const checkBox = document.getElementById("useparams");

	if (checkBox.checked == true) { checkBox.checked = false; }
	else { checkBox.checked = true; }
	}

function labelToggle(editor) {
	if (editor == 'Linux') { var cbSelect = 'leselect'; }
	else if (editor == 'Mac') { var cbSelect = 'meselect'; }
	else if (editor == 'Windows') { var cbSelect = 'weselect'; }
	const checkBox = document.getElementById(cbSelect);

	if (checkBox.checked == true) { checkBox.checked = false; }
	else { checkBox.checked = true; }
	editorToggle(editor);
	}

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

function lsformat(value) {
	if (value == "shell") {
		leditor.getSession().setMode("ace/mode/sh");
		leditor.setValue("#!/bin/sh\n\n", 10);
		}
	else if (value == "perl") {
		leditor.getSession().setMode("ace/mode/perl");
		leditor.setValue("#!/usr/bin/perl -w\n\nuse strict;\n\n", 35);
		}
	else if (value == "python") {
		leditor.getSession().setMode("ace/mode/python");
		leditor.setValue("#!/usr/bin/python\n\n", 20);
		}
	document.getElementById('lsize').innerHTML = formatBytes(leditor.session.getValue().length,1);
	}

function msformat(value) {
	if (value == "shell") {
		meditor.getSession().setMode("ace/mode/sh");
		meditor.setValue("#!/bin/sh\n\n", 10);
		}
	else if (value == "perl") {
		meditor.getSession().setMode("ace/mode/perl");
		meditor.setValue("#!/usr/bin/perl -w\n\nuse strict;\n\n", 35);
		}
	else if (value == "python") {
		meditor.getSession().setMode("ace/mode/python");
		meditor.setValue("#!/usr/bin/python3\n\n", 21);
		}
	document.getElementById('msize').innerHTML = formatBytes(meditor.session.getValue().length,1);
	}

function wsformat(value) {
	if (value == "powershell") { weditor.getSession().setMode("ace/mode/powershell"); }
	else if (value == "vbscript") { weditor.getSession().setMode("ace/mode/vbscript"); }
	else if (value == "batch") { weditor.getSession().setMode("ace/mode/batchfile"); }
	else if (value == "python") { weditor.getSession().setMode("ace/mode/python"); }
	document.getElementById('wsize').innerHTML = formatBytes(weditor.session.getValue().length,1);
	}

function editorToggle(edsel) {
	if (edsel == "Linux") {
		const checkBox = document.getElementById('leselect');
		if (checkBox.checked == true) { enableEditor('Linux'); }
		else { disableEditor('Linux'); }
		}
	else if (edsel == "Mac") {
		const checkBox = document.getElementById('meselect');
		if (checkBox.checked == true) { enableEditor('Mac'); }
		else { disableEditor('Mac'); }
		}
	else if (edsel == "Windows") {
		const checkBox = document.getElementById('weselect');
		if (checkBox.checked == true) { enableEditor('Windows'); }
		else { disableEditor('Windows'); }
		}
	}

function disableEditor(edsel) {
	if (edsel == "Linux") {
		leditor.container.style.opacity = 0.5;
		leditor.container.style.pointerEvents="none";
		leditor.renderer.setStyle("disabled", true);
		document.getElementById('lstlabel').style.color = "#777";
		document.getElementById('lstype').disabled = true;
		document.getElementById('lstype').value = 'shell';
		leditor.setValue("",0);
		document.getElementById('len').innerHTML = '<span style=\"font-weight: bold; font-size: 13px; color: #cf1104;\">&#10060;</span>';
		document.getElementById('lsize').innerHTML = '';
		}
	else if (edsel == "Mac") {
		meditor.container.style.opacity = 0.5;
		meditor.container.style.pointerEvents="none";
		meditor.renderer.setStyle("disabled", true);
		document.getElementById('mstlabel').style.color = "#777";
		document.getElementById('mstype').disabled = true;
		document.getElementById('mstype').value = 'shell';
		meditor.setValue("",0);
		document.getElementById('men').innerHTML = '<span style=\"font-weight: bold; font-size: 13px; color: #cf1104;\">&#10060;</span>';
		document.getElementById('msize').innerHTML = '';
		}
	else if (edsel == "Windows") {
		weditor.container.style.opacity = 0.5;
		weditor.container.style.pointerEvents="none";
		weditor.renderer.setStyle("disabled", true);
		document.getElementById('wstlabel').style.color = "#777";
		document.getElementById('wstype').disabled = true;
		document.getElementById('wstype').value = 'powershell';
		weditor.setValue("",0);
		document.getElementById('wen').innerHTML = '<span style=\"font-weight: bold; font-size: 13px; color: #cf1104;\">&#10060;</span>';
		document.getElementById('wsize').innerHTML = '';
		}
	}

function enableEditor(edsel) {
	if (edsel == "Linux") {
		leditor.container.style.opacity = 1;
		leditor.container.style.pointerEvents="";
		leditor.renderer.setStyle("disabled", false);
		document.getElementById('lstlabel').style.color = "#444";
		document.getElementById('lstype').disabled = false;
		lsformat('shell');
		document.getElementById('len').innerHTML = '<span style=\"font-weight: bold; font-size: 16px; color: #0ec940;\">✓</span>';
		document.getElementById('lsize').innerHTML = formatBytes(leditor.session.getValue().length,1);
		}
	else if (edsel == "Mac") {
		meditor.container.style.opacity = 1;
		meditor.container.style.pointerEvents="";
		meditor.renderer.setStyle("disabled", false);
		document.getElementById('mstlabel').style.color = "#444";
		document.getElementById('mstype').disabled = false;
		msformat('shell');
		document.getElementById('men').innerHTML = '<span style=\"font-weight: bold; font-size: 16px; color: #0ec940;\">✓</span>';
		document.getElementById('msize').innerHTML = formatBytes(meditor.session.getValue().length,1);
		}
	else if (edsel == "Windows") {
		weditor.container.style.opacity = 1;
		weditor.container.style.pointerEvents="";
		weditor.renderer.setStyle("disabled", false);
		document.getElementById('wstlabel').style.color = "#444";
		document.getElementById('wstype').disabled = false;
		wsformat('powershell');
		document.getElementById('wen').innerHTML = '<span style=\"font-weight: bold; font-size: 16px; color: #0ec940;\">✓</span>';
		document.getElementById('wsize').innerHTML = formatBytes(weditor.session.getValue().length,1);
		}
	}

function formatBytes(bytes, decimals = 2) {
	if (!+bytes) return '0'
	const k = 1024
	const dm = decimals < 0 ? 0 : decimals
	const sizes = ['B', 'KB', 'MB', 'GB', 'TB']
	const i = Math.floor(Math.log(bytes) / Math.log(k))

	return `${parseFloat((bytes / Math.pow(k, i)).toFixed(dm))} ${sizes[i]}`
	}

disableEditor('Linux');
disableEditor('Mac');
disableEditor('Windows');
</script>

		<?php else: ?>

		<h1 style="color: red">Access Denied</h1>

		<?php endif; ?>
	<?php endif; ?>
<?php endif; ?>
