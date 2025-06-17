<?php include ("layout/header.php"); ?>

<?php if (!isset($_GET['view']) || $_GET['view'] == "profile"): ?>
<?php
	mysqli_select_db($db, "AUTH") or die( "<h5>Fatal Error</h5>\n\n<p>Unable to access database.\n</p>");
	$userquery = mysqli_query($db, "select ID,USERNAME,FULLNAME,EMAIL,PHONE,TYPE,ROLE,REGDATE,(select CVAL from SYSTEM.CONFIG where CKEY = '2FA') as SYS2FA,(select CVAL from SYSTEM.CONFIG where CKEY = 'MINPASS') as MINPASS from USERS where USERNAME = (select USERNAME from USERS where ID = (select ID from SESSION where SID = '" . $_SESSION["SID"] . "'))");
	//$userquery = mysqli_query($db, "select ID,USERNAME,FULLNAME,EMAIL,PHONE,TYPE,ROLE,REGDATE from USERS where USERNAME = (select USERNAME from USERS where ID = (select ID from SESSION where SID = '" . $_SESSION["SID"] . "'))");
	$userinfo = $userquery->fetch_assoc();
	if ($userinfo["ROLE"] == "1") { $userrole = "Administrator"; }
	elseif ($userinfo["ROLE"] == "2") { $userrole = "Power User"; }
	elseif ($userinfo["ROLE"] == "3") { $userrole = "User"; }
	elseif ($userinfo["ROLE"] == "4") { $userrole = "Read-Only User"; }

	$tfua = "False";
	$tfsms = "False";
	$tfeml = "False";
	$tfapp = "False";

	if ($userinfo["SYS2FA"] != "Disabled") {
		$tfquery = mysqli_query($db, "select * from 2FA where UID = " . $userinfo["ID"]);
		while ($tfrow = mysqli_fetch_assoc($tfquery)) {
			if ($tfrow["ENABLED"] == 1) {
				$tfua = "True";
				if ($tfrow["METHOD"] == "SMS") { $tfsms = "True"; }
				elseif ($tfrow["METHOD"] == "EMAIL") { $tfsms = "True"; }
				elseif ($tfrow["METHOD"] == "APP") { $tfapp = "True"; }
				}
			}
		}
?>

