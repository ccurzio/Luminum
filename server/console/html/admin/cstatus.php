<?php
mysqli_select_db($db, "CLIENTS") or die( "<h5>Fatal Error</h5>\n\n<p>Unable to access database.\n</p>");

$starttime = microtime(true);
$clientsquery = mysqli_query($db, "select ID,HOSTNAME,IPV4,OSPLATFORM,OSRELEASE,CLIENTVER,CSTATE,LASTSEEN from STATUS order by ID");
$endtime = microtime(true);

$duration = number_format((float)$endtime - $starttime, 2, '.', '');
$clientscount = mysqli_num_rows($clientsquery);
$lincount = 0;
$maccount = 0;
$wincount = 0;
?>

<div class="content">
	<h1>Client Status</h1>

	<div class="module-content" style="display: flex; justify-content: space-between; align-items: flex-start; width: 70%; float: left; margin-right: 0px;">
		<div style="display: block; width: 100%; text-align: right;">
			<button class="formgo" style="margin-top: 5px; margin-right: 0;" disabled="disabled">Deploy Action</button> <button class="formgo" style="margin-top: 5px; margin-right: 0;" disabled="disabled">Connect</button> <button class="formgo" style="margin-top: 5px; margin-right: 0;" disabled="disabled">Get Info</button>
			<table style="margin-top: 10px; text-align: left;">
			<tr><td colspan="8"><div style="position: absolute; padding-top: 5px; padding-left: 5px;">??? of <?php print "$clientscount"; ?> items <img src="icons/refresh.png" style="cursor: pointer; margin-left: 2px; width: 20px; height: 20px; vertical-align: text-bottom;"></div><div style="float: right; text-align: right; padding-right: 5px;">Filter: <input type="text" style="font-size: 15px; padding: 3px; margin-top: 0;"></div></td></tr>
			<tr><td style="width: 15px;">
			<?php 
			if ($clientscount == 0) { print "<input type=\"checkbox\" disabled=\"disabled\">"; }
			else { print "<input type=\"checkbox\">"; }
			?>
			</td><td>Hostname</td><td style="width: 125px;">IP Address</td><td style="width: 50px;">OS</td><td style="width: 150px;">Release</td><td style="width: 120px;">Client Version</td><td style="width: 60px;">Status</td><td style="width: 175px;">Last Check-In</td></tr>
			<?php
			if ($clientscount == 0) {
				print "<tr><td colspan=\"9\" style=\"text-align: center; background-color: #494a69; font-weight: normal; font-style: italic;\">No Results</td></tr>\n";
				}
			else {
				while($row = mysqli_fetch_assoc($clientsquery)) {
					if ($row["OSPLATFORM"] == "Linux") { $lincount++; }
					else if ($row["OSPLATFORM"] == "macOS") { $maccount++; }
					else if ($row["OSPLATFORM"] == "Windows") { $wincount++; }
					print "<tr><td id=\"" . $row["ID"] . "A\" style=\"width: 15px; background-color: #494a69;\"><input id=\"ID" . $row["ID"] . "\" type=\"checkbox\" onclick=\"rowHighlight(" . $row["ID"] . ")\"></td><td id=\"" . $row["ID"] . "B\" style=\"width: 50px; background-color: #494a69; font-weight: normal;\">" . $row["HOSTNAME"] . "</td><td id=\"" . $row["ID"] . "C\" style=\"width: 75px; background-color: #494a69; font-weight: normal;\">" . $row["IPV4"] . "</td><td id=\"" . $row["ID"] . "D\" style=\"width: 120px; background-color: #494a69; font-weight: normal;\"><img src=\"images/" . $row["OSPLATFORM"] . ".png\" style=\"width: 24px; height: 24px;\"></td><td id=\"" . $row["ID"] . "E\" style=\"background-color: #494a69; font-weight: normal;\">" . $row["OSRELEASE"] . "</td><td id=\"" . $row["ID"] . "F\" style=\"width: 90px; background-color: #494a69; font-weight: normal;\">" . $row["CLIENTVER"] . "</td>" . "<td id=\"" . $row["ID"] . "G\" style=\"width: 90px; background-color: #494a69; font-weight: normal;\">" . $row["CSTATE"] . "</td><td id=\"" . $row["ID"] . "H\" style=\"background-color: #494a69; font-weight: normal;\">" . $row["LASTSEEN"] . "</td></tr>\n";
					}
				}
			?>
			</table>
		</div>
	</div>

	<div class="module-content" style="width: 21%; float: right; font-size: 13px;">
	<p>
		<b><input type="checkbox" checked> Show systems that have checked in within:</b><br>
		<input type="text" style="font-size: 15px; padding: 5px; margin-top: 3px; width: 40px;" value="1">
		<select name="filterint" id="filterint" style="font-size: 15px; height: 30px; margin-left: 2px;">
			 <option value="reg">Registration Interval</option>
			 <option value="minutes">Minute(s)</option>
			 <option value="hours">Hour(s)</option>
			 <option value="days">Day(s)</option>
			 <option value="weeks">Week(s)</option>
			 <option value="months">Month(s)</option>
		</select>
		<button class="formgo" style="margin-top: 5px; margin-right: 0; margin-left: 1px; height: 30px; padding-top: 5px;">Apply</button>
	</p>

	<p style="margin-top: 20px;">
	<span style="font-size: 15px; font-weight: bold;">Filter by Operating System:</span>
	</p>
	<table style="margin-bottom: 20px;">
	<tr><td style="width: 15px;"></td><td>Platform</td><td>Percentage</td><td>Count</td></tr>
	<tr><td style="background-color: #494a69; width: 15px;"><input type="checkbox" id="filterlinux"></td><td style="background-color: #494a69;">Linux</td><td style="background-color: #494a69; text-align: center;">0%</td><td style="background-color: #494a69;"><?php print "$lincount"; ?></td></tr>
	<tr><td style="background-color: #494a69; width: 15px;"><input type="checkbox" id="filtermac"></td><td style="background-color: #494a69;">macOS</td><td style="background-color: #494a69; text-align: center;">0%</td><td style="background-color: #494a69;"><?php print "$maccount"; ?></td></tr>
	<tr><td style="background-color: #494a69; width: 15px;"><input type="checkbox" id="filterwin"></td><td style="background-color: #494a69;">Windows</td><td style="background-color: #494a69; text-align: center;">0%</td><td style="background-color: #494a69;"><?php print "$wincount"; ?></td></tr>
	</table>

	<span style="font-size: 15px; font-weight: bold;">Filter by Client Version:</span>
	<p>
	</p>
	</div>

