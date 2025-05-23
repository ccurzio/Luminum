<?php
mysqli_select_db($db, "CONTENT") or die( "<h5>Fatal Error</h5>\n\n<p>Unable to access database.\n</p>");

$starttime = microtime(true);
$csquery = mysqli_query($db, "select cs.ID,cs.NAME,cs.DESCRIPTION,(select USERNAME from AUTH.USERS where ID = cs.OWNER) as OWNER,cs.CREATED,cs.MODIFIED,(select USERNAME from AUTH.USERS where ID = cs.EDITOR) as EDITOR,count(distinct p.ID) as PACKAGES, count(distinct s.ID) as SENSORS from SETS cs left join PACKAGES p on p.ID = cs.ID left join SENSORS s on s.ID = cs.ID group by cs.ID");
$endtime = microtime(true);
$duration = number_format((float)$endtime - $starttime, 2, '.', '');
$cscount = mysqli_num_rows($csquery);
?>
<div class="content">
	<h1>Content Sets</h1>

	<div class="module-content">
                <?php
                print "<div style=\"display: block; width: 100%; text-align: right;\">\n";
                if (isset($acctrole) && $acctrole <= 2) {
                        print "<button class=\"formgo\" style=\"margin-top: 5px; margin-right: 0;\">Create New</button>\n";
                        print "<button id=\"modify\" class=\"formgo\" style=\"margin-top: 5px; margin-right: 0;\" disabled=\"disabled\">Modify Selected</button>\n";
                        print "<button id=\"delete\" class=\"formgo\" style=\"margin-top: 5px; margin-right: 0;\" disabled=\"disabled\">Delete Selected</button>\n";
                        }
                print "<button id=\"getinfo\" class=\"formgo\" style=\"margin-top: 5px; margin-right: 0;\" disabled=\"disabled\">Get Info</button>\n";
                print "</div>\n";
                ?>
		<table style="margin-top: 10px;">
		<tr><td colspan="10"><div style="position: absolute; padding-top: 7px; padding-left: 5px;">0 of <?php print $cscount; ?> items</div>
		<div style="float: right; text-align: right; padding-right: 5px;">Filter: <input type="text" style="font-size: 15px; padding: 3px; margin-top: 0;" <?php if ($cscount == 0) { print "disabled=\"disabled\""; } ?>></div></td></tr>
		<tr><td style="width: 15px;">
		<?php
			if ($cscount == 0) { print "<input type=\"checkbox\" disabled=\"disabled\">"; }
			else { print "<input id=\"selectall\" type=\"checkbox\" onclick=\"allToggle()\">"; }
		?>
		</td><td style="width: 200px;">Name</td><td style="width: 450px;">Description</td><td style="width: 50px;">Packages</td><td style="width: 75px;">Sensors</td><td>Owner</td><td style="width: 175px;">Create Date</td><td style="width: 175px;">Last Modification</td><td style="width: 100px;">Modified By</tr>
		<?php

		if ($cscount == 0) {
			print "<tr><td colspan=\"10\" style=\"text-align: center; background-color: #494a69; font-weight: normal; font-style: italic;\">No Results</td></tr>\n";
			}
		else {
			while($row = mysqli_fetch_assoc($csquery)) { // (!isset($row["LASTSEEN"]) ? "Never" : $row["LASTSEEN"])
				print "<tr><td id=\"" . $row["ID"] . "A\" style=\"width: 15px; background-color: #494a69;\"><input id=\"ID" . $row["ID"] . "\" class=\"contentset\" type=\"checkbox\" onclick=\"rowHighlight(" . $row["ID"] . "); allCheck();\"></td><td id=\"" . $row["ID"] . "B\" style=\"width: 50px; background-color: #494a69; font-weight: normal;\">" . $row["NAME"] . "</td><td id=\"" . $row["ID"] . "C\" style=\"width: 75px; background-color: #494a69; font-weight: normal;\">" . $row["DESCRIPTION"] . "</td><td id=\"" . $row["ID"] . "D\" style=\"background-color: #494a69; font-weight: normal;\">" . $row["PACKAGES"] . "</td><td id=\"" . $row["ID"] . "E\" style=\"background-color: #494a69; font-weight: normal;\">" . $row["SENSORS"] . "</td><td id=\"" . $row["ID"] . "F\" style=\"width: 120px; background-color: #494a69; font-weight: normal;\">" . $row["OWNER"] . "</td><td id=\"" . $row["ID"] . "G\" style=\"width: 90px; background-color: #494a69; font-weight: normal;\">" . $row["CREATED"] . "</td><td id=\"" . $row["ID"] . "H\" style=\"width: 90px; background-color: #494a69; font-weight: normal;\">" . (!isset($row["MODIFIED"]) ? "Never" : $row["MODIFIED"]) . "</td>" . "<td id=\"" . $row["ID"] . "I\" style=\"width: 90px; background-color: #494a69; font-weight: normal;\">" . $row["EDITOR"] . "</td></tr>\n";
				}
			}
		?>
		<tr style="height: 35px;"><td colspan="10"><div style="position: absolute; padding-top: 5px;"></div><div style="float: right; text-align: right; padding-bottom: 2px; padding-right: 5px; font-weight: normal;"><i>Query Completed in <?php print $duration; ?> Seconds</i></div></td></tr>
		</table>
	</div>

