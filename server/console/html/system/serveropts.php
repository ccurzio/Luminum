<?php

//
// Server Options form POST handler. The form (config.php?view=options)
// posts directly to /system/serveropts.php, so this branch bootstraps the
// session and DB on its own (the config.php include path is GET only),
// validates the payload (system/serveroptsmap.php), writes the values to
// SYSTEM.CONFIG (and the administrator email to AUTH.USERS), and redirects
// back to the page (PRG). Validation failures redirect with
// ?err=<field ids> so the page can highlight the offending fields.
//
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
	require_once __DIR__ . '/../layout/db.php';
	require_once __DIR__ . '/../layout/session.php';
	require_once __DIR__ . '/serveroptsmap.php';
	if (!isset($_SESSION)) { session_start(); }
	$db = luminum_db();
	// Bounce unauthenticated/expired sessions to the login page; a POST is
	// user activity, so a live session's deadline is refreshed.
	luminum_session_gate($db);
	$psid = (isset($_SESSION['SID']) && ctype_alnum($_SESSION['SID'])) ? mysqli_real_escape_string($db, $_SESSION['SID']) : '';
	$urow = null;
	if ($psid !== '') {
		$uq = mysqli_query($db, "select u.ROLE from AUTH.SESSION s join AUTH.USERS u on u.ID = s.ID where s.SID = '$psid' and s.EXPIRES > now() and u.ENABLED = 1");
		$urow = $uq ? $uq->fetch_assoc() : null;
	}
	// The page itself is admin-only (ROLE 1; the GET path checks
	// $acctrole > 1), so the save path enforces the same.
	if ($urow === null || (int)$urow['ROLE'] > 1) {
		header('Location: /config.php?view=options');
		exit;
	}
	$v = luminum_validate_serveropts($_POST);
	if (!$v['ok']) {
		header('Location: /config.php?view=options&err=' . implode(',', $v['err']));
		exit;
	}
	// DB-backed check the pure validator cannot do: the default content sets
	// must exist and be unlocked (the dropdowns list only LOCKED = 0 sets).
	mysqli_select_db($db, "CONTENT") or die( "<h5>Fatal Error</h5>\n\n<p>Unable to access database.\n</p>");
	foreach (['sensorset' => $v['config']['DEFSENSORSET'], 'packageset' => $v['config']['DEFPKGSET']] as $field => $id) {
		$cq = mysqli_query($db, "select ID from SETS where ID = " . (int)$id . " and LOCKED = 0");
		if (!$cq || mysqli_num_rows($cq) === 0) {
			header('Location: /config.php?view=options&err=' . $field);
			exit;
		}
	}
	// All-or-nothing: validate everything first, then write every value in
	// one transaction (CONFIG has no unique key on CKEY, so each row is an
	// explicit read-then-write, as in server/luminum-config.pl).
	$eg = function ($x) use ($db) { return mysqli_real_escape_string($db, $x); };
	mysqli_select_db($db, "SYSTEM") or die( "<h5>Fatal Error</h5>\n\n<p>Unable to access database.\n</p>");
	if (!mysqli_query($db, "start transaction")) {
		header('Location: /config.php?view=options&err=save');
		exit;
	}
	$fail = false;
	foreach ($v['config'] as $ckey => $cval) {
		$k = $eg($ckey);
		$c = $eg($cval);
		$q = mysqli_query($db, "select CVAL from CONFIG where CKEY = '$k'");
		if ($q && mysqli_num_rows($q) > 0) {
			$ok = mysqli_query($db, "update CONFIG set CVAL = '$c' where CKEY = '$k'");
		} else {
			$ok = mysqli_query($db, "insert into CONFIG (CKEY, CVAL) values ('$k','$c')");
		}
		if (!$ok) { $fail = true; break; }
	}
	if (!$fail) {
		$fail = !mysqli_query($db, "update AUTH.USERS set EMAIL = '" . $eg($v['email']) . "' where USERNAME = 'lumadmin'");
	}
	if ($fail) {
		mysqli_query($db, "rollback");
		header('Location: /config.php?view=options&err=save');
		exit;
	}
	mysqli_query($db, "commit");
	header('Location: /config.php?view=options&saved=1');
	exit;
}

