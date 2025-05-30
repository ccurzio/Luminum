<?php
mysqli_select_db($db, "CONTENT") or die( "<h5>Fatal Error</h5>\n\n<p>Unable to access database.\n</p>");

$starttime = microtime(true);
$pkgquery = mysqli_query($db, "select ID,NAME,DESCRIPTION,SIZE,MAC,LIN,WIN,AUTHOR,CREATED,MODIFIED,EDITOR,REVISIONS from PACKAGES order by ID");
$csets = mysqli_query($db, "select ID,NAME from SETS order by NAME");
$endtime = microtime(true);

$duration = number_format((float)$endtime - $starttime, 2, '.', '');
$pkgcount = mysqli_num_rows($pkgquery);
?>

<div class="content">

<?php if ($_GET["view"] == "packages"): ?>
        <?php if (!isset($_GET["action"])): ?>

	<h1>Packages</h1>

	<div class="module-content">
                <?php
                print "<div style=\"display: block; width: 100%; text-align: right;\">\n";
                if (isset($acctrole) && $acctrole <= 2) {
                        print "<a href=\"/index.php?view=packages&action=new\"><button class=\"formgo\" style=\"margin-top: 5px; margin-right: 0;\">Create New</button></a>\n";
                        print "<button class=\"formgo\" style=\"margin-top: 5px; margin-right: 0;\" disabled=\"disabled\">Modify Selected</button>\n";
                        print "<button class=\"formgo\" style=\"margin-top: 5px; margin-right: 0;\" disabled=\"disabled\">Delete Selected</button>\n";
                        }
                print "<button class=\"formgo\" style=\"margin-top: 5px; margin-right: 0;\" disabled=\"disabled\">Get Info</button>\n";
                print "</div>\n";
                ?>
		<table style="margin-top: 10px;">
		<tr><td colspan="10"><div style="position: absolute; padding-top: 7px; padding-left: 5px;">0 of <?php print $pkgcount; ?> items</div>
		<div style="float: right; text-align: right; padding-right: 5px;">Content Set: <select id="contentset" name="contentset" style="margin-left: 2px; margin-right: 30px; margin-top: 2px; width: 170px; height: 28px;" <?php if ($pkgcount == 0) { print "disabled=\"disabled\""; } ?>>
			<option value="all">All</option>
			<?php
			while ($csrow = mysqli_fetch_assoc($csets)) {
				print "<option value=\"" . $csrow["ID"] . "\">" . $csrow["NAME"] . "</option>\n";
				}
			?>
		</select> Filter: <input type="text" style="font-size: 15px; padding: 3px; margin-top: 0;" <?php if ($pkgcount == 0) { print "disabled=\"disabled\""; } ?> maxlength="64"></div></td></tr>
		<tr><td style="width: 15px;">
		<?php
			if ($pkgcount == 0) { print "<input type=\"checkbox\" disabled=\"disabled\">"; }
			else { print "<input type=\"checkbox\">"; }
		?>
		</td><td style="width: 200px;">Name</td><td>Description</td><td style="width: 100px;">Supports</td><td style="width: 75px;">Size</td><td style="width: 100px;">Author</td><td style="width: 175px;">Create Date</td><td style="width: 175px;">Last Modification</td><td style="width: 100px;">Modified By</tr>
		<?php

		if ($pkgcount == 0) {
			print "<tr><td colspan=\"10\" style=\"text-align: center; background-color: #494a69; font-weight: normal; font-style: italic;\">No Results</td></tr>\n";
			}
		else {
			while($row = mysqli_fetch_assoc($pkgquery)) {
				print "<tr><td id=\"" . $row["ID"] . "A\" style=\"width: 15px; background-color: #494a69;\"><input id=\"ID" . $row["ID"] . "\" type=\"checkbox\" onclick=\"rowHighlight(" . $row["ID"] . ")\"></td><td id=\"" . $row["ID"] . "B\" style=\"width: 50px; background-color: #494a69; font-weight: normal;\">" . $row["NAME"] . "</td><td id=\"" . $row["ID"] . "C\" style=\"width: 75px; background-color: #494a69; font-weight: normal;\">" . $row["DESCRIPTION"] . "</td><td id=\"" . $row["ID"] . "D\" style=\"width: 120px; background-color: #494a69; font-weight: normal;\">" . "COMPAT" . "</td><td id=\"" . $row["ID"] . "E\" style=\"background-color: #494a69; font-weight: normal;\">" . "SIZE" . "</td><td id=\"" . $row["ID"] . "F\" style=\"width: 90px; background-color: #494a69; font-weight: normal;\">" . $row["AUTHOR"] . "</td><td id=\"" . $row["ID"] . "G\" style=\"width: 90px; background-color: #494a69; font-weight: normal;\">" . $row["CREATED"] . "</td>" . "<td id=\"" . $row["ID"] . "H\" style=\"width: 90px; background-color: #494a69; font-weight: normal;\">" . $row["MODIFIED"] . "</td><td id=\"" . $row["ID"] . "I\" style=\"background-color: #494a69; font-weight: normal;\">" . $row["EDITOR"] . "</td></tr>\n";
				}
			}
		?>
		<tr style="height: 35px;"><td colspan="10"><div style="position: absolute; padding-top: 5px;"></div><div style="float: right; text-align: right; padding-bottom: 2px; padding-right: 5px; font-weight: normal;"><i>Query Completed in <?php print $duration; ?> Seconds</i></div></td></tr>
		</table>
	</div>

	<?php elseif ($_GET["action"] == "new"): ?>

		<?php
		if (isset($acctrole) && $acctrole <= 2): ?>
		<h1>Create New Package</h1>

		<form id="npform" action="/admin/packages.php" method="POST">
		<div style="width: 100%; text-align: right; margin: -50px auto 10px auto;">
			<button id="save" class="formgo" style="margin-right: 0px;" disabled="disabled">Save Package</button>
			<a href="/index.php?view=packages"><button type="button" class="formgo" style="margin-top: 5px; margin-right: 25px;">Cancel</button></a>
		</div>

		<div class="module-content" style="overflow: auto; min-width: 1000px;">
			<div style="float: left; margin-bottom: 10px;">
				<table style="margin-top: 10px; margin-bottom: 20px; border: 0;">
				<tr><td style="background-color: transparent; border: 0; color: #444;">Name: <span style="color: red;">*</span></td><td style="background-color: transparent; border: 0; color: #444;">Download Timeout: <span style="color: red;">*</span> <div class="tooltip"><img src="/icons/help.png" style="width: 15px; height: 15px; opacity: 0.33; vertical-align: top;"> <span class="tooltiptext">Specifies how long the client should wait to fully download the package files before aborting the operation<br><br>Default: 2 Minutes</span></div></td></tr>
				<tr><td style="background-color: transparent; border: 0; color: #444;"><input type="text" name="pkgname" style="width: 400px;" maxlength="128"></td><td style="background-color: transparent; border: 0; color: #444;"><input id="timeout" type="text" style="width: 30px;" value="2" maxlength="3"><select id="tint" style="width: 100px; margin-left: 10px; height: 33px;"><option value="sec">Second(s)</option><option value="min" selected="selected">Minute(s)</option></select></td></tr>
				<tr><td style="padding-top: 30px; background-color: transparent; border: 0; color: #444;">Description: <span style="color: red;">*</span></td><td style="padding-top: 30px; background-color: transparent; border: 0; color: #444;">Completion Timeout: <span style="color: red;">*</span> <div class="tooltip"><img src="/icons/help.png" style="width: 15px; height: 15px; opacity: 0.33; vertical-align: top;"> <span class="tooltiptext">Specifies how long the client should wait for the specified command to finish<br><br>Default: 5 Minutes</span></div></td></tr>
				<tr><td style="background-color: transparent; border: 0; color: #444;"><input type="text" name="pkgdesc" style="width: 400px;" maxlength="128"></td><td style="background-color: transparent; border: 0; color: #444;"><input id="dtimeout" type="text" style="width: 30px;" value="5" maxlength="3"><select id="tint" style="width: 100px; margin-left: 10px; height: 33px;"><option value="sec">Second(s)</option><option value="min" selected="selected">Minute(s)</option></select></td></tr></td></tr>
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
				</table>

			</div>

		<hr style="width: 99%; margin-bottom: 20px;">

		<div style="float: left; margin-left: 10px;">
			<table style="width: 250px; margin-left: auto; margin-right: auto; margin-top: 20px;">
			<tr><td style="width: 80px;">OS</td><td>Enabled</td><td style="text-align: center; width: 80px;">Size</td></tr>
			<tr><td style="background-color: #494a69; font-weight: normal;">Linux</td><td id="len" style="text-align: center; background-color: #494a69; font-size: 13px;"><span style="font-weight: bold; font-size: 13px; color: #cf1104;">&#10060;</span></td><td id="lsize" style="background-color: #494a69; font-weight: normal;"></td></tr>
			<tr><td style="background-color: #494a69; font-weight: normal;">Mac</td><td id="men" style="text-align: center; background-color: #494a69; font-size: 13px;"><span style="font-weight: bold; font-size: 13px; color: #cf1104;">&#10060;</span></td><td id="msize" style="background-color: #494a69; font-weight: normal;"></tr>
			<tr><td style="background-color: #494a69; font-weight: normal;">Windows</td><td id="wen" style="text-align: center; background-color: #494a69; font-size: 13px;"><span style="font-weight: bold; font-size: 13px; color: #cf1104;">&#10060;</span></td><td id="wsize" style="background-color: #494a69; font-weight: normal;"></tr>
			</table>
		</div>

		<div class="module-content" style="padding: 0 1px 1px 0; width: 800px; margin-left: auto; margin-right: auto; margin-top: 40px;">
			<div class="tabbar tabbarback">
				<button type="button" class="tabbaritem tabbutton tablink tabbarsel" style="border-right: 1px solid #07f;" onclick="switchTab(event, 'Linux')">Linux</button>
				<button type="button" class="tabbaritem tabbutton tablink" style="border-right: 1px solid #07f;" onclick="switchTab(event, 'macOS')">macOS</button>
				<button type="button" class="tabbaritem tabbutton tablink" style="border-right: 1px solid #07f;" onclick="switchTab(event, 'Windows')">Windows</button>
			</div>

			<div style="margin: 8px 0 0 0; width: 100%;" id="Linux" class="configtab">
				<div style="text-align: left; color: #444;">
					<input id="lpselect" type="checkbox" style="margin-left: 8px;" onclick="pkosToggle('Linux');"> <span style="cursor: normal; user-select: none;" onclick="labelToggle('Linux')">Enabled</span>
                                </div>
                                <div id="lfeditor" style="background-color: #eee; margin-top: 7px; color: #444; width: 100%; opacity: 0.5; user-select: none;">
					<div style="width: 90%; margin-left: 125px; padding-top: 20px;">
					Command: <input type="text" id="lpkgcmd" style="width: 400px;" value="/bin/sh ./" disabled="disabled">
					</div>
					<div style="width: 90%; margin-left: 150px; padding-top: 20px; margin-bottom: 20px;">
						<div style="float: left; margin-right: 50px;">
						Files:<br>
						<select id="lfiles" size="8" style="width: 225px; border-radius: 6px;" disabled="disabled"></select>
						</div>

						<div>
						<br>
						Selected File Size: xx KB<br>
						<br>
						MD5 Hash:<br>
						xxxxxxxxxxxxxxxxxxxxxxxxx<br>
						<br>
						<button class="formgo" disabled="disabled">Remove</button>
						<br>
						</div>
					</div>
					<div style="width: 90%; padding-top: 10px; margin-left: 170px; padding-bottom: 40px;">
						<button class="formgo" id="lfadd" style="margin-right: 5px;" disabled="disabled">Add File</button> <button class="formgo" disabled="disabled">Remove All</button>
					</div>
				</div>
			</div>

			<div style="margin: 8px 0 0 0; width: 100%; display: none;" id="macOS" class="configtab">
				<div style="text-align: left; color: #444;">
					<input id="mpselect" type="checkbox" style="margin-left: 8px;" onclick="pkosToggle('Mac');"> <span style="cursor: normal; user-select: none;" onclick="labelToggle('Mac');">Enabled</span>
				</div>
                                <div id="mfeditor" style="background-color: #eee; margin-top: 7px; color: #444; width: 100%; opacity: 0.5; user-select: none;">
					<div style="width: 90%; margin-left: 125px; padding-top: 20px;">
					Command: <input type="text" id="mpkgcmd" style="width: 400px;" value="/bin/sh ./" disabled="disabled">
					</div>
					<div style="width: 90%; margin-left: 150px; padding-top: 20px; margin-bottom: 20px;">
						<div style="float: left; margin-right: 50px;">
						Files:<br>
						<select id="mfiles" size="8" style="width: 225px; border-radius: 6px;" disabled="disabled"></select>
						</div>

						<div>
						<br>
						Selected File Size: xx KB<br>
						<br>
						MD5 Hash:<br>
						xxxxxxxxxxxxxxxxxxxxxxxxx<br>
						<br>
						<button class="formgo" disabled="disabled">Remove</button>
						<br>
						</div>
					</div>
					<div style="width: 90%; padding-top: 10px; margin-left: 170px; padding-bottom: 40px;">
						<button class="formgo" id="mfadd" style="margin-right: 5px;" disabled="disabled">Add File</button> <button class="formgo" disabled="disabled">Remove All</button>
					</div>
				</div>
			</div>

			<div style="margin: 8px 0 0 0; width: 100%; display: none;" id="Windows" class="configtab">
				<div style="text-align: left; color: #444;">
					<input id="wpselect" type="checkbox" style="margin-left: 8px;" onclick="pkosToggle('Windows');"> <span style="cursor: normal; user-select: none;" onclick="labelToggle('Windows');">Enabled</span>
				</div>
                                <div id="wfeditor" style="background-color: #eee; margin-top: 7px; color: #444; width: 100%; opacity: 0.5; user-select: none;">
					<div style="width: 90%; margin-left: 125px; padding-top: 20px;">
					Command: <input type="text" id="wpkgcmd" style="width: 400px;" value="cmd.exe .\" disabled="disabled">
					</div>
					<div style="width: 90%; margin-left: 150px; padding-top: 20px; margin-bottom: 20px;">
						<div style="float: left; margin-right: 50px;">
						Files:<br>
						<select id="wfiles" size="8" style="width: 225px; border-radius: 6px;" disabled="disabled"></select>
						</div>

						<div>
						<br>
						Selected File Size: xx KB<br>
						<br>
						MD5 Hash:<br>
						xxxxxxxxxxxxxxxxxxxxxxxxx<br>
						<br>
						<button class="formgo" disabled="disabled">Remove</button>
						<br>
						</div>
					</div>
					<div style="width: 90%; padding-top: 10px; margin-left: 170px; padding-bottom: 40px;">
						<button class="formgo" id="wfadd" style="margin-right: 5px;" disabled="disabled">Add File</button> <button class="formgo" disabled="disabled">Remove All</button>
					</div>
				</div>
			</div>
		</div>
	</div>

