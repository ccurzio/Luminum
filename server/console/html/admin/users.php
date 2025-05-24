<?php
mysqli_select_db($db, "AUTH") or die( "<h5>Fatal Error</h5>\n\n<p>Unable to access database.\n</p>");

$starttime = microtime(true);
$usersquery = mysqli_query($db, "select ID,USERNAME,FULLNAME,EMAIL,TYPE,ROLE,REGDATE,LASTSEEN,ENABLED from USERS order by ID");
$endtime = microtime(true);

$duration = number_format((float)$endtime - $starttime, 2, '.', '');
$usercount = mysqli_num_rows($usersquery);

if ($acctrole > 2) {
	print "<div class=\"content\">\n";
	print "<h1 style=\"color: red\">Access Denied</h1>\n";
	}
else {
?>

<div class="content">
	<h1>User Accounts</h1>

	<div class="module-content">
		<div style="display: block; width: 100%; text-align: right;">
			<button class="formgo" style="margin-top: 5px; margin-right: 0;">Add User</button>
			<button class="formgo" id="modify" style="margin-top: 5px; margin-right: 0;" disabled="disabled">Modify Selected</button>
			<button class="formgo" id="delete" style="margin-top: 5px; margin-right: 0;" disabled="disabled">Delete Selected</button>
			<button class="formgo" id="getinfo" style="margin-top: 5px; margin-right: 0;" disabled="disabled">Get Info</button>
		</div>
		<table style="margin-top: 10px;">
		<tr><td colspan="9"><div style="position: absolute; padding-top: 5px; padding-left: 5px;"> <?php print "$usercount of $usercount items"; ?></div><div style="float: right; text-align: right; padding-right: 5px;">Filter: <input type="text" style="font-size: 15px; padding: 3px; margin-top: 0;"></div></td></tr>
		<tr><td style="width: 15px;"><input type="checkbox" id="selectall" onclick="allToggle()"></td><td style="width: 50px; text-align: center;">UID</td><td style="width: 75px; text-align: center;">Enabled</td><td style="width: 120px;">Username</td><td>Full Name</td><td style="width: 90px;">Role</td><td style="width: 90px;">Type</td><td>Created</td><td>Last Login</td></tr>

		<?php
			if ($usercount == 0) {
				print "<tr><td colspan=\"9\" style=\"text-align: center; background-color: #494a69; font-weight: normal; font-style: italic;\">No Results</td></tr>\n";
				}
			else {
				while($row = mysqli_fetch_assoc($usersquery)) {
					if ($row["ENABLED"] == "1") { $acctenabled = "<span style=\"font-weight: bold; font-size: 19px; color: #0ec940;\">✓</span>"; }
					else { $acctenabled = "<span style=\"font-weight: bold; font-size: 20px; color: #cf1104;\">&#10060;</span>"; }
					if ($row["ROLE"] == "1") { $acctrole = "Admin"; }
					elseif ($row["ROLE"] == "2") { $acctrole = "Power User"; }
					elseif ($row["ROLE"] == "3") { $acctrole = "User"; }
					elseif ($row["ROLE"] == "4") { $acctrole = "Read-Only"; }
					print "<tr><td id=\"" . $row["ID"] . "A\" style=\"width: 15px; background-color: #494a69;\"><input class=\"userrow\" id=\"ID" . $row["ID"] . "\" type=\"checkbox\" onclick=\"rowHighlight(" . $row["ID"] . "); allCheck();\"></td><td id=\"" . $row["ID"] . "B\" style=\"width: 50px; background-color: #494a69; font-weight: normal; text-align: center;\">" . $row["ID"] . "</td><td id=\"" . $row["ID"] . "C\" style=\"width: 75px; background-color: #494a69; font-weight: normal; text-align: center;\">" . $acctenabled . "</td><td id=\"" . $row["ID"] . "D\" style=\"width: 120px; background-color: #494a69; font-weight: normal;\">" . $row["USERNAME"] . "</td><td id=\"" . $row["ID"] . "E\" style=\"background-color: #494a69; font-weight: normal;\">" . $row["FULLNAME"] . "</td><td id=\"" . $row["ID"] . "F\" style=\"width: 90px; background-color: #494a69; font-weight: normal;\">" . $acctrole . "</td>" . "<td id=\"" . $row["ID"] . "G\" style=\"width: 90px; background-color: #494a69; font-weight: normal;\">" . $row["TYPE"] . "</td><td id=\"" . $row["ID"] . "H\" style=\"background-color: #494a69; font-weight: normal;\">" . $row["REGDATE"] . "</td><td id=\"" . $row["ID"] . "I\" style=\"background-color: #494a69; font-weight: normal;\">" . (!isset($row["LASTSEEN"]) ? "Never" : $row["LASTSEEN"]) . "</td></tr>\n";
					}
				}
		?>
		<tr style="height: 35px;"><td colspan="9"><div style="position: absolute; padding-top: 5px;"></div><div style="float: right; text-align: right; font-weight: normal; padding-right: 5px; padding-bottom: 2px;"><i>Query Completed in <?php print $duration; ?> Seconds</i></div></td></tr>
		</table>
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
		document.getElementById("modify").disabled = "disabled";
		}
	else {
		document.getElementById("getinfo").disabled = buttontoggle;
		document.getElementById("modify").disabled = buttontoggle;
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
	const checkboxes = document.querySelectorAll('input[class="userrow"]');

	checkboxes.forEach(checkbox => {
		checkbox.checked = allCheckbox.checked;
		var rowId = removeLetters(checkbox.id);
		rowHighlight(rowId);
		});
	}

function allCheck() {
	const checkboxes = document.querySelectorAll('input[class="userrow"]');
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

<?php } ?>
