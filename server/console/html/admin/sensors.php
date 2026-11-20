<?php
require_once __DIR__ . '/sensormap.php';

//
// Sensor create form POST handler. The form (view=sensors&action=new)
// posts directly to /admin/sensors.php, so this branch bootstraps the
// session and DB on its own (the index.php include path is GET only),
// validates the payload (admin/sensormap.php), inserts the sensor into
// CONTENT.SENSORS, and redirects back to the list (PRG). Validation
// failures redirect to the form with ?err=<code>, which shows the error
// in the overlay popup (LuminumOverlay in layout/session.js).
//
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
	require_once __DIR__ . '/../layout/db.php';
	require_once __DIR__ . '/../layout/session.php';
	if (!isset($_SESSION)) { session_start(); }
	$db = luminum_db();
	// Bounce unauthenticated/expired sessions to the login page; a POST is
	// user activity, so a live session's deadline is refreshed.
	luminum_session_gate($db);
	$psid = (isset($_SESSION['SID']) && ctype_alnum($_SESSION['SID'])) ? mysqli_real_escape_string($db, $_SESSION['SID']) : '';
	$urow = null;
	if ($psid !== '') {
		$uq = mysqli_query($db, "select s.ID, u.ROLE from AUTH.SESSION s join AUTH.USERS u on u.ID = s.ID where s.SID = '$psid' and s.EXPIRES > now() and u.ENABLED = 1");
		$urow = $uq ? $uq->fetch_assoc() : null;
	}
	if ($urow === null || (int)$urow['ROLE'] > 2) {
		header('Location: /index.php?view=sensors');
		exit;
	}
	// Edit mode: the form posts a hidden sensorid when it was opened from
	// the list's Modify Selected button. The same validator applies, and
	// failure redirects go back to the edit form for that sensor.
	$editid = (isset($_POST['sensorid']) && is_string($_POST['sensorid']) && preg_match('/^[1-9][0-9]*$/', $_POST['sensorid'])) ? (int)$_POST['sensorid'] : null;
	$back = $editid !== null ? 'edit&id=' . $editid : 'new';
	$v = luminum_validate_sensor_create($_POST);
	if (!$v['ok']) {
		header('Location: /index.php?view=sensors&action=' . $back . '&err=' . $v['err']);
		exit;
	}
	$s = $v['sensor'];
	mysqli_select_db($db, "CONTENT") or die( "<h5>Fatal Error</h5>\n\n<p>Unable to access database.\n</p>");
	$eg = function ($x) use ($db) { return mysqli_real_escape_string($db, $x); };
	if ($editid !== null) {
		$xq = mysqli_query($db, "select ID from SENSORS where ID = $editid");
		if (!$xq || mysqli_num_rows($xq) === 0) {
			header('Location: /index.php?view=sensors');
			exit;
		}
	}
	// DB-backed checks the pure validator cannot do: the content set must
	// exist, the category (when given) must belong to it, and the name must
	// be unique (the utf8mb4 collation makes the comparison case-insensitive;
	// an edit is not a duplicate of its own current name).
	$cq = mysqli_query($db, "select ID from SETS where ID = " . (int)$s['CSET']);
	if (!$cq || mysqli_num_rows($cq) === 0) {
		header('Location: /index.php?view=sensors&action=' . $back . '&err=cset');
		exit;
	}
	if ($s['CATEGORY'] !== null) {
		$qq = mysqli_query($db, "select ID from CATEGORIES where ID = " . (int)$s['CATEGORY'] . " and CSID = " . (int)$s['CSET']);
		if (!$qq || mysqli_num_rows($qq) === 0) {
			header('Location: /index.php?view=sensors&action=' . $back . '&err=category');
			exit;
		}
	}
	$nq = mysqli_query($db, "select ID from SENSORS where NAME = '" . $eg($s['NAME']) . "'" . ($editid !== null ? " and ID != $editid" : ""));
	if ($nq && mysqli_num_rows($nq) > 0) {
		header('Location: /index.php?view=sensors&action=' . $back . '&err=dupname');
		exit;
	}
	if ($editid !== null) {
		$sv = function ($x) use ($eg) { return $x === null ? 'null' : "'" . $eg($x) . "'"; };
		$upd = "update SENSORS set NAME = '" . $eg($s['NAME']) . "',DESCRIPTION = '" . $eg($s['DESCRIPTION']) . "',CSET = " . (int)$s['CSET'] . ",CATEGORY = "
			. ($s['CATEGORY'] === null ? 'null' : (int)$s['CATEGORY']) . ",TIMEOUT = '" . $eg($s['TIMEOUT']) . "',MSTYPE = " . $sv($s['MSTYPE'])
			. ",MSCRIPT = " . $sv($s['MSCRIPT']) . ",LSTYPE = " . $sv($s['LSTYPE']) . ",LSCRIPT = " . $sv($s['LSCRIPT'])
			. ",WSTYPE = " . $sv($s['WSTYPE']) . ",WSCRIPT = " . $sv($s['WSCRIPT']) . ",RTYPE = '" . $eg($s['RTYPE']) . "',USECASE = " . (int)$s['USECASE']
			. ",CSPLIT = " . (int)$s['CSPLIT'] . ",DELIMITER = " . $sv($s['DELIMITER']) . ",WITHPARAMS = " . (int)$s['WITHPARAMS']
			. ",MODIFIED = now(),EDITOR = " . (int)$urow['ID'] . " where ID = $editid";
		if (!mysqli_query($db, $upd)) {
			header('Location: /index.php?view=sensors&action=' . $back . '&err=save');
			exit;
		}
		header('Location: /index.php?view=sensors');
		exit;
	}
	$ins = "insert into SENSORS (NAME,DESCRIPTION,CSET,CATEGORY,TIMEOUT,MSTYPE,MSCRIPT,LSTYPE,LSCRIPT,WSTYPE,WSCRIPT,RTYPE,USECASE,CSPLIT,DELIMITER,WITHPARAMS,AUTHOR,CREATED) values ("
		. "'" . $eg($s['NAME']) . "','" . $eg($s['DESCRIPTION']) . "'," . (int)$s['CSET'] . ","
		. ($s['CATEGORY'] === null ? 'null' : (int)$s['CATEGORY']) . ","
		. "'" . $eg($s['TIMEOUT']) . "',"
		. ($s['MSTYPE'] === null ? 'null' : "'" . $eg($s['MSTYPE']) . "'") . ","
		. ($s['MSCRIPT'] === null ? 'null' : "'" . $eg($s['MSCRIPT']) . "'") . ","
		. ($s['LSTYPE'] === null ? 'null' : "'" . $eg($s['LSTYPE']) . "'") . ","
		. ($s['LSCRIPT'] === null ? 'null' : "'" . $eg($s['LSCRIPT']) . "'") . ","
		. ($s['WSTYPE'] === null ? 'null' : "'" . $eg($s['WSTYPE']) . "'") . ","
		. ($s['WSCRIPT'] === null ? 'null' : "'" . $eg($s['WSCRIPT']) . "'") . ","
		. "'" . $eg($s['RTYPE']) . "'," . (int)$s['USECASE'] . "," . (int)$s['CSPLIT'] . ","
		. ($s['DELIMITER'] === null ? 'null' : "'" . $eg($s['DELIMITER']) . "'") . ","
		. (int)$s['WITHPARAMS'] . "," . (int)$urow['ID'] . ",now())";
	if (!mysqli_query($db, $ins)) {
		header('Location: /index.php?view=sensors&action=new&err=save');
		exit;
	}
	header('Location: /index.php?view=sensors');
	exit;
}