<script>
const dtElement = document.getElementById('timeout');
const ctElement = document.getElementById('dtimeout');

dtElement.addEventListener('input', function(event) {
	document.getElementById('timeout').value = numbersOnly(document.getElementById('timeout').value);
	//formCheck();
	});

ctElement.addEventListener('input', function(event) {
	document.getElementById('dtimeout').value = numbersOnly(document.getElementById('dtimeout').value);
	//formCheck();
	});

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

function labelToggle(osel) {
	if (osel == 'Linux') { var cbSelect = 'lpselect'; }
	else if (osel == 'Mac') { var cbSelect = 'mpselect'; }
	else if (osel == 'Windows') { var cbSelect = 'wpselect'; }
	const checkBox = document.getElementById(cbSelect);

	if (checkBox.checked == true) { checkBox.checked = false; }
	else { checkBox.checked = true; }
	pkosToggle(osel);
	}

function pkosToggle(psel) {
	if (psel == "Linux") {
		const checkBox = document.getElementById('lpselect');
		if (checkBox.checked == true) { enableOS('Linux'); }
		else { disableOS('Linux'); }
		}
	else if (psel == "Mac") {
		const checkBox = document.getElementById('mpselect');
		if (checkBox.checked == true) { enableOS('Mac'); }
		else { disableOS('Mac'); }
		}
	else if (psel == "Windows") {
		const checkBox = document.getElementById('wpselect');
		if (checkBox.checked == true) { enableOS('Windows'); }
		else { disableOS('Windows'); }
		}
	}