<div class="content">
	<h1>Account Profile</h1>

		<form id="userform" action="user.php" method="POST">
		<div style="width: 80%; text-align: right; margin: -50px auto 10px auto;">
			<button id="save" class="formgo" style="margin-right: 0;" disabled="disabled">Save Changes</button>
			<input type="reset" id="reset" value="Reset Values" class="formgo" onclick="return resetForm();">
		</div>


	<div class="module-content" style="padding: 0; width: 75%; margin-left: auto; margin-right: auto; padding: 10px;">
		<div style="margin-top: 10px;">
			<table style="width: 75%; border: 0; margin-left: auto; margin-right: auto; margin-top: 15px; margin-bottom: 15px;">
                        <tr><td style="color: #444; background-color: transparent; border: 0; font-weight: bold;">Userame:</td><td style="color: #444; background-color: transparent; border: 0; font-weight: normal;"> <input id="username" type="text" value="<?php print $userinfo["USERNAME"]; ?>" maxlength="16" tabindex="1"></td><td style="color: #444; background-color: transparent; border: 0; font-weight: bold;">Password: <span style="color: red;">*</span> <div class="tooltip"><img src="/icons/help.png" style="width: 15px; height: 15px; opacity: 0.33; vertical-align: top;"><span class="tooltiptext">Your password is required to make changes to your account configuration.</span></td><td style="color: #444; background-color: transparent; border: 0; font-weight: normal;"><input id="password" type="password" value="" tabindex="5"></td></tr>
                        <tr><td style="color: #444; background-color: transparent; border: 0; font-weight: bold;">Full Name:</td><td style="color: #444; background-color: transparent; border: 0; font-weight: normal;"><input id="fullname" type="text" value="<?php print $userinfo["FULLNAME"]; ?>" maxlength="32" tabindex="2"></td><td style="color: #444; background-color: transparent; border: 0; font-weight: bold;">New Password: <div class="tooltip"><img src="/icons/help.png" style="width: 15px; height: 15px; opacity: 0.33; vertical-align: top;"><span class="tooltiptext">Your new password must match the confirmation password, and passwords must be a minimum of <?php print $userinfo["MINPASS"]; ?> characters long.</td><td style="color: #444; background-color: transparent; border: 0; font-weight: normal;"><input id="newpassword" type="password" tabindex="6"></td></tr>
                        <tr><td style="color: #444; background-color: transparent; border: 0; font-weight: bold;">Email:</td><td style="color: #444; background-color: transparent; border: 0; font-weight: normal;"><input id="email" type="text" value="<?php print $userinfo["EMAIL"]; ?>" maxlength="256" tabindex="3"></td><td style="color: #444; background-color: transparent; border: 0; font-weight: bold;">Confirm New Password:</td><td style="color: #444; background-color: transparent; border: 0; font-weight: normal;"><input id="confirmnewpass" type="password" tabindex="7"></td></tr>
                        <tr><td style="color: #444; background-color: transparent; border: 0; font-weight: bold;">Cell Phone:</td><td style="color: #444; background-color: transparent; border: 0; font-weight: normal;"><input id="phone" type="text" value="<?php print $userinfo["PHONE"]; ?>" maxlength="21" tabindex="4"></td>
			<?php
				if ($userinfo["SYS2FA"] == "Disabled") {
					print "<td style=\"color: #444; background-color: transparent; border: 0; font-weight: bold;\"></td><td style=\"color: #444; background-color: transparent; border: 0; font-weight: normal;\">\n";
					}
				else {
					print "<td style=\"color: #444; background-color: transparent; border: 0; font-weight: bold;\">Two-Factor Authentication: <div class=\"tooltip\"><img src=\"/icons/help.png\" style=\"width: 15px; height: 15px; opacity: 0.33; vertical-align: top;\"><span class=\"tooltiptext\">Enabling 2FA requires your account to be enrolled in at least one authentication method. Selecting one or more methods will begin the enrollment process once you've entered your password and saved changes to your account.<br><br>NOTE: Deselecting a method and saving changes will revoke your enrollment for that method.<br><br>NOTE: Disabling 2FA and saving changes while enrolled in any authentication methods will retain those enrollments.</span></td><td style=\"color: #444; background-color: transparent; border: 0; font-weight: normal; vertical-align: top;\" rowspan=\"4\">\n";
					if ($tfua == "False") {
						print "<select id=\"2FA\" style=\"height: 28px; width: 200px; margin-top: 3px; margin-left: 3px;\" tabindex=\"8\" onchange=\"tfdisablereset(); formCheck();\"><option value=\"enabled\">Enabled</option><option value=\"disabled\" selected=\"selected\">Disabled</option></select><br>\n";
						print "<div style=\"margin-top: 15px;\">";
						if ($tfapp == "True") { print "<input type=\"checkbox\" onclick=\"tfmcheck();\"> <span id=\"applabel\" style=\"style=\"color: #444; cursor: pointer; user-select: none;\" onclick=\"appToggle();\">Authenticator</span><br>\n"; }
						else { print "<input id=\"app2fa\" type=\"checkbox\" disabled=\"disabled\"> <span id=\"applabel\" style=\"color: #777; cursor: normal; user-select: none;\" onclick=\"appToggle();\">Authenticator</span><br>\n"; }
						if ($tfsms == "True") { print "<input type=\"checkbox\"> <span id=\"smslabel\" style=\"style=\"color: #444; cursor: pointer; user-select: none;\" onclick=\"smsToggle();\">SMS Text Message</span><br>\n"; }
						else { print "<input id=\"sms2fa\" type=\"checkbox\" disabled=\"disabled\"> <span id=\"smslabel\" style=\"color: #777; cursor: normal; user-select: none;\" onclick=\"smsToggle();\">SMS Text Message</span><br>\n"; }
						if ($tfeml == "True") { print "<input type=\"checkbox\"> <span id=\"emllabel\" style=\"style=\"color: #444; cursor: pointer; user-select: none;\" onclick=\"emlToggle();\">Email Message</span><br>\n"; }
						else { print "<input id=\"eml2fa\" type=\"checkbox\" disabled=\"disabled\"> <span id=\"emllabel\" style=\"color: #777; cursor: normal; user-select: none;\" onclick=\"emlToggle();\">Email Message</span><br>\n"; }

						print "</div><br>\n";
						}
					else {
						print "<select id=\"2FA\" style=\"height: 28px; width: 200px; margin-top: 3px; margin-left: 3px;\" tabindex=\"8\"><option value=\"enabled\" selected=\"selected\">Enabled</option><option value=\"disabled\">Disabled</option></select>\n";
						}
					}
			?>
			</td></tr>
                        <tr><td style="color: #444; background-color: transparent; border: 0; font-weight: bold; padding-top: 15px;">Role:</td><td style="color: #444; background-color: transparent; border: 0; font-weight: normal; padding-top: 15px;"> <?php print $userrole; ?></td>
			<?php
//				if ($userinfo["SYS2FA"] == "Enabled") {
//					print "<td style=\"color: #444; background-color: transparent; border: 0; font-weight: bold; padding-top: 15px;\">Methods:</td>";
//					}
			?>
			</tr>
                        <tr><td style="color: #444; background-color: transparent; border: 0; font-weight: bold; padding-top: 20px;">Account Type:</td><td style="color: #444; background-color: transparent; border: 0; font-weight: normal; padding-top: 18px;"><?php print $userinfo["TYPE"]; ?></td></tr>
                        <tr><td style="color: #444; background-color: transparent; border: 0; font-weight: bold; padding-top: 20px;">Create Date:</td><td style="color: #444; background-color: transparent; border: 0; font-weight: normal; padding-top: 18px;"><?php print $userinfo["REGDATE"]; ?></td></tr>

			</table>
		</div>
	</div>