mysqli_select_db($db, "CONTENT") or die( "<h5>Fatal Error</h5>\n\n<p>Unable to access database.\n</p>");

$starttime = microtime(true);
$sensorquery = mysqli_query($db, "select s.ID,s.NAME,s.DESCRIPTION,!ifnull(s.MSCRIPT,1) as MAC,!ifnull(s.LSCRIPT,1) as LIN,!ifnull(s.WSCRIPT,1) as WIN,u.USERNAME as AUTHOR,s.CREATED,s.MODIFIED,s.EDITOR from SENSORS s left join AUTH.USERS u ON s.AUTHOR = u.ID order by NAME;");
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
			print "<button id=\"modify\" class=\"formgo\" style=\"margin-top: 5px; margin-right: 0;\" disabled=\"disabled\">Modify Selected</button>\n";
			print "<button id=\"delete\" class=\"formgo\" style=\"margin-top: 5px; margin-right: 0;\" disabled=\"disabled\">Delete Selected</button>\n";
			}
		print "<button id=\"getinfo\" class=\"formgo\" style=\"margin-top: 5px; margin-right: 0;\" disabled=\"disabled\">Get Info</button>\n";
		print "</div>\n";
		?>
		<table style="margin-top: 10px;">
		<tr><td colspan="8"><div style="position: absolute; padding-top: 7px; padding-left: 5px;"><span id="selcount">0</span> <span id="totcount">of <?php print $sensorcount; ?></span> items</div><div style="float: right; text-align: right; padding-right: 5px;">Content Set: <select id="contentset" name="contentset" style="margin-left: 2px; margin-right: 30px; margin-top: 2px; width: 170px; height: 28px;" <?php if ($sensorcount == 0) { print "disabled=\"disabled\""; } ?>>
			<option value="all">All</option>
			<?php
			while ($csrow = mysqli_fetch_assoc($csets)) {
				print "<option value=\"" . $csrow["ID"] . "\">" . $csrow["NAME"] . "</option>\n";
				}
			?>
		</select> Filter: <input type="text" id="sensorsfilter" style="font-size: 15px; padding: 3px; margin-top: 0;" <?php if ($sensorcount == 0) { print "disabled=\"disabled\""; } ?> maxlength="64"></div></td></tr>
		<tr><td style="width: 15px;">
		<?php
			if ($sensorcount == 0) { print "<input type=\"checkbox\" disabled=\"disabled\">"; }
			else { print "<input id=\"selectall\" type=\"checkbox\" onclick=\"allToggle();\">"; }
		?>
		</td><td style="width: 100px;">Name</td><td style="width: 300px;">Description</td><td style="width: 50px; text-align: center;">Supports</td><td style="width: 50px;">Author</td><td style="width: 100px;">Create Date</td><td style="width: 100px;">Last Modification</td><td style="width: 100px;">Modified By</td></tr>
		<?php
		if ($sensorcount == 0) {
			print "<tr><td colspan=\"8\" style=\"text-align: center; background-color: #494a69; font-weight: normal; font-style: italic;\">No Results</td></tr>\n";
			}
		else {
			while($row = mysqli_fetch_assoc($sensorquery)) {
				$compat = "";
				$modified = ($row["MODIFIED"] !== null && $row["MODIFIED"] !== '') ? $row["MODIFIED"] : "Never";
				if ($row["MAC"] == 1) { $compat .= "<img src=\"/images/macos.png\" alt=\"macOS\" style=\"width: 24px; height: 24px;\">"; }
				if ($row["LIN"] == 1) { $compat .= "<img src=\"/images/linux.png\" alt=\"Linux\" style=\"width: 24px; height: 24px;\">"; }
				if ($row["WIN"] == 1) { $compat .= "<img src=\"/images/windows.png\" alt=\"Windows\" style=\"width: 24px; height: 24px;\">"; }
				print "<tr class=\"luminum-row\"><td id=\"" . $row["ID"] . "A\" style=\"width: 15px; background-color: #494a69;\"><input id=\"ID" . $row["ID"] . "\" class=\"sensorrow\" type=\"checkbox\" onclick=\"rowHighlight(" . $row["ID"] . "); allCheck();\"></td><td id=\"" . $row["ID"] . "B\" style=\"width: 50px; background-color: #494a69; font-weight: normal;\">" . $row["NAME"] . "</td><td id=\"" . $row["ID"] . "C\" style=\"width: 75px; background-color: #494a69; font-weight: normal;\">" . $row["DESCRIPTION"] . "</td><td id=\"" . $row["ID"] . "D\" style=\"background-color: #494a69; font-weight: normal; text-align: center;\">" . $compat . "</td><td id=\"" . $row["ID"] . "E\" style=\"background-color: #494a69; font-weight: normal;\">" . $row["AUTHOR"] . "</td><td id=\"" . $row["ID"] . "F\" style=\"width: 90px; background-color: #494a69; font-weight: normal;\">" . $row["CREATED"] . "</td>" . "<td id=\"" . $row["ID"] . "G\" style=\"width: 90px; background-color: #494a69; font-weight: normal;\">" . $modified . "</td><td id=\"" . $row["ID"] . "H\" style=\"background-color: #494a69; font-weight: normal;\">" . $row["EDITOR"] . "</td></tr>\n";
				}
			}
		?>
		<tr style="height: 35px;"><td colspan="8"><div style="position: absolute; padding-top: 5px;"></div><div style="float: right; text-align: right; padding-bottom: 2px; padding-right: 5px; font-weight: normal;"><i>Query Completed in <?php print $duration; ?> Seconds</i></div></td></tr>
		</table>
	</div>

	<?php elseif ($_GET["action"] == "new" || $_GET["action"] == "edit"): ?>

		<?php
		// Edit mode (the list's Modify Selected button) loads the selected
		// sensor's stored values so the form renders exactly like the create
		// form with the fields pre-filled. A missing/unknown id renders an
		// error in place - the console header is already printed by
		// index.php, so a header() redirect is no longer possible here.
		$sensor = null;
		if ($_GET["action"] == "edit") {
			$sid = (isset($_GET["id"]) && preg_match('/^[1-9][0-9]*$/', $_GET["id"])) ? (int)$_GET["id"] : 0;
			if ($sid !== 0) {
				$sq = mysqli_query($db, "select ID,NAME,DESCRIPTION,CSET,CATEGORY,TIMEOUT,MSTYPE,MSCRIPT,LSTYPE,LSCRIPT,WSTYPE,WSCRIPT,RTYPE,USECASE,CSPLIT,DELIMITER,WITHPARAMS from SENSORS where ID = $sid");
				$sensor = ($sq && mysqli_num_rows($sq) > 0) ? $sq->fetch_assoc() : null;
			}
		}
		$tparts = ($sensor !== null) ? luminum_sensor_timeout_parts($sensor['TIMEOUT']) : null;
		// The sensor's category/set names, for the pre-selected options (the
		// set may be one the form's list does not offer, e.g. "Luminum Core").
		$catname = null;
		if ($sensor !== null && $sensor['CATEGORY'] !== null) {
			$qc = mysqli_query($db, "select NAME from CATEGORIES where ID = " . (int)$sensor['CATEGORY']);
			$cr = $qc ? $qc->fetch_assoc() : null;
			if ($cr !== null) { $catname = $cr['NAME']; }
		}
		$csetname = null;
		if ($sensor !== null) {
			$qs = mysqli_query($db, "select NAME from SETS where ID = " . (int)$sensor['CSET']);
			$sr = $qs ? $qs->fetch_assoc() : null;
			if ($sr !== null) { $csetname = $sr['NAME']; }
		}
		// The stored per-OS type/script pairs for the ace editors (null on
		// the create form); the init block at the bottom of the form loads
		// them into the editors.
		$editdata = null;
		if ($sensor !== null) {
			$editdata = [
				'lstype' => $sensor['LSTYPE'], 'lscript' => $sensor['LSCRIPT'],
				'mstype' => $sensor['MSTYPE'], 'mscript' => $sensor['MSCRIPT'],
				'wstype' => $sensor['WSTYPE'], 'wscript' => $sensor['WSCRIPT'],
				'csplit' => (int)$sensor['CSPLIT'],
			];
		}
		?>
		<?php
		if ($_GET["action"] == "edit" && $sensor === null): ?>
		<h1 style="color: red">Sensor Not Found</h1>

		<?php
		elseif (isset($acctrole) && $acctrole <= 2): ?>
		<h1><?php print $sensor !== null ? 'Edit Sensor' : 'Create New Sensor'; ?></h1>

		<?php if (isset($_GET["err"])): ?>
		<script>
		// layout/session.js (LuminumOverlay) is loaded in the footer, so the
		// error popup is shown once the page has finished loading.
		window.addEventListener('DOMContentLoaded', function () {
			LuminumOverlay.show({
				title: 'Save Error',
				message: <?php print json_encode(luminum_sensor_error_message($_GET["err"]), JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT); ?>,
				buttons: [{ label: 'OK', onclick: function () { LuminumOverlay.hide(); } }]
			});
		});
		</script>
		<?php endif; ?>

		<form id="nsform" action="/admin/sensors.php" method="POST">
		<!-- The ace editors are not form fields; their contents are copied
		     into these hidden inputs by formCheck()/the submit handler. -->
		<input type="hidden" name="sensorid" value="<?php print $sensor !== null ? (int)$sensor['ID'] : ''; ?>">
		<input type="hidden" name="lscript" id="lhscript" value="">
		<input type="hidden" name="mscript" id="mhscript" value="">
		<input type="hidden" name="wscript" id="whscript" value="">
		<div style="width: 100%; text-align: right; margin: -50px auto 10px auto;">
			<a href="/index.php?view=sensors"><button type="button" class="formgo" style="margin-right: 0px;">Cancel</button></a>
			<button id="save" class="formgo" disabled="disabled" style="margin-top: 5px; margin-right: 25px;">Save Sensor</button>
		</div>

		<div class="module-content" style="overflow: auto; min-width: 1000px;">
			<div style="float: left; z-index: 10;">
				<table style="margin-top: 10px; margin-bottom: 20px; border: 0;">
				<tr><td style="background-color: transparent; border: 0; color: #444;">Name: <span style="color: red;">*</span></td><td style="background-color: transparent; border: 0; color: #444;">Timeout: <span style="color: red;">*</span> <div class="tooltip"><img src="/icons/tooltip.png" style="width: 15px; height: 15px; opacity: 0.33; vertical-align: top;"> <span class="tooltiptext">Specifies how long the server should wait for the sensor to provide an answer<br><br>Default: 30 Seconds</span></div></td></tr>
				<tr><td style="background-color: transparent; border: 0; color: #444;"><input type="text" name="pkgname" style="width: 400px;" maxlength="128" value="<?php print $sensor !== null ? htmlspecialchars($sensor['NAME'], ENT_QUOTES) : ''; ?>"></td><td style="background-color: transparent; border: 0; color: #444;"><input id="timeout" name="timeout" type="text" style="width: 30px;" value="<?php print $tparts !== null ? $tparts['num'] : '30'; ?>" maxlength="3"><select id="tint" name="tint" style="width: 100px; margin-left: 10px; height: 33px;"><option value="sec"<?php print ($tparts !== null && $tparts['unit'] === 'sec') ? ' selected="selected"' : ''; ?>>Second(s)</option><option value="min"<?php print ($tparts !== null && $tparts['unit'] === 'min') ? ' selected="selected"' : ''; ?>>Minute(s)</option></select></td></tr>
				<tr><td style="padding-top: 30px; background-color: transparent; border: 0; color: #444;">Description: <span style="color: red;">*</span></td><td style="padding-top: 30px; background-color: transparent; border: 0; color: #444;">Result Type: <div class="tooltip"><img src="/icons/tooltip.png" style="width: 15px; height: 15px; opacity: 0.33; vertical-align: top;"> <span class="tooltiptext">Defines the format of the sensor output<br><br>Default: Text</span></div></td></tr>
				<tr><td style="background-color: transparent; border: 0; color: #444;"><input type="text" name="pkgdesc" style="width: 400px;" maxlength="128" value="<?php print $sensor !== null ? htmlspecialchars($sensor['DESCRIPTION'], ENT_QUOTES) : ''; ?>"></td><td style="background-color: transparent; border: 0; color: #444;"><select id="rtype" name="rtype" style="font-size: 15px; height: 33px; width: 300px; margin-left: 2px; margin-right: 30px;"><option value="text"<?php print ($sensor !== null && $sensor['RTYPE'] === 'text') ? ' selected="selected"' : ''; ?>>Text</option><option value="number"<?php print ($sensor !== null && $sensor['RTYPE'] === 'number') ? ' selected="selected"' : ''; ?>>Number</option><option value="bool"<?php print ($sensor !== null && $sensor['RTYPE'] === 'bool') ? ' selected="selected"' : ''; ?>>Boolean</option><option value="ipaddress"<?php print ($sensor !== null && $sensor['RTYPE'] === 'ipaddress') ? ' selected="selected"' : ''; ?>>IP Address</option><option value="datetime"<?php print ($sensor !== null && $sensor['RTYPE'] === 'datetime') ? ' selected="selected"' : ''; ?>>Date/Time Stamp</option></td></tr>
				<tr><td style="padding-top: 30px; background-color: transparent; border: 0; color: #444;">Content Set: <span style="color: red;">*</span></td><td style="padding-top: 30px; background-color: transparent; border: 0; color: #444;">Category:</td></tr>
				<tr><td style="background-color: transparent; border: 0; color: #444;"><select id="contentset" name="contentset" style="font-size: 15px; height: 33px; width: 430px; margin-left: 2px; margin-right: 30px;">
				<?php
				$csetlisted = false;
				while ($csrow = mysqli_fetch_assoc($csets)) {
					$iscur = ($sensor !== null && (int)$csrow["ID"] === (int)$sensor['CSET']);
					if ($iscur) { $csetlisted = true; }
					print "<option value=\"" . $csrow["ID"] . "\"" . ($iscur ? ' selected="selected"' : '') . ">" . $csrow["NAME"] . "</option>\n";
					}
				if ($sensor !== null && !$csetlisted && $csetname !== null) {
					print "<option value=\"" . (int)$sensor['CSET'] . "\" selected=\"selected\">" . htmlspecialchars($csetname, ENT_QUOTES) . "</option>\n";
					}
				?>
				</select></td><td style="background-color: transparent; border: 0; color: #444;"><select id="category" name="category" style="font-size: 15px; height: 33px; width: 430px; margin-left: 2px; margin-right: 30px;">
				<option value="none">(None)</option>
				<?php
				if ($sensor !== null && $sensor['CATEGORY'] !== null && $catname !== null) {
					print "<option value=\"" . (int)$sensor['CATEGORY'] . "\" selected=\"selected\">" . htmlspecialchars($catname, ENT_QUOTES) . "</option>\n";
					}
				?>
				</select></td></tr>
				<tr><td style="padding-top: 30px; background-color: transparent; border: 0; color: #444; font-weight: normal;" colspan="2"><input type="checkbox" id="case" name="case"<?php print ($sensor !== null && (int)$sensor['USECASE'] === 1) ? ' checked="checked"' : ''; ?>><span style="cursor: normal; user-select: none;" onclick="caseToggle()"> Results are Case Sensitive</span> <div class="tooltip"><img src="/icons/tooltip.png" style="width: 15px; height: 15px; opacity: 0.33; vertical-align: top;"> <span class="tooltiptext">Instructs the server to force case sensitive matching for the sensor output<br><br>Default: Disabled</span></div></td></tr>
				<tr><td style="background-color: transparent; border: 0; color: #444; font-weight: normal;" colspan="2"><input type="checkbox" id="split" name="split" onclick="toggleSplit()"<?php print ($sensor !== null && (int)$sensor['CSPLIT'] === 1) ? ' checked="checked"' : ''; ?>><span style="cursor: normal; user-select: none;" onclick="csToggle()"> Split Results into Columns </span><div class="tooltip"><img src="/icons/tooltip.png" style="width: 15px; height: 15px; opacity: 0.33; vertical-align: top;"> <span class="tooltiptext">Allows the server to split the sensor output and display the split segments in separate columns within a query response<br><br>Default: Disabled</span></div><span class="delform" style="margin-left: 50px; opacity: 0;">Delimeter: </span><span class="delform" style="opacity: 0; color: red;">*</span><input class="delform" id="delimeter" name="delimeter" type="text" style="opacity: 0; margin-left: 15px; width: 5px;" maxlength="1" value="<?php print ($sensor !== null && $sensor['DELIMITER'] !== null) ? htmlspecialchars($sensor['DELIMITER'], ENT_QUOTES) : '|'; ?>"></td></tr>
				</table>

			</div>


		<hr style="width: 99%; margin-bottom: 20px;">

		<table style="border: 0; margin-bottom: 20px;">
		<tr><td style="background-color: transparent; border: 0; color: #444; font-weight: normal;"><input type="checkbox" id="useparams" name="useparams"<?php print ($sensor !== null && (int)$sensor['WITHPARAMS'] === 1) ? ' checked="checked"' : ''; ?>><span style="cursor: normal; user-select: none;" onclick="paramToggle()"> Accepts Query Parameters</span> <div class="tooltip"><img src="/icons/tooltip.png" style="width: 15px; height: 15px; opacity: 0.33; vertical-align: top;"> <span class="tooltiptext">Allows the sensor to accept variables when constructing a query and injects them at user-defined points in the sensor scripts<br><br>Default: Disabled</span></div></td></tr>
		</table>

		<hr style="width: 99%;">

		<div style="float: left; margin-left: 10px;">
			<table style="width: 250px; margin-left: auto; margin-right: auto; margin-top: 20px;">
			<tr><td style="width: 80px;">OS</td><td>Enabled</td><td style="text-align: center; width: 80px;">Size</td></tr>
			<tr><td style="background-color: #494a69; font-weight: normal;">Linux</td><td id="len" style="text-align: center; background-color: #494a69; font-weight: normal;"><span style="font-weight: bold; font-size: 13px; color: #cf1104;">&#10060;</span></td><td id="lsize" style="background-color: #494a69; font-weight: normal; text-align: center;"></td></tr>
			<tr><td style="background-color: #494a69; font-weight: normal;">Mac</td><td id="men" style="text-align: center; background-color: #494a69; font-weight: normal;"><span style="font-weight: bold; font-size: 13px; color: #cf1104;">&#10060;</span></td><td id="msize" style="background-color: #494a69; font-weight: normal; text-align: center;"></td></tr>
			<tr><td style="background-color: #494a69; font-weight: normal;">Windows</td><td id="wen" style="text-align: center; background-color: #494a69; font-weight: normal;"><span style="font-weight: bold; font-size: 13px; color: #cf1104;">&#10060;</span></td><td id="wsize" style="background-color: #494a69; font-weight: normal; text-align: center;"></td></tr>
			</table>
		</div>

		<div class="module-content" style="padding: 0 1px 1px 0; width: 700px; margin-left: auto; margin-right: auto; margin-top: 30px;">
			<div class="tabbar tabbarback">
				<button type="button" class="tabbaritem tabbutton tablink tabbarsel" style="border-right: 1px solid #07f;" onclick="switchTab(event, 'Linux')">Linux</button>
				<button type="button" class="tabbaritem tabbutton tablink" style="border-right: 1px solid #07f;" onclick="switchTab(event, 'macOS')">macOS</button>
				<button type="button" class="tabbaritem tabbutton tablink" style="border-right: 1px solid #07f;" onclick="switchTab(event, 'Windows')">Windows</button>
			</div>

			<div style="margin: 8px 0 0 0; width: 100%;" id="Linux" class="configtab">
				<div style="text-align: left; color: #444;">
					<input id="leselect" name="leselect" type="checkbox" style="margin-left: 8px;" onclick="editorToggle('Linux');"<?php print ($sensor !== null && $sensor['LSCRIPT'] !== null) ? ' checked="checked"' : ''; ?>> <span style="cursor: normal; user-select: none;" onclick="labelToggle('Linux')">Enabled</span> &nbsp;&nbsp;&nbsp;&nbsp; <span id="lstlabel" style="color: #777; user-select: none;">Type: </span><select id="lstype" name="lstype" onchange="lsformat(document.getElementById('lstype').value);" disabled="disabled"><option value="shell">Shell Script</option><option value="perl">Perl</option><option value="python">Python</option></select>
				</div>
				<div id="leditor" style="margin-top: 7px; width: 100%;"></div>
				<script src="/layout/src/ace.js" type="text/javascript" charset="utf-8"></script>
				<script>
					var leditor = ace.edit("leditor");
					leditor.setShowPrintMargin(false);
					leditor.getSession().setMode("ace/mode/sh");
					// Scripts run on the client's interpreter stdin, where a
					// stray \r breaks shell scripts; lock the editor to LF so
					// pasted Windows (CRLF) text is not re-CRLF'd on submit.
					leditor.getSession().setNewLineMode("unix");
					leditor.getSession().on('change', function() {
						document.getElementById('lsize').innerHTML = formatBytes(leditor.session.getValue().length,1);
						formCheck();
						});
				</script>
			</div>

			<div style="margin: 8px 0 0 0; width: 100%; display: none;" id="macOS" class="configtab">
				<div style="text-align: left; color: #444;">
					<input id="meselect" name="meselect" type="checkbox" style="margin-left: 8px;" onclick="editorToggle('Mac');"<?php print ($sensor !== null && $sensor['MSCRIPT'] !== null) ? ' checked="checked"' : ''; ?>> <span style="cursor: normal; user-select: none;" onclick="labelToggle('Mac')">Enabled</span> &nbsp;&nbsp;&nbsp;&nbsp; <span id="mstlabel" style="color: #777; user-select: none;">Type: </span><select id="mstype" name="mstype" onchange="msformat(document.getElementById('mstype').value);" disabled="disabled"><option value="shell">Shell Script</option><option value="perl">Perl</option><option value="python">Python</option></select>
				</div>
				<div id="meditor" style="margin-top: 7px; width: 100%;"></div>
				<script>
					var meditor = ace.edit("meditor");
					meditor.setShowPrintMargin(false);
					meditor.getSession().setMode("ace/mode/sh");
					meditor.getSession().setNewLineMode("unix");
					meditor.getSession().on('change', function() {
						document.getElementById('msize').innerHTML = formatBytes(meditor.session.getValue().length,1);
						formCheck();
						});
				</script>
			</div>

			<div style="margin: 8px 0 0 0; width: 100%; display: none;" id="Windows" class="configtab">
				<div style="text-align: left; color: #444;">
					<input id="weselect" name="weselect" type="checkbox" style="margin-left: 8px;" onclick="editorToggle('Windows');"<?php print ($sensor !== null && $sensor['WSCRIPT'] !== null) ? ' checked="checked"' : ''; ?>> <span style="cursor: normal; user-select: none;" onclick="labelToggle('Windows');">Enabled</span> &nbsp;&nbsp;&nbsp;&nbsp; <span id="wstlabel" style="color: #777; user-select: none;">Type: </span><select id="wstype" name="wstype" onchange="wsformat(document.getElementById('wstype').value)" disabled="disabled"><option value="powershell">PowerShell</option><option value="vbscript">VBScript</option><option value="batch">Batch File</option><option value="python">Python</option></select>
				</div>
				<div id="weditor" style="margin-top: 7px; width: 100%;"></div>
				<script>
					var weditor = ace.edit("weditor");
					weditor.setShowPrintMargin(false);
					weditor.getSession().setMode("ace/mode/powershell");
					weditor.getSession().setNewLineMode("unix");
					weditor.getSession().on('change', function() {
						document.getElementById('wsize').innerHTML = formatBytes(weditor.session.getValue().length,1);
						formCheck();
						});
				</script>
			</div>
		</div>
	</div>