if ($acctrole > 1) {
	print "<div class=\"content\">\n";
	print "<h1 style=\"color: red\">Access Denied</h1>\n";
	}
else {
	mysqli_select_db($db, "SYSTEM") or die( "<h5>Fatal Error</h5>\n\n<p>Unable to access database.\n</p>");
	$defsensorset = "";
	$defpkgset = "";
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
		else if ($row["CKEY"] == "UTIMEOUT") { $logintimeout = $row["CVAL"]; }
		else if ($row["CKEY"] == "UTIMEOUTWARN") { $timeoutwarn = $row["CVAL"]; }
		else if ($row["CKEY"] == "SENREVS") { $senrevs = $row["CVAL"]; }
		else if ($row["CKEY"] == "PKGREVS") { $pkgrevs = $row["CVAL"]; }
		else if ($row["CKEY"] == "PASSKEYS") { $passkeys = $row["CVAL"]; }
		else if ($row["CKEY"] == "USERLOGGING") { $userlogging = $row["CVAL"]; }
		else if ($row["CKEY"] == "DEFSENSORSET") { $defsensorset = $row["CVAL"]; }
		else if ($row["CKEY"] == "DEFPKGSET") { $defpkgset = $row["CVAL"]; }
		}
	mysqli_select_db($db, "AUTH") or die( "<h5>Fatal Error</h5>\n\n<p>Unable to access database.\n</p>");
	$uquery = mysqli_query($db, "select EMAIL from USERS where USERNAME = 'lumadmin'");
	if ($urow = mysqli_fetch_assoc($uquery)) { $owner = $urow["EMAIL"]; }

	mysqli_select_db($db, "CONTENT") or die( "<h5>Fatal Error</h5>\n\n<p>Unable to access database.\n</p>");
	$csquery = mysqli_query($db, "select ID,NAME from SETS where LOCKED = 0");
	$sensorsetopts = array();
	$packagesetopts = array();
	while($row = mysqli_fetch_assoc($csquery)) {
		$sel = ($row["ID"] == $defsensorset) ? " selected=\"selected\"" : "";
		array_push($sensorsetopts, "<option value=\"" . $row["ID"] . "\"" . $sel . ">" . $row["NAME"] . "</option>\n");
		$sel = ($row["ID"] == $defpkgset) ? " selected=\"selected\"" : "";
		array_push($packagesetopts, "<option value=\"" . $row["ID"] . "\"" . $sel . ">" . $row["NAME"] . "</option>\n");
		}
?>

