<?php include ("layout/header.php");

if ($acctrole > 1) {
	print "<div class=\"content\">\n";
	print "<h1 style=\"color: red\">Access Denied</h1>\n";
	}
else {
	mysqli_select_db($db, "SYSTEM") or die( "<h5>Fatal Error</h5>\n\n<p>Unable to access database.\n</p>");
	$hostquery = mysqli_query($db, "select CVAL from CONFIG where CKEY = 'SHOST'");
	$hostinfo = $hostquery->fetch_assoc();
	$hostname = $hostinfo["CVAL"];
	$lpquery = mysqli_query($db, "select CVAL from CONFIG where CKEY = 'LPORT'");
	$lpinfo = $lpquery->fetch_assoc();
	$wcport = $_SERVER['SERVER_PORT'];
	$lport = $lpinfo["CVAL"];

	if (!isset($_GET['view']) || $_GET['view'] == "options"): ?>
	<?php include ("system/serveropts.php"); ?>

	<?php elseif ($_GET['view'] == "clients"): ?>
	<div class="content">
	<h1>Client Management</h1>

	<?php elseif ($_GET['view'] == "network"): ?>
	<?php
		$netifaces = array("", "");
		$ipinfo = trim((string) shell_exec("/usr/bin/ip -4 -o addr show scope global 2>/dev/null | /usr/bin/head -n 1 | /usr/bin/awk '{print \$4}'"));
		if ($ipinfo !== "" && strpos($ipinfo, "/") !== false) {
			list($ipaddr, $prefixlen) = explode("/", $ipinfo);
			$netifaces[0] = $ipaddr;
			$netifaces[1] = long2ip((~((1 << (32 - (int) $prefixlen)) - 1)) & 0xFFFFFFFF);
		}
		$gateway = rtrim((string) shell_exec("/usr/bin/ip route 2>/dev/null | /usr/bin/grep '^default' | /usr/bin/awk '{print \$3}' | /usr/bin/head -n 1"));
		$gwhostname = preg_replace("/.*pointer /","",shell_exec("/usr/bin/host $gateway"));
		$gwhostname = rtrim(preg_replace("/\.$/","",$gwhostname));
		$dnscfg = array("", "", "");
		if (($dnslines = file("/etc/resolv.conf", FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES)) !== false) {
			foreach ($dnslines as $dnsline) {
				$dnsline = trim($dnsline);
				if ($dnsline === "" || $dnsline[0] === "#") { continue; }
				if (preg_match('/^[Nn]ameserver[ \t]*=?[ \t]*(\S+)/', $dnsline, $m)) {
					if ($dnscfg[1] === "") { $dnscfg[1] = $m[1]; }
					elseif ($dnscfg[2] === "") { $dnscfg[2] = $m[1]; }
				}
				elseif (preg_match('/^(?:search|domain)[ \t]+(\S+)/', $dnsline, $m)) {
					$dnscfg[0] = $m[1];
				}
			}
		}
	?>

	<div class="content">
	<h1>Network Configuration</h1>

	<div style="width: 70%; text-align: right; margin: -50px auto 10px auto;">
		<input type="reset" id="reset" style="margin-right: 0;" value="Reset Values" class="formgo" onclick="return resetForm();">
		<button id="save" class="formgo" style="margin-right: 35px" disabled="disabled">Save Changes</button>
	</div>

	<div class="module-content" style="padding: 0; width: 65%; margin-left: auto; margin-right: auto;">
		<div class="tabbar tabbarback">
			<button type="button" class="tabbaritem tabbutton tablink tabbarsel" style="border-right: 1px solid #07f;" onclick="switchTab(event, 'General')">General</button>
			<button type="button" class="tabbaritem tabbutton tablink" style="border-right: 1px solid #07f;" onclick="switchTab(event, 'Proxies')">Proxies</button>
			<button type="button" class="tabbaritem tabbutton tablink" style="border-right: 1px solid #07f;" onclick="switchTab(event, 'Subnets')">Subnets</button>
			<button type="button" class="tabbaritem tabbutton tablink" style="border-right: 1px solid #07f;" onclick="switchTab(event, 'Bandwidth')">Bandwidth</button>
		</div>
		<div id="General" class="configtab" style="width: 75%; margin-left: auto; margin-right: auto; text-align: center;">
			<table style="border: 0; margin-top: 20px;">
				<?php
					$netcheck = array("www.google.com", "");
					$ncquery = mysqli_query($db, "select CKEY,CVAL from CONFIG where CKEY in ('PNETCHECK','SNETCHECK')");
					while ($ncrow = mysqli_fetch_assoc($ncquery)) {
						if ($ncrow["CKEY"] == "PNETCHECK" && $ncrow["CVAL"] != "") { $netcheck[0] = $ncrow["CVAL"]; }
						elseif ($ncrow["CKEY"] == "SNETCHECK" && $ncrow["CVAL"] != "") { $netcheck[1] = $ncrow["CVAL"]; }
						}
					$testsock = @fsockopen($netcheck[0], 443, $connerr, $connerrno, 3);
					if (!$testsock && $netcheck[1] != "") { $testsock = @fsockopen($netcheck[1], 443, $connerr, $connerrno, 3); }
					$connected = false;
					if ($testsock) { $connected = true; fclose($testsock); }
					print "\t\t\t<tr style=\"pointer-events: none; user-select: none;\"><td style=\"color: #444; background-color: transparent; border: 0; font-weight: normal; font-size: 10px;\"><img src=\"/icons/server.png\" style=\"width: 125px; height: 125px;\"><br>$hostname<br>" . $netifaces[0] . "</td><td style=\"color: #444; background-color: transparent; border: 0; font-weight: normal;\">";
					if (shell_exec("/usr/bin/ping -c1 $gateway -W1 | /usr/bin/grep ttl") != "") {
						print "<img src=\"/icons/greenlink.png\"></td><td style=\"color: #444; background-color: transparent; border: 0; font-weight: normal; font-size: 10px;\"><img src=\"/icons/firewall.png\" style=\"width: 125px; height: 125px;\">";
						print "<br>$gwhostname<br>$gateway</td><td style=\"color: #444; background-color: transparent; border: 0; font-weight: normal; font-size: 10px;\">";
						if ($connected) { print "<img src=\"/icons/greenlink.png\"></td><td style=\"color: #444; background-color: transparent; border: 0; font-weight: normal; font-size: 10px;\"><img src=\"/icons/internet.png\" style=\"width: 125px; height: 125px;\"><br>Internet<br>Connected</td></tr>\n"; }
						else { print "<img src=\"/icons/redlink.png\"></td><td style=\"color: #444; background-color: transparent; border: 0; font-weight: normal; font-size: 10px;\"><img src=\"/icons/internet.png\" style=\"width: 125px; height: 125px; opacity: 0.25;\"><br>Internet<br>Unreachable</td></tr>\n"; }
						}
					else {
						print "<img src=\"/icons/redlink.png\"></td><td style=\"color: #444; background-color: transparent; border: 0; font-weight: normal; font-size: 10px;\"><img src=\"/icons/firewall.png\" style=\"width: 125px; height: 125px; opacity: 0.25\"><br>$gwhostname<br>$gateway</td><td style=\"color: #444; background-color: transparent; border: 0; font-weight: normal; font-size: 10px;\"><img src=\"/icons/redlink.png\"></td><td style=\"color: #444; background-color: transparent; border: 0; font-weight: normal; font-size: 10px;\"><img src=\"/icons/internet.png\" style=\"width: 125px; height: 125px; opacity: 0.25;\"><br>Internet<br>Unreachable</td></tr>\n";
						}
				?>
			</table>
			<br>
			<hr />
			<br>
			<table style="text-align: left; border: 0; margin-left: auto; margin-right: auto;">
				<?php print "<tr><td style=\"color: #444; background-color: transparent; border: 0; font-weight: bold;\">Primary IP Address:</td><td style=\"color: #444; background-color: transparent; border: 0;\"><input id=\"ipaddr\" type=\"text\" style=\"width: 150px; font-size: 15px; padding: 3px; margin-top: 0; margin-right: 20px;\" maxlength=\"39\" value=\"$netifaces[0]\" onchange=\"formCheck();\" tabindex=\"1\"></td><td style=\"color: #444; background-color: transparent; border: 0; font-weight: bold;\">Web Console Port:</td><td style=\"color: #444; background-color: transparent; border: 0;\"><input id=\"wcport\" type=\"text\" style=\"width: 100px; font-size: 15px; padding: 3px; margin-top: 0;\" maxlength=\"5\" value=\"$wcport\" onchange=\"formCheck();\" tabindex=\"7\"></td></tr>\n"; ?>
				<?php print "<tr><td style=\"color: #444; background-color: transparent; border: 0; font-weight: bold;\">Subnet Mask:</td><td style=\"color: #444; background-color: transparent; border: 0;\"><input id=\"subnetmask\" type=\"text\" style=\"width: 150px; font-size: 15px; padding: 3px; margin-top: 0; margin-right: 20px;\" maxlength=\"39\" value=\"$netifaces[1]\" onchange=\"formCheck();\" tabindex=\"2\"></td><td style=\"color: #444; background-color: transparent; border: 0; font-weight: bold;\">Luminum Port:</td><td style=\"color: #444; background-color: transparent; border: 0;\"><input id=\"lport\" type=\"text\" style=\"width: 100px; font-size: 15px; padding: 3px; margin-top: 0;\" value=\"$lport\" onchange=\"formCheck();\" tabindex=\"8\"></td></tr>\n"; ?>
				<?php print "<tr><td style=\"color: #444; background-color: transparent; border: 0; font-weight: bold;\">Default Gateway:</td><td style=\"color: #444; background-color: transparent; border: 0;\"><input id=\"dgateway\" type=\"text\" style=\"width: 150px; font-size: 15px; padding: 3px; margin-top: 0; margin-right: 20px;\" maxlength=\"39\" value=\"$gateway\" onchange=\"formCheck();\" tabindex=\"3\"></td></tr>\n"; ?>
				<?php print "<tr><td style=\"color: #444; background-color: transparent; border: 0; font-weight: bold;\">Primary DNS Server:</td><td style=\"color: #444; background-color: transparent; border: 0;\"><input id=\"dnsserver\" type=\"text\" style=\"width: 150px; font-size: 15px; padding: 3px; margin-top: 0; margin-right: 20px;\" maxlength=\"39\" value=\"$dnscfg[1]\" onchange=\"formCheck();\" tabindex=\"4\"></td></tr>\n"; ?>
				<?php print "<tr><td style=\"color: #444; background-color: transparent; border: 0; font-weight: bold;\">Secondary DNS Server:</td><td style=\"color: #444; background-color: transparent; border: 0;\"><input id=\"dns2server\" type=\"text\" style=\"width: 150px; font-size: 15px; padding: 3px; margin-top: 0; margin-right: 20px;\" maxlength=\"39\" value=\"$dnscfg[2]\" onchange=\"formCheck();\" tabindex=\"5\"></td><td style=\"color: #444; background-color: transparent; border: 0; font-weight: bold;\">Connectivity Test (Primary):</td><td style=\"color: #444; background-color: transparent; border: 0; font-weight: bold;\"><input id=\"connchk\" type=\"text\" style=\"width: 150px; font-size: 15px; padding: 3px; margin-top: 0; margin-right: 20px;\" maxlength=\"128\" value=\"$netcheck[0]\" onchange=\"formCheck();\" tabindex=\"9\"></td></tr>\n"; ?>
				<?php print "<tr><td style=\"color: #444; background-color: transparent; border: 0; font-weight: bold;\">DNS Search Suffix:</td><td style=\"color: #444; background-color: transparent; border: 0;\"><input id=\"suffix\" type=\"text\" style=\"width: 150px; font-size: 15px; padding: 3px; margin-top: 0; margin-right: 20px;\" maxlength=\"39\" value=\"$dnscfg[0]\" onchange=\"formCheck();\" tabindex=\"6\"></td><td style=\"color: #444; background-color: transparent; border: 0; font-weight: bold;\">Connectivity Test (Secondary):</td><td style=\"color: #444; background-color: transparent; border: 0; font-weight: bold;\"><input id=\"sconnchk\" type=\"text\" style=\"width: 150px; font-size: 15px; padding: 3px; margin-top: 0; margin-right: 20px;\" maxlength=\"128\" value=\"$netcheck[1]\" onchange=\"formCheck();\" tabindex=\"10\"></td></tr>\n"; ?>
			</table>
			<br>
		</div>
		<div id="Proxies" class="configtab" style="display: none;">
			<p>
			</p>
		</div>
		<div id="Subnets" class="configtab" style="display: none;">
			<p>
			</p>
		</div>
		<div id="Bandwidth" class="configtab" style="display: none;">
			<p>
			</p>
		</div>

		<?php elseif ($_GET['view'] == "auth"): ?>
		<div class="content">
		<h1>Authentication</h1>

		<?php elseif ($_GET['view'] == "certs"): ?>
		<div class="content">
		<h1>Certificates</h1>

		<?php endif; 
		} ?>

</div>

<script>
function resetForm() {
	setTimeout(function() {
		srevCheck();
		prevCheck();
		formCheck();
		document.getElementById('save').disabled = true;
		}, 25);
	return true;
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

<?php include ("layout/footer.php"); ?>