<script>
// The selected sensor's stored per-OS type/script pairs (null on the create
// form); the init block at the bottom of this script loads them into the
// ace editors.
var editData = <?php print $editdata === null ? 'null' : json_encode($editdata, JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT); ?>;

const tiElement = document.getElementById('timeout');

tiElement.addEventListener('input', function(event) {
	document.getElementById('timeout').value = numbersOnly(document.getElementById('timeout').value);
	formCheck();
	});

function caseToggle() {
	const checkbox = document.getElementById("case");

	if (checkbox.checked == true) { checkbox.checked = false; }
	else { checkbox.checked = true; }
	}

function csToggle() {
	const checkbox = document.getElementById("split");

	if (checkbox.checked == true) { checkbox.checked = false; }
	else { checkbox.checked = true; }
	toggleSplit();
	}

function paramToggle() {
	const checkbox = document.getElementById("useparams");

	if (checkbox.checked == true) { checkbox.checked = false; }
	else { checkbox.checked = true; }
	}

function labelToggle(editor) {
	if (editor == 'Linux') { var cbSelect = 'leselect'; }
	else if (editor == 'Mac') { var cbSelect = 'meselect'; }
	else if (editor == 'Windows') { var cbSelect = 'weselect'; }
	const checkbox = document.getElementById(cbSelect);

	if (checkbox.checked == true) { checkbox.checked = false; }
	else { checkbox.checked = true; }
	editorToggle(editor);
	}