<div class="content">
	<h1>Server Configuration Options</h1>

	<form id="scform" action="/system/serveropts.php" method="POST">
	<div style="width: 84%; text-align: right; margin: -50px auto 10px auto;">
		<input type="reset" id="reset" style="margin-right: 0;" value="Reset Values" class="formgo" onclick="return resetForm();">
		<button id="save" class="formgo" disabled="disabled">Save Changes</button>
	</div>

	<?php if (isset($_GET['saved']) && $_GET['saved'] == '1') {
		print "<div style=\"width: 80%; margin: 0 auto 10px auto; padding: 8px 12px; background-color: #e6f4e6; border: 1px solid #4a4; color: #262; font-size: 14px;\">Configuration saved.</div>\n";
	}
	elseif (isset($_GET['err'])) {
		$errfields = preg_replace('/[^a-z0-9,]/', '', $_GET['err']);
		if ($errfields === 'save') {
			print "<div style=\"width: 80%; margin: 0 auto 10px auto; padding: 8px 12px; background-color: #f4e6e6; border: 1px solid #a44; color: #622; font-size: 14px;\">The configuration could not be saved. Please try again.</div>\n";
		}
		elseif ($errfields !== '') {
			print "<div style=\"width: 80%; margin: 0 auto 10px auto; padding: 8px 12px; background-color: #f4e6e6; border: 1px solid #a44; color: #622; font-size: 14px;\">One or more values are invalid and could not be saved. Check the highlighted fields.</div>\n";
		}
	}
	?>

	<div class="module-content" style="padding: 0; width: 80%; margin-left: auto; margin-right: auto;">
		<div class="tabbar tabbarback">
			<button type="button" class="tabbaritem tabbutton tablink tabbarsel" style="border-right: 1px solid #07f;" onclick="switchTab(event, 'General')">General</button>
			<button type="button" class="tabbaritem tabbutton tablink" style="border-right: 1px solid #07f;" onclick="switchTab(event, 'Accounts')">Accounts</button>
			<button type="button" class="tabbaritem tabbutton tablink" style="border-right: 1px solid #07f;" onclick="switchTab(event, 'Servers')">Servers</button>
			<button type="button" class="tabbaritem tabbutton tablink" style="border-right: 1px solid #07f;" onclick="switchTab(event, 'Endpoints')">Endpoints</button>
			<button type="button" class="tabbaritem tabbutton tablink" style="border-right: 1px solid #07f;" onclick="switchTab(event, 'Content')">Content</button>
			<button type="button" class="tabbaritem tabbutton tablink" style="border-right: 1px solid #07f;" onclick="switchTab(event, 'Logging')">Logging</button>
			<button type="button" class="tabbaritem tabbutton tablink" style="border-right: 1px solid #07f;" onclick="switchTab(event, 'SMTP')">SMTP</button>
			<button type="button" class="tabbaritem tabbutton tablink" style="border-right: 1px solid #07f;" onclick="switchTab(event, 'API')">API</button>
			<button type="button" class="tabbaritem tabbutton tablink" style="border-right: 1px solid #07f;" onclick="switchTab(event, 'Export')">Export</button>
		</div>

		<div id="General" class="configtab">
			<table style="width: 50%; border: 0; margin-left: auto; margin-right: auto; margin-top: 15px; margin-bottom: 15px;">
			<tr><td style="color: #444; background-color: transparent; border: 0; font-weight: bold;">Administrator Email Address: <div class="tooltip"><img src="/icons/tooltip.png" style="width: 15px; height: 15px; opacity: 0.33; vertical-align: top;"><span class="tooltiptext">Email address provided to users to contact with questions or issues regarding this Luminum system.</span></td><td style="color: #444; background-color: transparent; border: 0; font-weight: normal;"><input id="adminemail" name="adminemail" type="text" style="width: 200px; font-size: 15px; padding: 3px; margin-top: 0;" maxlength="128" onchange="formCheck();" value="<?php print htmlspecialchars($owner, ENT_QUOTES, 'UTF-8'); ?>"></td></tr>
			<tr><td style="color: #444; background-color: transparent; border: 0; font-weight: bold;">Minimum Action Target Confirmation: 			<div class="tooltip"><img src="/icons/tooltip.png" style="width: 15px; height: 15px; opacity: 0.33; vertical-align: top;"> <span class="tooltiptext">Specifies the minimum number of targeted endpoints requiring confirmation for action deployments<br><br>Default: Enabled; 250 Endpoints</span></div></td><td style="color: #444; background-color: transparent; border: 0;"><select id="minactconf" name="minactconf" style="width: 175px; height: 28px;" onchange="formCheck();">
			<?php if ($targetconf == "Enabled") {
				print "\t\t\t\t<option value=\"enabled\" selected=\"selected\">Enabled</option><option value=\"disabled\">Disabled</option>\n";
				}
			else {
				print "\t\t\t\t<option value=\"enabled\">Enabled</option><option value=\"disabled\" selected=\"selected\">Disabled</option>\n";
				}
			?>
			</select></td></tr>
			<tr><td style="color: #444; background-color: transparent; border: 0; font-weight: normal; padding-left: 30px;"><span id="ctlabel">Confirmation Threshold:</span></td><td style="color: #444; background-color: transparent; border: 0; font-weight: normal;"><input id="actconfclients" name="actconfclients" type="text" style="width: 60px; font-size: 15px; padding: 3px; margin-top: 0;" maxlength="5" value="<?php print $targetconfthreshold; ?>" onchange="formCheck();"> <span id="eplabel">Endpoints</span></td></tr>
			</table>
		</div>

		<div id="Servers" class="configtab" style="display: none;">
			<p></p>
		</div>

		<div id="Endpoints" class="configtab" style="display: none;">
			<table style="width: 50%; border: 0; margin-left: auto; margin-right: auto; margin-top: 15px; margin-bottom: 15px;">
			<tr><td style="color: #444; background-color: transparent; border: 0; font-weight: bold;">Communication Method: 			<div class="tooltip"><img src="/icons/tooltip.png" style="width: 15px; height: 15px; opacity: 0.33; vertical-align: top;"> <span class="tooltiptext">The method of communication used between the server and endpoint clients.<br><br><u>MQTT</u>: Message Queuing Telemetry Transport provides a method by which clients subscribe to feeds on which messages are published<br><br><u>Hub &amp; Spoke</u>: Direct client&lt;-&gt;server connections<br><br><u>Hybrid</u>: Uses a combination of both MQTT and Hub &amp; Spoke with the server and endpoints automatically choosing the best method based on endpoint network positioning<br><br>Default: MQTT</span></div></td><td style="background-color: transparent; border: 0;"><select id="commproto" name="commproto" style="width: 175px; height: 28px;" onchange="formCheck();">
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
			</td></tr>
			<tr><td style="color: #444; background-color: transparent; border: 0; font-weight: bold;">Check-In Interval: <div class="tooltip"><img src="/icons/tooltip.png" style="width: 15px; height: 15px; opacity: 0.33; vertical-align: top;"> <span class="tooltiptext">The interval at which clients ping the server with their status and request updates<br><br>Default: 5 Minutes</span></div></td><td style="color: #444; background-color: transparent; border: 0; font-weight: normal;"><input id="checkinint" name="checkinint" type="text" style="width: 25px; font-size: 15px; padding: 3px; margin-top: 0;" maxlength="2" value="<?php print $checkinint; ?>" onchange="formCheck();"> Minutes</td></tr>
			<tr><td style="color: #444; background-color: transparent; border: 0; font-weight: bold;">Mark as Missing After: <div class="tooltip"><img src="/icons/tooltip.png" style="width: 15px; height: 15px; opacity: 0.33; vertical-align: top;"> <span class="tooltiptext">The length of time after which offline endpoints are marked as missing<br><br>Default: 90 Days</span></div></td><td style="color: #444; background-color: transparent; border: 0; font-weight: normal;"><input id="missingafter" name="missingafter" type="text" style="width: 25px; font-size: 15px; padding: 3px; margin-top: 0;" maxlength="2" value="<?php print $missingafter; ?>" onchange="formCheck();"> Days</td></tr>
			</table>
		</div>

		<div id="Content" class="configtab" style="display: none;">
			<table style="width: 50%; border: 0; margin-left: auto; margin-right: auto; margin-top: 15px; margin-bottom: 15px;">
			<tr><td style="color: #444; background-color: transparent; border: 0; font-weight: bold;">Default Content Set for new Sensors: <div class="tooltip"><img src="/icons/tooltip.png" style="width: 15px; height: 15px; opacity: 0.33; vertical-align: top;"> <span class="tooltiptext">The content set to which newly-created sensors will be added by default<br><br>NOTE: Orphaned sensors will also be moved to this content set</span></div></td><td style="background-color: transparent; border: 0;"><select id="sensorset" name="sensorset" style="width: 175px; height: 28px;" onchange="formCheck();">
			<?php foreach ($sensorsetopts as $value) { print $value; } ?>
			</select>
			</td></tr>
			<tr><td style="color: #444; background-color: transparent; border: 0; font-weight: bold;">Default Content Set for new Packages: <div class="tooltip"><img src="/icons/tooltip.png" style="width: 15px; height: 15px; opacity: 0.33; vertical-align: top;"> <span class="tooltiptext">The content set to which newly-created packages will be added by default<br><br>NOTE: Orphaned packages will also be moved to this content set</span></div></td><td style="background-color: transparent; border: 0;"><select id="packageset" name="packageset" style="width: 175px; height: 28px;" onchange="formCheck();">
			<?php foreach ($packagesetopts as $value) { print $value; } ?>
			</select>
			</td></tr>
			<tr><td style="color: #444; background-color: transparent; border: 0; font-weight: bold;">Sensor Edit History: <div class="tooltip"><img src="/icons/tooltip.png" style="width: 15px; height: 15px; opacity: 0.33; vertical-align: top;"> <span class="tooltiptext">Enables or disables the ability to retain previous versions of sensors.<br><br>Default: Enabled; 5 Revisions</span></div></td><td style="background-color: transparent; border: 0;"><select id="sensorhist" name="sensorhist" style="width: 175px; height: 28px;" onchange="srevCheck();"><option value="Enabled" <?php if ($senrevs > 0) { print "selected=\"selected\""; } ?>>Enabled</option><option value="Disabled" <?php if ($senrevs == 0) { print "selected=\"selected\""; } ?>>Disabled</option></select></td></tr>
			<?php
			if ($senrevs > 0) { print "<tr><td style=\"color: #444; background-color: transparent; border: 0; font-weight: normal; padding-left: 30px;\"><span id=\"shrlabel\" style=\"color: #444;\">Sensor History Retention:</span></td><td style=\"color: #444; background-color: transparent; border: 0; font-weight: normal;\"><input id=\"srevcnt\" name=\"srevcnt\" type=\"text\" style=\"width: 60px; font-size: 15px; padding: 3px; margin-top: 0;\" maxlength=\"2\" value=\"" . $senrevs . "\" onchange=\"formCheck();\"> <span id=\"srlabel\" style=\"color: #444;\">Revisions</span></td></tr>\n"; }
			else { print "<tr><td style=\"background-color: transparent; border: 0; font-weight: normal; padding-left: 30px;\"><span id=\"shrlabel\" style=\"color: #777;\">Sensor History Retention:</span></td><td style=\"color: #777; background-color: transparent; border: 0; font-weight: normal;\"><input id=\"srevcnt\" name=\"srevcnt\" type=\"text\" style=\"width: 60px; font-size: 15px; padding: 3px; margin-top: 0;\" maxlength=\"2\" value=\"5\" onchange=\"document.getElementById('save').disabled = false;\" disabled=\"disabled\"> <span id=\"srlabel\" style=\"color: #777;\">Revisions</span></td></tr>\n"; }
			?>
			<tr><td style="color: #444; background-color: transparent; border: 0; font-weight: bold;">Package Edit History: <div class="tooltip"><img src="/icons/tooltip.png" style="width: 15px; height: 15px; opacity: 0.33; vertical-align: top;"><span class="tooltiptext">Enables or disables the ability to retain previous versions of packages.<br><br>Default: Enabled; 5 Revisions</span></div></td><td style="background-color: transparent; border: 0;"><select id="packagehist" name="packagehist" style="width: 175px; height: 28px;" onchange="prevCheck();"><option value="Enabled" <?php if ($pkgrevs > 0) { print "selected=\"selected\""; } ?>>Enabled</option><option value="Disabled" <?php if ($pkgrevs == 0) { print "selected=\"selected\""; } ?>>Disabled</option></select></td></tr>
			<?php
			if ($pkgrevs > 0) { print "<tr><td style=\"color: #444; background-color: transparent; border: 0; font-weight: normal; padding-left: 30px;\"><span id=\"phrlabel\" style=\"color: #444;\">Package History Retention:</span></td><td style=\"color: #444; background-color: transparent; border: 0; font-weight: normal;\"><input id=\"prevcnt\" name=\"prevcnt\" type=\"text\" style=\"width: 60px; font-size: 15px; padding: 3px; margin-top: 0;\" maxlength=\"2\" value=\"" . $pkgrevs . "\" onchange=\"formCheck();\"> <span id=\"prlabel\" style=\"color: #444;\">Revisions</span></td></tr>\n"; }
			else { print "<tr><td style=\"background-color: transparent; border: 0; font-weight: normal; padding-left: 30px;\"><span id=\"phrlabel\" style=\"color: #777;\">Package History Retention:</span></td><td style=\"color: #777; background-color: transparent; border: 0; font-weight: normal;\"><input id=\"prevcnt\" name=\"prevcnt\" type=\"text\" style=\"width: 60px; font-size: 15px; padding: 3px; margin-top: 0;\" maxlength=\"2\" value=\"5\" onchange=\"document.getElementById('save').disabled = false;\" disabled=\"disabled\"> <span id=\"prlabel\" style=\"color: #777;\">Revisions</span></td></tr>\n"; }
			?>
			</table>
		</div>

		<div id="Logging" class="configtab" style="display: none;">
			<p>Log Settings</p>
		</div>

		<div id="SMTP" class="configtab" style="display: none;">
			<p>SMTP Settings</p>
		</div>

		<div id="Accounts" class="configtab" style="display: none;">
			<table style="width: 50%; border: 0; margin-left: auto; margin-right: auto; margin-top: 15px; margin-bottom: 15px;">
			<tr><td style="color: #444; background-color: transparent; border: 0; font-weight: bold;">Minimum Password Length: </td><td style="color: #444; background-color: transparent; border: 0; font-weight: normal;"><input id="passlen" name="passlen" type="text" style="width: 25px; font-size: 15px; padding: 3px; margin-top: 0;" maxlength="2" value="<?php print $minpass; ?>" onchange="formCheck();"> Characters</td></tr>
			<tr><td style="color: #444; background-color: transparent; border: 0; font-weight: bold;">Password Complexity Enforcement: <div class="tooltip"><img src="/icons/tooltip.png" style="width: 15px; height: 15px; opacity: 0.33; vertical-align: top;"> <span class="tooltiptext">Require user passwords to include specified characters<br><br>Default: Disabled</span></div></td><td style="color: #444; background-color: transparent; border: 0; font-weight: normal;"><select id="complexpass" name="complexpass" style="width: 175px; height: 28px;" onchange="formCheck();">
			<?php if ($complexpass == "Enabled") {
				print "<option value=\"enabled\" selected=\"selected\">Enabled</option><option value=\"disabled\">Disabled</option>\n\n";
				}
			else if ($complexpass == "Disabled") {
				print "<option value=\"enabled\">Enabled</option><option value=\"disabled\" selected=\"selected\">Disabled</option>\n\n";
				}
			?>
			</select>
			</td></tr>
			<tr><td style="color: #444; background-color: transparent; border: 0;"></td><td style="color: #444; background-color: transparent; border: 0; font-weight: normal;">
			<?php if ($complexpass == "Disabled") {
				print "<input id=\"pwdcase\" name=\"pwdcase\" type=\"checkbox\" ";
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
				print "<input id=\"pwdcase\" name=\"pwdcase\" type=\"checkbox\"";
				if ($pcul == "Enabled") { print " checked=\"checked\""; }
				print "> <span id=\"ullabel\" style=\"color: #777; cursor: normal; user-select: none;\" onclick=\"ulToggle()\">Upper and Lowercase</span><br>\n";
				print "<input id=\"pwdnums\" name=\"pwdnums\" type=\"checkbox\"";
				if ($pcln == "Enabled") { print " checked=\"checked\""; }
				print "> <span id=\"lnlabel\" style=\"color: #777; cursor: normal; user-select: none;\" onclick=\"lnToggle()\">Letters and Numbers</span><br>\n";
				print "<input id=\"pwdspec\" name=\"pwdspec\" type=\"checkbox\"";
				if ($pcsc == "Enabled") { print " checked=\"checked\""; }
				print "> <span id=\"sclabel\" style=\"color: #777; cursor: normal; user-select: none;\" onclick=\"scToggle()\">Special Characters</span>\n";
				}
			?>
			</td></tr>
			<tr><td style="color: #444; background-color: transparent; border: 0; font-weight: bold;">PassKey Support: <div class="tooltip"><img src="/icons/tooltip.png" style="width: 15px; height: 15px; opacity: 0.33; vertical-align: top;"> <span class="tooltiptext">Allow users to log into the system using PassKeys<br><br>Default: Disabled</span></td><td style="color: #444; background-color: transparent; border: 0; font-weight: normal;"><select id="passkeys" name="passkeys" style="width: 175px; height: 28px;" onchange="formCheck()">
			<?php if ($passkeys == "Disabled") {
				print "<option value=\"Enabled\">Enabled</option><option value=\"Disabled\" selected=\"selected\">Disabled</option>\n";
				}
			else {
				print "<option value=\"Enabled\" selected=\"selected\">Enabled</option><option value=\"Disabled\">Disabled</option>\n";
				}
			?>
			</select>
			</td></tr>
			<tr><td style="color: #444; background-color: transparent; border: 0; font-weight: bold;">Two-Factor Authentication: <div class="tooltip"><img src="/icons/tooltip.png" style="width: 15px; height: 15px; opacity: 0.33; vertical-align: top;"> <span class="tooltiptext">Sets the 2FA policy for all user accounts<br><br>Default: Optional</span></td><td style="color: #444; background-color: transparent; border: 0; font-weight: normal;"><select id="2fa" name="2fa" style="width: 175px; height: 28px;" onchange="formCheck()">
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
			</select>
			</td></tr>
			<?php
				$timeoutnum = preg_replace('/[^0-9]/', '', $logintimeout);
				$timeouttype = preg_replace('/[^a-zA-Z]/', '', $logintimeout);
			?>
			<tr><td style="color: #444; background-color: transparent; border: 0; font-weight: bold;">Inactivity Timeout: <div class="tooltip"><img src="/icons/tooltip.png" style="width: 15px; height: 15px; opacity: 0.33; vertical-align: top;"> <span class="tooltiptext">The length of time before a user is automatically logged out due to inactivity<br><br>Default: 15 Minutes</span></div></td><td style="background-color: transparent; border: 0;"><input id="inactiveint" name="inactiveint" type="text" style="width: 25px; font-size: 15px; padding: 3px; margin-top: 0;" maxlength="2" <?php print "value=\"$timeoutnum\""; ?> onchange="formCheck();"> <select id="inttype" name="inttype" style="width: 175px; height: 28px;" onchange="formCheck()">
			<?php
				if ($timeouttype == "M") {
					print "<option value=\"min\" selected=\"selected\">Minute(s)</option><option value=\"hour\">Hour(s)</option>";
					}
				else if ($timeouttype == "H") {
					print "<option value=\"min\">Minute(s)</option><option value=\"hour\" selected=\"selected\">Hour(s)</option>";
					}
			?>
			</select>
			</td></tr>
			<tr><td style="color: #444; background-color: transparent; border: 0; font-weight: normal; padding-left: 30px;">2 Minute Warning: <div class="tooltip"><img src="/icons/tooltip.png" style="width: 15px; height: 15px; opacity: 0.33; vertical-align: top;"> <span class="tooltiptext">Displays a warning to the user 2 minutes before they are automatically logged out<br><br>Default: Enabled</span></div></td><td style="color: #444; background-color: transparent; border: 0; font-weight: normal;"><select id="2minwarn" name="2minwarn" style="width: 175px; height: 28px;" onchange="formCheck()">
			<?php
				if ($timeoutwarn == "Enabled") {
					print "<option value=\"enabled\" selected=\"selected\">Enabled</option><option value=\"disabled\">Disabled</option>";
					}
				else if ($timeoutwarn == "Disabled") {
					print "<option value=\"enabled\">Enabled</option><option value=\"disabled\" selected=\"selected\">Disabled</option>";
					}
			?>
			</select>
			</td></tr>
			</table>
		</div>
		<div id="API" class="configtab" style="display: none;">
			<p>API Settings</p>
		</div>
		<div id="Export" class="configtab" style="display: none;">
			<p>Configuration Export Settings</p>
		</div>
	</div>
	</form>