function enableOS(osel) {
	if (osel == "Linux") {
		lfeditor.style.opacity = 1;
		document.getElementById('lfiles').disabled = false;
		document.getElementById('lpkgcmd').disabled = false;
		document.getElementById('lfadd').disabled = false;
		document.getElementById('len').innerHTML = '<span style=\"font-weight: bold; font-size: 16px; color: #0ec940;\">✓</span>';
		document.getElementById('lsize').innerHTML = formatBytes(0,1);
		}
	else if (osel == "Mac") {
		mfeditor.style.opacity = 1;
		document.getElementById('mfiles').disabled = false;
		document.getElementById('mpkgcmd').disabled = false;
		document.getElementById('mfadd').disabled = false;
		document.getElementById('men').innerHTML = '<span style=\"font-weight: bold; font-size: 16px; color: #0ec940;\">✓</span>';
		document.getElementById('msize').innerHTML = formatBytes(0,1);
		}
	else if (osel == "Windows") {
		wfeditor.style.opacity = 1;
		document.getElementById('wfiles').disabled = false;
		document.getElementById('wpkgcmd').disabled = false;
		document.getElementById('wfadd').disabled = false;
		document.getElementById('wen').innerHTML = '<span style=\"font-weight: bold; font-size: 16px; color: #0ec940;\">✓</span>';
		document.getElementById('wsize').innerHTML = formatBytes(0,1);
		}
	}