function toggleSplit() {
	const delements = document.getElementsByClassName("delform");
	const checkbox = document.getElementById("split");
	var len = delements.length;

	if (checkbox.checked == true) { var ol = 1; }
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
		leditor.setValue("#!/usr/bin/perl\n\nuse strict;\n\n", 35);
		}
	else if (value == "python") {
		leditor.getSession().setMode("ace/mode/python");
		leditor.setValue("#!/usr/bin/python3\n\n", 20);
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
		meditor.setValue("#!/usr/bin/perl\n\nuse strict;\n\n", 35);
		}
	else if (value == "python") {
		meditor.getSession().setMode("ace/mode/python");
		meditor.setValue("#!/usr/local/bin/python3\n\n", 21);
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
		const checkbox = document.getElementById('leselect');
		if (checkbox.checked == true) { enableEditor('Linux'); }
		else { disableEditor('Linux'); }
		}
	else if (edsel == "Mac") {
		const checkbox = document.getElementById('meselect');
		if (checkbox.checked == true) { enableEditor('Mac'); }
		else { disableEditor('Mac'); }
		}
	else if (edsel == "Windows") {
		const checkbox = document.getElementById('weselect');
		if (checkbox.checked == true) { enableEditor('Windows'); }
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

// Set an ace editor's syntax mode for a stored script type. The
// lsformat/msformat/wsformat variants do the same but also replace the
// script with the type's template, which must not happen when loading a
// stored script.
function setEditorMode(edsel, type) {
	if (edsel == "Linux" || edsel == "Mac") {
		const editor = (edsel == "Linux") ? leditor : meditor;
		if (type == "shell") { editor.getSession().setMode("ace/mode/sh"); }
		else if (type == "perl") { editor.getSession().setMode("ace/mode/perl"); }
		else if (type == "python") { editor.getSession().setMode("ace/mode/python"); }
		}
	else if (edsel == "Windows") {
		if (type == "powershell") { weditor.getSession().setMode("ace/mode/powershell"); }
		else if (type == "vbscript") { weditor.getSession().setMode("ace/mode/vbscript"); }
		else if (type == "batch") { weditor.getSession().setMode("ace/mode/batchfile"); }
		else if (type == "python") { weditor.getSession().setMode("ace/mode/python"); }
		}
	}

// Edit mode: enable a platform's editor with the stored type and load the
// stored script (unlike enableEditor(), which resets the script to the
// type's template).
function initEditEditor(edsel, type, script) {
	if (edsel == "Linux") {
		leditor.container.style.opacity = 1;
		leditor.container.style.pointerEvents="";
		leditor.renderer.setStyle("disabled", false);
		document.getElementById('lstlabel').style.color = "#444";
		document.getElementById('lstype').disabled = false;
		document.getElementById('lstype').value = type;
		setEditorMode('Linux', type);
		leditor.setValue(script, -1);
		document.getElementById('len').innerHTML = '<span style=\"font-weight: bold; font-size: 16px; color: #0ec940;\">✓</span>';
		document.getElementById('lsize').innerHTML = formatBytes(leditor.session.getValue().length,1);
		}
	else if (edsel == "Mac") {
		meditor.container.style.opacity = 1;
		meditor.container.style.pointerEvents="";
		meditor.renderer.setStyle("disabled", false);
		document.getElementById('mstlabel').style.color = "#444";
		document.getElementById('mstype').disabled = false;
		document.getElementById('mstype').value = type;
		setEditorMode('Mac', type);
		meditor.setValue(script, -1);
		document.getElementById('men').innerHTML = '<span style=\"font-weight: bold; font-size: 16px; color: #0ec940;\">✓</span>';
		document.getElementById('msize').innerHTML = formatBytes(meditor.session.getValue().length,1);
		}
	else if (edsel == "Windows") {
		weditor.container.style.opacity = 1;
		weditor.container.style.pointerEvents="";
		weditor.renderer.setStyle("disabled", false);
		document.getElementById('wstlabel').style.color = "#444";
		document.getElementById('wstype').disabled = false;
		document.getElementById('wstype').value = type;
		setEditorMode('Windows', type);
		weditor.setValue(script, -1);
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

function numbersOnly(str) { return str.replace(/[^0-9]/g, ''); }

// Enable the Save button only when the form is complete and valid (mirrors
// the server-side validation in admin/sensormap.php), and keep the hidden
// script inputs in sync with the ace editors (which are not form fields).
function formCheck() {
	const saveBtn = document.getElementById('save');
	const name = document.querySelector('#nsform input[name="pkgname"]').value.trim();
	const desc = document.querySelector('#nsform input[name="pkgdesc"]').value.trim();
	const tval = document.getElementById('timeout').value;
	const cset = document.getElementById('contentset').value;
	const split = document.getElementById('split').checked;
	const delim = document.getElementById('delimeter').value;
	const lEn = document.getElementById('leselect').checked;
	const mEn = document.getElementById('meselect').checked;
	const wEn = document.getElementById('weselect').checked;
	const lsc = leditor.getValue();
	const msc = meditor.getValue();
	const wsc = weditor.getValue();

	document.getElementById('lhscript').value = lsc;
	document.getElementById('mhscript').value = msc;
	document.getElementById('whscript').value = wsc;

	let ok = true;
	if (name === '' || name.length > 128 || !/^[A-Za-z0-9][A-Za-z0-9 _.\-]*$/.test(name)) { ok = false; }
	if (desc === '' || desc.length > 128) { ok = false; }
	if (!/^[1-9][0-9]{0,2}$/.test(tval)) { ok = false; }
	if (cset === '') { ok = false; }
	if (split && delim.length !== 1) { ok = false; }
	if (!lEn && !mEn && !wEn) { ok = false; }
	if (lEn && lsc.trim() === '') { ok = false; }
	if (mEn && msc.trim() === '') { ok = false; }
	if (wEn && wsc.trim() === '') { ok = false; }

	if (ok) { saveBtn.disabled = false; }
	else { saveBtn.disabled = true; }
	}

document.querySelector('#nsform input[name="pkgname"]').addEventListener('input', formCheck);
document.querySelector('#nsform input[name="pkgdesc"]').addEventListener('input', formCheck);
['tint', 'rtype', 'contentset', 'category'].forEach(id => document.getElementById(id).addEventListener('change', formCheck));
['case', 'split', 'useparams', 'leselect', 'meselect', 'weselect'].forEach(id => document.getElementById(id).addEventListener('change', formCheck));
document.getElementById('delimeter').addEventListener('input', formCheck);
document.getElementById('nsform').addEventListener('submit', formCheck);

if (editData) {
	// Edit mode: load each stored platform into its editor (the enable
	// checkboxes are already checked in the markup); platforms the sensor
	// does not define stay disabled.
	if (editData.lscript !== null) { initEditEditor('Linux', editData.lstype, editData.lscript); }
	else { disableEditor('Linux'); }
	if (editData.mscript !== null) { initEditEditor('Mac', editData.mstype, editData.mscript); }
	else { disableEditor('Mac'); }
	if (editData.wscript !== null) { initEditEditor('Windows', editData.wstype, editData.wscript); }
	else { disableEditor('Windows'); }
	if (editData.csplit) { toggleSplit(); }
	}
else {
	disableEditor('Linux');
	disableEditor('Mac');
	disableEditor('Windows');
	}
formCheck();
</script>

		<?php else: ?>

		<h1 style="color: red">Access Denied</h1>

		<?php endif; ?>
	<?php endif; ?>
<?php endif; ?>

<script src="layout/table.js"></script>
<script>
LuminumTable.attachTextFilter('sensorsfilter');

function rowHighlight(idnum) {
	var checkbox = document.getElementById("ID" + idnum);
	const checkboxes = document.querySelectorAll('input[class="sensorrow"]');
	var checkTrigger = 0;

	checkboxes.forEach(checkbox => {
		if (checkbox.checked == true) { checkTrigger++; }
		});

	if (checkbox.checked == true) {
		var bgcolor = "#686993";
		var buttontoggle = false;
		}
	else {
		var bgcolor = "#494a69";
		if (checkTrigger == 0) { var buttontoggle = "disabled"; }
		}

	if (checkTrigger > 1) {
		document.getElementById("getinfo").disabled = "disabled";
		document.getElementById("modify").disabled = "disabled";
		}
	else {
		document.getElementById("getinfo").disabled = buttontoggle;
		if (document.getElementById(idnum + "E").innerText != "lumadmin") {
			document.getElementById("modify").disabled = buttontoggle;
			}
		}

	if (checkTrigger == checkboxes.length) {
		document.getElementById("delete").disabled = "disabled";
		}
	else {
		if (document.getElementById(idnum + "E").innerText != "lumadmin") {
			document.getElementById("delete").disabled = buttontoggle;
			}
		}

	document.getElementById(idnum + "A").style.backgroundColor = bgcolor;
	document.getElementById(idnum + "B").style.backgroundColor = bgcolor;
	document.getElementById(idnum + "C").style.backgroundColor = bgcolor;
	document.getElementById(idnum + "D").style.backgroundColor = bgcolor;
	document.getElementById(idnum + "E").style.backgroundColor = bgcolor;
	document.getElementById(idnum + "F").style.backgroundColor = bgcolor;
	document.getElementById(idnum + "G").style.backgroundColor = bgcolor;
	document.getElementById(idnum + "H").style.backgroundColor = bgcolor;
	}

function allToggle() {
	const allCheckbox = document.getElementById("selectall");
	const checkboxes = document.querySelectorAll('input[class="sensorrow"]');

	checkboxes.forEach(checkbox => {
		checkbox.checked = allCheckbox.checked;
		var rowId = removeLetters(checkbox.id);
		rowHighlight(rowId);
		});
	allCheck();
	}

function allCheck() {
	const checkboxes = document.querySelectorAll('input[class="sensorrow"]');
	var checkTrigger = 0;

	checkboxes.forEach(checkbox => {
		if (checkbox.checked == true) { checkTrigger++; }
		});

	document.getElementById("selcount").textContent = checkTrigger;

	if (checkTrigger == checkboxes.length) {
		document.getElementById("selectall").checked = "checked";
		}
	else { document.getElementById("selectall").checked = false; }
	}

function removeLetters(str) {
	return str.replace(/[a-zA-Z]/g, '');
	}

// Modify Selected opens the create form pre-filled with the selected
// sensor's stored values (rowHighlight() only enables the button for a
// single non-lumadmin selection).
document.getElementById("modify").addEventListener('click', function () {
	var checkboxes = document.querySelectorAll('input[class="sensorrow"]');
	var sel = null;
	checkboxes.forEach(cb => { if (cb.checked) { sel = removeLetters(cb.id); } });
	if (sel !== null) { window.location.href = '/index.php?view=sensors&action=edit&id=' + sel; }
	});
</script>