</div>

<script>
<?php if (isset($_GET['err'])) {
	// Highlight the fields the save rejected (the value is sanitized to
	// field ids on the way in, so it is safe to embed in the array).
	$errfields = preg_replace('/[^a-z0-9,]/', '', $_GET['err']);
	if ($errfields !== '' && $errfields !== 'save') {
		print "['" . str_replace(',', "', '", $errfields) . "'].forEach(function(id) { var el = document.getElementById(id); if (el) { el.classList.add('textError'); } });\n";
	}
} ?>
const mtElement = document.getElementById('actconfclients');
const ciElement = document.getElementById('checkinint');
const maElement = document.getElementById('missingafter');
const srElement = document.getElementById('srevcnt');
const prElement = document.getElementById('prevcnt');
const mpElement = document.getElementById('passlen');
const iaElement = document.getElementById('inactiveint');
const owElement = document.getElementById('adminemail');

mtElement.addEventListener('input', function(event) {
	document.getElementById('actconfclients').value = numbersOnly(document.getElementById('actconfclients').value);
	formCheck();
	});

ciElement.addEventListener('input', function(event) {
	document.getElementById('checkinint').value = numbersOnly(document.getElementById('checkinint').value);
	formCheck();
	});

maElement.addEventListener('input', function(event) {
	document.getElementById('missingafter').value = numbersOnly(document.getElementById('missingafter').value);
	formCheck();
	});