function disableOS(osel) {
	if (osel == "Linux") {
		lfeditor.style.opacity = 0.5;
		document.getElementById('lfiles').disabled = true;
		document.getElementById('lpkgcmd').disabled = true;
		document.getElementById('lfadd').disabled = true;
		document.getElementById('len').innerHTML = '<span style=\"font-weight: bold; font-size: 13px; color: #cf1104;\">&#10060;</span>';
		document.getElementById('lsize').innerHTML = '';
		}
	else if (osel == "Mac") {
		mfeditor.style.opacity = 0.5;
		document.getElementById('mfiles').disabled = true;
		document.getElementById('mpkgcmd').disabled = true;
		document.getElementById('mfadd').disabled = true;
		document.getElementById('men').innerHTML = '<span style=\"font-weight: bold; font-size: 13px; color: #cf1104;\">&#10060;</span>';
		document.getElementById('msize').innerHTML = '';
		}
	else if (osel == "Windows") {
		wfeditor.style.opacity = 0.5;
		document.getElementById('wfiles').disabled = true;
		document.getElementById('wpkgcmd').disabled = true;
		document.getElementById('wfadd').disabled = true;
		document.getElementById('wen').innerHTML = '<span style=\"font-weight: bold; font-size: 13px; color: #cf1104;\">&#10060;</span>';
		document.getElementById('wsize').innerHTML = '';
		}
	}

function formatBytes(bytes, decimals = 2) {
	if (!+bytes) return '0 B'
	const k = 1024
	const dm = decimals < 0 ? 0 : decimals
	const sizes = ['B', 'KB', 'MB', 'GB', 'TB']
	const i = Math.floor(Math.log(bytes) / Math.log(k))

	return `${parseFloat((bytes / Math.pow(k, i)).toFixed(dm))} ${sizes[i]}`
	}

function numbersOnly(str) { return str.replace(/[^0-9]/g, ''); }

</script>

	<?php else: ?>

		<h1 style="color: red">Access Denied</h1>

	<?php endif; ?>

<?php endif; ?>
<?php endif; ?>