</div>

<script>
function rowHighlight(idnum) {
	var checkBox = document.getElementById("ID" + idnum);
	const checkboxes = document.querySelectorAll('input[type="checkbox"]');
	var checkTrigger = 0;

	checkboxes.forEach(checkbox => {
		if (checkbox.checked == true) { checkTrigger++; }
		});

	if (checkBox.checked == true) {
		var bgcolor = "#686993";
		var buttontoggle = false;
		}
	else {
		var bgcolor = "#494a69";
		if (checkTrigger == 0) { var buttontoggle = "disabled"; }
		}

	document.getElementById("delete").disabled = buttontoggle;
	if (checkTrigger > 1) {
		document.getElementById("getinfo").disabled = "disabled";
		}
	else {
		document.getElementById("getinfo").disabled = buttontoggle;
		}
	document.getElementById(idnum + "A").style.backgroundColor = bgcolor;
	document.getElementById(idnum + "B").style.backgroundColor = bgcolor;
	document.getElementById(idnum + "C").style.backgroundColor = bgcolor;
	document.getElementById(idnum + "D").style.backgroundColor = bgcolor;
	document.getElementById(idnum + "E").style.backgroundColor = bgcolor;
	document.getElementById(idnum + "F").style.backgroundColor = bgcolor;
	document.getElementById(idnum + "G").style.backgroundColor = bgcolor;
	document.getElementById(idnum + "H").style.backgroundColor = bgcolor;
	document.getElementById(idnum + "I").style.backgroundColor = bgcolor;
	}
</script>