srElement.addEventListener('input', function(event) {
	document.getElementById('srevcnt').value = numbersOnly(document.getElementById('srevcnt').value);
	formCheck();
	});

prElement.addEventListener('input', function(event) {
	document.getElementById('prevcnt').value = numbersOnly(document.getElementById('prevcnt').value);
	formCheck();
	});

mpElement.addEventListener('input', function(event) {
	document.getElementById('passlen').value = numbersOnly(document.getElementById('passlen').value);
	formCheck();
	});

iaElement.addEventListener('input', function(event) {
	document.getElementById('inactiveint').value = numbersOnly(document.getElementById('inactiveint').value);
	formCheck();
	});

owElement.addEventListener('input', function(event) { formCheck(); });

function numbersOnly(str) { return str.replace(/[^0-9]/g, ''); }

// Must match the backend's validator (system/serveroptsmap.php): the safe
// unquoted-atom character set, so the client rejects what the server would.
function isValidEmail(email) {
	const emailRegex = /^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/;
	return emailRegex.test(email);
	}

function resetForm() {
	setTimeout(function() {
		srevCheck();
		prevCheck();
		formCheck();
		document.getElementById('save').disabled = true;
		}, 25);
	return true;
	}

function srevCheck() {
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
		document.getElementById('srevcnt').classList.remove('textError');
		}
	document.getElementById("save").disabled = false;
	}