<script>
window.onload = function() {
	app2fainit = document.getElementById("app2fa").checked;
	sms2fainit = document.getElementById("sms2fa").checked;
	eml2fainit = document.getElementById("eml2fa").checked;

	document.getElementById("app2fa").addEventListener('change', (event) => { tfmcheck(); })
	document.getElementById("sms2fa").addEventListener('change', (event) => { tfmcheck(); })
	document.getElementById("eml2fa").addEventListener('change', (event) => { tfmcheck(); })
	}

function resetForm() {
        setTimeout(function() {
                formCheck();
                document.getElementById('save').disabled = true;
                }, 25);
        return true;
        }

function tfdisablereset() {
	if (document.getElementById("2FA").value == "disabled") {
		document.getElementById("app2fa").checked = app2fainit;
		document.getElementById("sms2fa").checked = sms2fainit;
		document.getElementById("eml2fa").checked = eml2fainit;
		}
	}

function formCheck() {
	if (document.getElementById("2FA").value == "enabled") {
		document.getElementById("app2fa").disabled = false;
		document.getElementById("sms2fa").disabled = false;
		document.getElementById("eml2fa").disabled = false;
		document.getElementById("applabel").style.color = "#444";
		document.getElementById("smslabel").style.color = "#444";
		document.getElementById("emllabel").style.color = "#444";
		}
	else {
		document.getElementById("app2fa").disabled = true;
		document.getElementById("sms2fa").disabled = true;
		document.getElementById("eml2fa").disabled = true;
		document.getElementById("applabel").style.color = "#777";
		document.getElementById("smslabel").style.color = "#777";
		document.getElementById("emllabel").style.color = "#777";
		}

	if (document.getElementById("password").value != "") {
		if (document.getElementById("newpassword") != "") {
			if (document.getElementById("newpassword") == document.getElementById("confirmnewpass")) {
				document.getElementById("save").disabled = false;
				}
			else { document.getElementById("save").disabled = true; }
			}
		}
	tfmcheck();
	}

function tfmcheck() {
	if (document.getElementById("2FA").value == "enabled") {
		if (document.getElementById("app2fa").checked == false && document.getElementById("sms2fa").checked == false && document.getElementById("eml2fa").checked == false) {
			document.getElementById("app2fa").classList.add('checkError');
			document.getElementById("sms2fa").classList.add('checkError');
			document.getElementById("eml2fa").classList.add('checkError');
			}
		else {
			document.getElementById("app2fa").classList.remove('checkError');
			document.getElementById("sms2fa").classList.remove('checkError');
			document.getElementById("eml2fa").classList.remove('checkError');
			}
		}
	else {
		document.getElementById("app2fa").classList.remove('checkError');
		document.getElementById("sms2fa").classList.remove('checkError');
		document.getElementById("eml2fa").classList.remove('checkError');
		}
	}

function appToggle() {
	if (document.getElementById("2FA").value == "enabled") {
		if (document.getElementById("app2fa").checked == false) {
			document.getElementById("app2fa").checked = true;
			document.getElementById("app2fa").classList.remove('checkError');
			document.getElementById("sms2fa").classList.remove('checkError');
			document.getElementById("eml2fa").classList.remove('checkError');
			}
		else {
			document.getElementById("app2fa").checked = false;
			tfmcheck();
			}
		}
	}

function smsToggle() {
	if (document.getElementById("2FA").value == "enabled") {
		if (document.getElementById("sms2fa").checked == false) {
			document.getElementById("sms2fa").checked = true;
			document.getElementById("app2fa").classList.remove('checkError');
			document.getElementById("sms2fa").classList.remove('checkError');
			document.getElementById("eml2fa").classList.remove('checkError');
			}
		else {
			document.getElementById("sms2fa").checked = false;
			tfmcheck();
			}
		}
	}

function emlToggle() {
	if (document.getElementById("2FA").value == "enabled") {
		if (document.getElementById("eml2fa").checked == false) {
			document.getElementById("eml2fa").checked = true;
			document.getElementById("app2fa").classList.remove('checkError');
			document.getElementById("sms2fa").classList.remove('checkError');
			document.getElementById("eml2fa").classList.remove('checkError');
			}
		else {
			document.getElementById("eml2fa").checked = false;
			tfmcheck();
			}
		}
	}

</script>

<?php elseif ($_GET['view'] == "prefs"): ?>
<div class="content">
	<h1>User Preferences</h1>

<?php endif; ?>

</div>

<?php include ("layout/footer.php"); ?>