<script>
function rowHighlight(idnum) {
	var checkBox = document.getElementById("ID" + idnum);
	const checkboxes = document.querySelectorAll('input[class="contentset"]');
	var checkTrigger = 0;

	checkboxes.forEach(checkbox => {
		if (checkbox.checked == true) { checkTrigger++; }
		});

	if (checkBox.checked == true) {
		var bgcolor = "#686993";
		buttontoggle = false;
		}
	else {
		var bgcolor = "#494a69";
		buttontoggle = true;
		}

	document.getElementById("modify").disabled = buttontoggle;
	document.getElementById("delete").disabled = buttontoggle;
	document.getElementById("getinfo").disabled = buttontoggle;

	if (document.getElementById("ID1").checked == true) {
		if (checkTrigger > 1) {
			document.getElementById("modify").disabled = "disabled";
			document.getElementById("delete").disabled = "disabled";
			document.getElementById("getinfo").disabled = "disabled";
			}
		else if (checkTrigger == 1) {
			document.getElementById("modify").disabled = "disabled";
			document.getElementById("delete").disabled = "disabled";
			document.getElementById("getinfo").disabled = false;
			}
		}
	else {
		if (checkTrigger > 1) {
			document.getElementById("modify").disabled = "disabled";
			document.getElementById("delete").disabled = false;
			document.getElementById("getinfo").disabled = "disabled";
			}
		else if (checkTrigger == 1) {
			document.getElementById("modify").disabled = false;
			document.getElementById("delete").disabled = false;
			document.getElementById("getinfo").disabled = false;
			}
	else { document.getElementById("selectall").checked = false; }
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

function allToggle() {
	const allCheckbox = document.getElementById("selectall");
	const checkboxes = document.querySelectorAll('input[class="contentset"]');

	checkboxes.forEach(checkbox => {
		checkbox.checked = allCheckbox.checked;
		var rowId = removeLetters(checkbox.id);
		rowHighlight(rowId);
		});
	}

function allCheck() {
	const checkboxes = document.querySelectorAll('input[class="contentset"]');
	var checkTrigger = 0;

	checkboxes.forEach(checkbox => {
		if (checkbox.checked == true) { checkTrigger++; }
		});

	if (checkTrigger == checkboxes.length) {
		document.getElementById("selectall").checked = "checked";
		}
	else { document.getElementById("selectall").checked = false; }
	}

function removeLetters(str) {
	return str.replace(/[a-zA-Z]/g, '');
	}
</script>