function prevCheck() {
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
		document.getElementById('prevcnt').classList.remove('textError');
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

	if (!isValidEmail(document.getElementById("adminemail").value)) {
		document.getElementById("save").disabled = true;
		document.getElementById("adminemail").classList.add('textError');
		}
	else { document.getElementById("adminemail").classList.remove('textError'); }

	if (document.getElementById("minactconf").value == "enabled" && document.getElementById("actconfclients").value == 0) {
		document.getElementById("save").disabled = true;
		document.getElementById('actconfclients').classList.add('textError');
		}
	else { document.getElementById('actconfclients').classList.remove('textError'); }

	if (document.getElementById('checkinint').value == 0 || document.getElementById('checkinint').value == "") {
		document.getElementById("save").disabled = true;
		document.getElementById('checkinint').classList.add('textError');
		}
	else { document.getElementById('checkinint').classList.remove('textError'); }

	if (document.getElementById('missingafter').value == 0 || document.getElementById('missingafter').value == "") {
		document.getElementById("save").disabled = true;
		document.getElementById('missingafter').classList.add('textError');
		}
	else { document.getElementById('missingafter').classList.remove('textError'); }

	if (document.getElementById('sensorhist').value == "Enabled" && (document.getElementById('srevcnt').value == 0 || document.getElementById('srevcnt').value == "")) {
		document.getElementById("save").disabled = true;
		document.getElementById('srevcnt').classList.add('textError');
		}
	else { document.getElementById('srevcnt').classList.remove('textError'); }

	if (document.getElementById('packagehist').value == "Enabled" && (document.getElementById('prevcnt').value == 0 || document.getElementById('prevcnt').value == "")) {
		document.getElementById("save").disabled = true;
		document.getElementById('prevcnt').classList.add('textError');
		}
	else { document.getElementById('prevcnt').classList.remove('textError'); }

	if (document.getElementById('passlen').value == 0 || document.getElementById('passlen').value == "" || document.getElementById('passlen').value < 8) {
		document.getElementById("save").disabled = true;
		document.getElementById('passlen').classList.add('textError');
		}
	else { document.getElementById('passlen').classList.remove('textError'); }

	if (document.getElementById('inactiveint').value == 0 || document.getElementById('inactiveint').value == "") {
		document.getElementById("save").disabled = true;
		document.getElementById('inactiveint').classList.add('textError');
		}
	else { document.getElementById('inactiveint').classList.remove('textError'); }
	}
</script>

<?php } ?>
