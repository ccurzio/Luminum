<?php

if ($acctrole > 1) {
	print "<div class=\"content\">\n";
	print "<h1 style=\"color: red\">Access Denied</h1>\n";
	}
else {
	mysqli_select_db($db, "SYSTEM") or die( "<h5>Fatal Error</h5>\n\n<p>Unable to access database.\n</p>");
	$confquery = mysqli_query($db, "select CKEY,CVAL from CONFIG");
	while($row = mysqli_fetch_assoc($confquery)) {
		if ($row["CKEY"] == "TARGETCONF") { $targetconf = $row["CVAL"]; }
		else if ($row["CKEY"] == "TCONFTHRESHOLD") { $targetconfthreshold = $row["CVAL"]; }
		else if ($row["CKEY"] == "ENDPOINTCOMM") { $endpointcomm = $row["CVAL"]; }
		else if ($row["CKEY"] == "CHECKININT") { $checkinint = $row["CVAL"]; }
		else if ($row["CKEY"] == "MISSINGAFTER") { $missingafter = $row["CVAL"]; }
		else if ($row["CKEY"] == "2FA") { $twofactor = $row["CVAL"]; }
		else if ($row["CKEY"] == "MINPASS") { $minpass = $row["CVAL"]; }
		else if ($row["CKEY"] == "COMPLEXPASS") { $complexpass = $row["CVAL"]; }
		else if ($row["CKEY"] == "PCUPPERLOWER") { $pcul = $row["CVAL"]; }
		else if ($row["CKEY"] == "PCLETNUM") { $pcln = $row["CVAL"]; }
		else if ($row["CKEY"] == "PCSPECIAL") { $pcsc = $row["CVAL"]; }
		else if ($row["CKEY"] == "TIMEOUT") { $logintimeout = $row["CVAL"]; }
		else if ($row["CKEY"] == "TIMEOUTWARN") { $timeoutwarn = $row["CVAL"]; }
		else if ($row["CKEY"] == "SENREVS") { $senrevs = $row["CVAL"]; }
		else if ($row["CKEY"] == "PKGREVS") { $pkgrevs = $row["CVAL"]; }
		}

	mysqli_select_db($db, "CONTENT") or die( "<h5>Fatal Error</h5>\n\n<p>Unable to access database.\n</p>");
	$csquery = mysqli_query($db, "select ID,NAME from SETS where LOCKED = 0");
	$csopts = array();
	while($row = mysqli_fetch_assoc($csquery)) {
		array_push($csopts, "<option value=\"" . $row["ID"] . "\">" . $row["NAME"] . "</option>\n");
		}
?>

<div class="content">
	<h1>Server Configuration Options</h1>

	<form id="scform" action="/system/serveropts.php" method="POST">
	<div style="width: 100%; text-align: right; margin: -50px auto 10px auto;">
		<button id="save" class="formgo" style="margin-right: 0;" disabled="disabled">Save Changes</button>
		<input type="reset" id="reset" value="Reset Values" class="formgo" onclick="return resetForm();">
	</div>

	<div class="module-content" style="padding: 0;">
		<div class="tabbar tabbarback">
			<button type="button" class="tabbaritem tabbutton tablink tabbarsel" style="border-right: 1px solid #07f;" onclick="switchTab(event, 'General')">General</button>
			<button type="button" class="tabbaritem tabbutton tablink" style="border-right: 1px solid #07f;" onclick="switchTab(event, 'Endpoints')">Endpoints</button>
			<button type="button" class="tabbaritem tabbutton tablink" style="border-right: 1px solid #07f;" onclick="switchTab(event, 'Content')">Content</button>
			<button type="button" class="tabbaritem tabbutton tablink" style="border-right: 1px solid #07f;" onclick="switchTab(event, 'Logging')">Logging</button>
			<button type="button" class="tabbaritem tabbutton tablink" style="border-right: 1px solid #07f;" onclick="switchTab(event, 'SMTP')">SMTP</button>
			<button type="button" class="tabbaritem tabbutton tablink" style="border-right: 1px solid #07f;" onclick="switchTab(event, 'Encryption')">Encryption</button>
			<button type="button" class="tabbaritem tabbutton tablink" style="border-right: 1px solid #07f;" onclick="switchTab(event, 'Accounts')">Accounts</button>
		</div>

		<div id="General" class="configtab">
			<table style="width: 50%; border: 0; margin-left: auto; margin-right: auto; margin-top: 15px; margin-bottom: 15px;">
			<tr><td style="color: #444; background-color: transparent; border: 0; font-weight: bold;">Minimum Action Target Confirmation: </td><td style="color: #444; background-color: transparent; border: 0;"><select id="minactconf" style="width: 175px; height: 28px;" onchange="formCheck()">
			<?php if ($targetconf == "Enabled") {
				print "\t\t\t\t<option value=\"enabled\" selected=\"selected\">Enabled</option><option value=\"disabled\">Disabled</option>\n";
				}
			else {
				print "\t\t\t\t<option value=\"enabled\">Enabled</option><option value=\"enabled\">Enabled</option><option value=\"disabled\" selected=\"selected\">Disabled</option>\n";
				}
			?>
			</select>
			<div class="tooltip"><img src="/icons/help.png" style="width: 15px; height: 15px; opacity: 0.33; vertical-align: top;"> <span class="tooltiptext">Specifies the minimum number of targeted clients requiring confirmation for action deployments<br><br>Default: Enabled; 250 Endpoints</span></div></td></tr>
			<tr><td style="color: #444; background-color: transparent; border: 0; font-weight: normal; padding-left: 30px;"><span id="ctlabel">Confirmation Threshold:</span></td><td style="color: #444; background-color: transparent; border: 0; font-weight: normal;"><input id="actconfclients" type="text" style="width: 60px; font-size: 15px; padding: 3px; margin-top: 0;" maxlength="5" value="<?php print $targetconfthreshold; ?>" onchange="formCheck()"> <span id="eplabel">Endpoints</span></td></tr>
			</table>
		</div>

		<div id="Endpoints" class="configtab" style="display: none;">
			<table style="width: 50%; border: 0; margin-left: auto; margin-right: auto; margin-top: 15px; margin-bottom: 15px;">
			<tr><td style="color: #444; background-color: transparent; border: 0; font-weight: bold;">Communication Method: </td><td style="background-color: transparent; border: 0;"><select id="commproto" style="width: 175px; height: 28px;" onchange="formCheck()">
			<?php if ($endpointcomm == "mqtt") {
				print "<option value=\"mqtt\" selected=\"selected\">MQTT</option><option value=\"direct\">Hub &amp; Spoke</option><option value=\"hybrid\">Hybrid</option>\n";
				}
			else if ($endpointcomm == "direct") {
				print "<option value=\"mqtt\">MQTT</option><option value=\"direct\" selected=\"selected\">Hub &amp; Spoke</option><option value=\"hybrid\">Hybrid</option>\n";
				}
			else if ($endpointcomm == "hybrid") {
				print "<option value=\"mqtt\">MQTT</option><option value=\"direct\">Hub &amp; Spoke</option><option value=\"hybrid\" selected=\"selected\">Hybrid</option>\n";
				}
			?>
			</select>
			<div class="tooltip"><img src="/icons/help.png" style="width: 15px; height: 15px; opacity: 0.33; vertical-align: top;"> <span class="tooltiptext">The method of communication used between the server and endpoint clients.<br><br><u>MQTT</u>: Message Queuing Telemetry Transport provides a method by which clients subscribe to feeds on which messages are published<br><br><u>Hub &amp; Spoke</u>: Direct client/server connections (NOT RECOMMENDED FOR LARGE MULTI-NETWORK DEPLOYMENTS)<br><br><u>Hybrid</u>: Uses a combination of both MQTT and Hub &amp; Spoke with the server automatically choosing the best method based on endpoint network positioning<br><br>Default: MQTT</span></div></td></tr>
			<tr><td style="color: #444; background-color: transparent; border: 0; font-weight: bold;">Check-In Interval: </td><td style="color: #444; background-color: transparent; border: 0; font-weight: normal;"><input id="checkinint" type="text" style="width: 25px; font-size: 15px; padding: 3px; margin-top: 0;" maxlength="2" value="<?php print $checkinint; ?>" onchange="formCheck()"> Minutes <div class="tooltip"><img src="/icons/help.png" style="width: 15px; height: 15px; opacity: 0.33; vertical-align: top;"> <span class="tooltiptext">The interval at which clients ping the server with their status and request updates<br><br>Default: 5 Minutes</span></div></td></tr>
			<tr><td style="color: #444; background-color: transparent; border: 0; font-weight: bold;">Mark as Missing After: </td><td style="color: #444; background-color: transparent; border: 0; font-weight: normal;"><input id="checkinint" type="text" style="width: 25px; font-size: 15px; padding: 3px; margin-top: 0;" maxlength="2" value="<?php print $missingafter; ?>" onchange="formCheck()"> Days <div class="tooltip"><img src="/icons/help.png" style="width: 15px; height: 15px; opacity: 0.33; vertical-align: top;"> <span class="tooltiptext">The length of time after which offline endpoints are marked as missing<br><br>Default: 90 Days</span></div></td></tr>
			</table>
		</div>

		<div id="Content" class="configtab" style="display: none;">
			<table style="width: 50%; border: 0; margin-left: auto; margin-right: auto; margin-top: 15px; margin-bottom: 15px;">
			<tr><td style="color: #444; background-color: transparent; border: 0; font-weight: bold;">Default Content Set for new Sensors: </td><td style="background-color: transparent; border: 0;"><select id="sensorset" style="width: 175px; height: 28px;" onchange="formCheck()">
			<?php foreach ($csopts as $value) { print $value; } ?>
			</select> <div class="tooltip"><img src="/icons/help.png" style="width: 15px; height: 15px; opacity: 0.33; vertical-align: top;"> <span class="tooltiptext">The content set to which newly-created sensors will be added by default<br><br>NOTE: Orphaned sensors will also be moved to this content set</span></div></td></tr>
			<tr><td style="color: #444; background-color: transparent; border: 0; font-weight: bold;">Default Content Set for new Packages: </td><td style="background-color: transparent; border: 0;"><select id="packageset" style="width: 175px; height: 28px;" onchange="formCheck()">
			<?php foreach ($csopts as $value) { print $value; } ?>
			</select> <div class="tooltip"><img src="/icons/help.png" style="width: 15px; height: 15px; opacity: 0.33; vertical-align: top;"> <span class="tooltiptext">The content set to which newly-created packages will be added by default<br><br>NOTE: Orphaned packages will also be moved to this content set</span></div></td></tr>
			<tr><td style="color: #444; background-color: transparent; border: 0; font-weight: bold;">Sensor Edit History:</td><td style="background-color: transparent; border: 0;"><select id="sensorhist" style="width: 175px; height: 28px;" onchange="srevcheck();"><option value="Enabled" <?php if ($senrevs > 0) { print "selected=\"selected\""; } ?>>Enabled</option><option value="Disabled" <?php if ($senrevs == 0) { print "selected=\"selected\""; } ?>>Disabled</option></select> <div class="tooltip"><img src="/icons/help.png" style="width: 15px; height: 15px; opacity: 0.33; vertical-align: top;"> <span class="tooltiptext">Enables or disables the ability to retain previous versions of sensors.<br><br>Default: Enabled, 5 Revisions</span></div></td></tr>
			<?php
			if ($senrevs > 0) { print "<tr><td style=\"color: #444; background-color: transparent; border: 0; font-weight: normal; padding-left: 30px;\"><span id=\"shrlabel\" style=\"color: #444;\">Sensor History Retention:</span></td><td style=\"color: #444; background-color: transparent; border: 0; font-weight: normal;\"><input id=\"srevcnt\" type=\"text\" style=\"width: 60px; font-size: 15px; padding: 3px; margin-top: 0;\" maxlength=\"2\" value=\"" . $senrevs . "\" onchange=\"document.getElementById('save').disabled = false;\"> <span id=\"srlabel\" style=\"color: #444;\">Revisions</span></td></tr>\n"; }
			else { print "<tr><td style=\"background-color: transparent; border: 0; font-weight: normal; padding-left: 30px;\"><span id=\"shrlabel\" style=\"color: #777;\">Sensor History Retention:</span></td><td style=\"color: #777; background-color: transparent; border: 0; font-weight: normal;\"><input id=\"srevcnt\" type=\"text\" style=\"width: 60px; font-size: 15px; padding: 3px; margin-top: 0;\" maxlength=\"2\" value=\"5\" onchange=\"document.getElementById('save').disabled = false;\" disabled=\"disabled\"> <span id=\"srlabel\" style=\"color: #777;\">Revisions</span></td></tr>\n"; }
			?>
			<tr><td style="color: #444; background-color: transparent; border: 0; font-weight: bold;">Package Edit History:</td><td style="background-color: transparent; border: 0;"><select id="packagehist" style="width: 175px; height: 28px;" onchange="prevcheck();"><option value="Enabled" <?php if ($pkgrevs > 0) { print "selected=\"selected\""; } ?>>Enabled</option><option value="Disabled" <?php if ($pkgrevs == 0) { print "selected=\"selected\""; } ?>>Disabled</option></select> <div class="tooltip"><img src="/icons/help.png" style="width: 15px; height: 15px; opacity: 0.33; vertical-align: top;"><span class="tooltiptext">Enables or disables the ability to retain previous versions of packages.<br><br>Default: Enabled, 5 Revisions</span></div></td></tr>
			<?php
			if ($pkgrevs > 0) { print "<tr><td style=\"color: #444; background-color: transparent; border: 0; font-weight: normal; padding-left: 30px;\"><span id=\"phrlabel\" style=\"color: #444;\">Package History Retention:</span></td><td style=\"color: #444; background-color: transparent; border: 0; font-weight: normal;\"><input id=\"prevcnt\" type=\"text\" style=\"width: 60px; font-size: 15px; padding: 3px; margin-top: 0;\" maxlength=\"2\" value=\"" . $pkgrevs . "\" onchange=\"document.getElementById('save').disabled = false;\"> <span id=\"prlabel\" style=\"color: #444;\">Revisions</span></td></tr>\n"; }
			else { print "<tr><td style=\"background-color: transparent; border: 0; font-weight: normal; padding-left: 30px;\"><span id=\"phrlabel\" style=\"color: #777;\">Package History Retention:</span></td><td style=\"color: #777; background-color: transparent; border: 0; font-weight: normal;\"><input id=\"prevcnt\" type=\"text\" style=\"width: 60px; font-size: 15px; padding: 3px; margin-top: 0;\" maxlength=\"2\" value=\"5\" onchange=\"document.getElementById('save').disabled = false;\" disabled=\"disabled\"> <span id=\"prlabel\" style=\"color: #777;\">Revisions</span></td></tr>\n"; }
			?>
			</table>
		</div>

		<div id="Logging" class="configtab" style="display: none;">
			<p>Log Settings</p>
		</div>

		<div id="SMTP" class="configtab" style="display: none;">
			<p>SMTP Settings</p>
		</div>

		<div id="Encryption" class="configtab" style="display: none;">
			<p>Encryption Settings</p>
		</div>

		<div id="Accounts" class="configtab" style="display: none;">
			<table style="width: 50%; border: 0; margin-left: auto; margin-right: auto; margin-top: 15px; margin-bottom: 15px;">
			<tr><td style="color: #444; background-color: transparent; border: 0; font-weight: bold;">Two-Factor Authentication: </td><td style="color: #444; background-color: transparent; border: 0; font-weight: normal;"><select id="2fa" style="width: 175px; height: 28px;" onchange="formCheck()">
			<?php if ($twofactor == "Required") {
				print "<option value=\"Required\" selected=\"selected\">Required</option><option value=\"Optional\">Optional</option><option value=\"Disabled\">Disabled</option>"; 
				}
			else if ($twofactor == "Optional") {
				print "<option value=\"Required\">Required</option><option value=\"Optional\" selected=\"selected\">Optional</option><option value=\"Disabled\">Disabled</option>"; 
				}
			else if ($twofactor == "Disabled") {
				print "<option value=\"Required\">Required</option><option value=\"Optional\">Optional</option><option value=\"Disabled\" selected=\"selected\">Disabled</option>";
				}
			?>
			</select> <div class="tooltip"><img src="/icons/help.png" style="width: 15px; height: 15px; opacity: 0.33; vertical-align: top;"> <span class="tooltiptext">Sets the 2FA policy for all user accounts<br><br>Default: Optional</span></td></tr>
			<tr><td style="color: #444; background-color: transparent; border: 0; font-weight: bold;">Minimum Password Length: </td><td style="color: #444; background-color: transparent; border: 0; font-weight: normal;"><input id="passlen" type="text" style="width: 25px; font-size: 15px; padding: 3px; margin-top: 0;" maxlength="2" value="<?php print $minpass; ?>" onchange="formCheck()"> Characters</td></tr>
			<tr><td style="color: #444; background-color: transparent; border: 0; font-weight: bold;">Password Complexity Enforcement: </td><td style="color: #444; background-color: transparent; border: 0; font-weight: normal;"><select id="complexpass" style="width: 175px; height: 28px;" onchange="formCheck()">
			<?php if ($complexpass == "Enabled") {
				print "<option value=\"enabled\" selected=\"selected\">Enabled</option><option value=\"disabled\">Disabled</option>\n\n";
				}
			else if ($complexpass == "Disabled") {
				print "<option value=\"enabled\">Enabled</option><option value=\"disabled\" selected=\"selected\">Disabled</option>\n\n";
				}
			?>
			</select> <div class="tooltip"><img src="/icons/help.png" style="width: 15px; height: 15px; opacity: 0.33; vertical-align: top;"> <span class="tooltiptext">Require user passwords to include specified characters<br><br>Default: Disabled</span></div></td></tr>
			<tr><td style="color: #444; background-color: transparent; border: 0;"></td><td style="color: #444; background-color: transparent; border: 0; font-weight: normal;">
			<?php if ($complexpass == "Disabled") {
				print "<input id=\"pwdcase\" type=\"checkbox\" ";
				if ($pcul == "Enabled") { print "checked=\"checked\" "; }
				print "disabled=\"disabled\"> ";
				print "<span id=\"ullabel\" style=\"color: #777; cursor: normal; user-select: none;\" onclick=\"ulToggle()\">Upper and Lowercase</span><br>\n";
				print "<input id=\"pwdnums\" type=\"checkbox\" ";
				if ($pcln == "Enabled") { print "checked=\"checked\" "; }
				print "disabled=\"disabled\"> ";
				print "<span id=\"lnlabel\" style=\"color: #777; cursor: normal; user-select: none;\" onclick=\"lnToggle()\">Letters and Numbers</span><br>\n";
				print "<input id=\"pwdspec\" type=\"checkbox\" ";
				if ($pcsc == "Enabled") { print "checked=\"checked\" "; }
				print "disabled=\"disabled\"> ";
				print "<span id=\"sclabel\" style=\"color: #777; cursor: normal; user-select: none;\" onclick=\"scToggle()\">Special Characters</span>\n";
				}
			else {
				print "<input id=\"pwdcase\" type=\"checkbox\"> <span id=\"ullabel\" style=\"color: #777; cursor: normal; user-select: none;\" onclick=\"ulToggle()\">Upper and Lowercase</span><br>\n";
				print "<input id=\"pwdnums\" type=\"checkbox\"> <span id=\"lnlabel\" style=\"color: #777; cursor: normal; user-select: none;\" onclick=\"lnToggle()\">Letters and Numbers</span><br>\n";
				print "<input id=\"pwdspec\" type=\"checkbox\"> <span id=\"sclabel\" style=\"color: #777; cursor: normal; user-select: none;\" onclick=\"scToggle()\">Special Characters</span>\n";
				}
			?>
			</td></tr>
			<?php
				$timeoutnum = preg_replace('/[^0-9]/', '', $logintimeout);
				$timeouttype = preg_replace('/[^a-zA-Z]/', '', $logintimeout);
			?>
			<tr><td style="color: #444; background-color: transparent; border: 0; font-weight: bold;">Inactivity Timeout: </td><td style="background-color: transparent; border: 0;"><input id="inactiveint" type="text" style="width: 25px; font-size: 15px; padding: 3px; margin-top: 0;" maxlength="2" <?php print "value=\"$timeoutnum\""; ?> onchange="formCheck()"> <select id="inttype" style="width: 175px; height: 28px;" onchange="formCheck()">
			<?php
				if ($timeouttype == "M") {
					print "<option value=\"min\" selected=\"selected\">Minute(s)</option><option value=\"hour\">Hour(s)</option><option value=\"day\">Day(s)</option>";
					}
				else if ($timeouttype == "H") {
					print "<option value=\"min\">Minute(s)</option><option value=\"hour\" selected=\"selected\">Hour(s)</option><option value=\"day\">Day(s)</option>";
					}
				else if ($timeouttype == "D") {
					print "<option value=\"min\">Minute(s)</option><option value=\"hour\">Hour(s)</option><option value=\"day\" selected=\"selected\">Day(s)</option>";
					}
			?>
			</select> <div class="tooltip"><img src="/icons/help.png" style="width: 15px; height: 15px; opacity: 0.33; vertical-align: top;"> <span class="tooltiptext">The length of time before a user is automatically logged out due to inactivity<br><br>Default: 15 Minutes</span></div></td></tr>
			<tr><td style="color: #444; background-color: transparent; border: 0; font-weight: normal; padding-left: 30px;">2 Minute Warning:</td><td style="color: #444; background-color: transparent; border: 0; font-weight: normal;"><select id="2minwarn" style="width: 175px; height: 28px;" onchange="formCheck()">
			<?php
				if ($timeoutwarn == "Enabled") {
					print "<option value=\"enabled\" selected=\"selected\">Enabled</option><option value=\"disabled\">Disabled</option>";
					}
				else if ($timeoutwarn == "Disabled") {
					print "<option value=\"enabled\">Enabled</option><option value=\"disabled\" selected=\"selected\">Disabled</option>";
					}
			?>
			</select> <div class="tooltip"><img src="/icons/help.png" style="width: 15px; height: 15px; opacity: 0.33; vertical-align: top;"> <span class="tooltiptext">Displays a warning to the user 2 minutes before they are automatically logged out<br><br>Default: Enabled</span></div></td></tr></td></tr>
			</table>
		</div>
	</div>
	</form>
</div>

<script>
function resetForm() {
	setTimeout(function() {
		srevcheck();
		prevcheck();
		document.getElementById('save').disabled = true;
		}, 25);
	return true;
	}

function srevcheck() {
	if (document.getElementById('sensorhist').value == "Enabled") {
		document.getElementById('shrlabel').style.color = "#444";
		document.getElementById('srlabel').style.color = "#444";
		if (document.getElementById('srevcnt').value == "") { document.getElementById('srevcnt').value = 5; }
		document.getElementById('srevcnt').disabled = false;
		}
	else {
		document.getElementById('shrlabel').style.color = "#777";
		document.getElementById('srlabel').style.color = "#777";
		document.getElementById('srevcnt').disabled = true;
		}
	document.getElementById("save").disabled = false;
	}

function prevcheck() {
	if (document.getElementById('packagehist').value == "Enabled") {
		document.getElementById('phrlabel').style.color = "#444";
		document.getElementById('prlabel').style.color = "#444";
		if (document.getElementById('prevcnt').value == "") { document.getElementById('prevcnt').value = 5; }
		document.getElementById('prevcnt').disabled = false;
		}
	else {
		document.getElementById('phrlabel').style.color = "#777";
		document.getElementById('prlabel').style.color = "#777";
		document.getElementById('prevcnt').disabled = true;
		}
	document.getElementById("save").disabled = false;
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

function ulToggle() {
	if (document.getElementById('complexpass').value == "enabled") {
		const checkBox = document.getElementById('pwdcase');
		if (checkBox.checked == false) { checkBox.checked = true; }
		else { checkBox.checked = false; }
		}
	}

function lnToggle() {
	if (document.getElementById('complexpass').value == "enabled") {
		const checkBox = document.getElementById('pwdnums');
		if (checkBox.checked == false) { checkBox.checked = true; }
		else { checkBox.checked = false; }
		}
	}

function scToggle() {
	if (document.getElementById('complexpass').value == "enabled") {
		const checkBox = document.getElementById('pwdspec');
		if (checkBox.checked == false) { checkBox.checked = true; }
		else { checkBox.checked = false; }
		}
	}

function formCheck() {
	if (document.getElementById("complexpass").value == "enabled") {
		document.getElementById("pwdcase").disabled = false;
		document.getElementById("pwdnums").disabled = false;
		document.getElementById("pwdspec").disabled = false;
		document.getElementById("ullabel").style.color = "";
		document.getElementById("lnlabel").style.color = "";
		document.getElementById("sclabel").style.color = "";
		}
	else {
		document.getElementById("pwdcase").disabled = true;
		document.getElementById("pwdnums").disabled = true;
		document.getElementById("pwdspec").disabled = true;
		document.getElementById("ullabel").style.color = "#777";
		document.getElementById("lnlabel").style.color = "#777";
		document.getElementById("sclabel").style.color = "#777";
		}

	if (document.getElementById("minactconf").value == "enabled") {
		document.getElementById("actconfclients").disabled = false;
		document.getElementById("ctlabel").style.color = "";
		document.getElementById("eplabel").style.color = "";
		}
	else {
		document.getElementById("actconfclients").disabled = true;
		document.getElementById("ctlabel").style.color = "#777";
		document.getElementById("eplabel").style.color = "#777";
		}
	document.getElementById("save").disabled = false;
	}
</script>

<?php } ?>
