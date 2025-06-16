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
		$netifaces = explode(" ",shell_exec("/usr/sbin/ifconfig | /usr/bin/grep inet | /usr/bin/grep -v \"127.0.0.1\" | /usr/bin/sed -E 's/^.*inet/inet/; s/[inet|netmask|brodc]//g; s/\s+/ /g; s/^\s//'"));
		$gateway = rtrim(shell_exec("/usr/sbin/route -n | /usr/bin/grep 'UG[ \t]' | /usr/bin/awk '{print \$2}'"));
		$gwhostname = preg_replace("/.*pointer /","",shell_exec("/usr/bin/host $gateway"));
		$gwhostname = rtrim(preg_replace("/\.$/","",$gwhostname));
		$dnscfg = explode(" ",shell_exec("/usr/bin/cat /etc/resolv.conf | /usr/bin/sed -E 's/(search|nameserver) //g' | /usr/bin/tr '\n' ' '"));
	?>

	<div class="content">
	<h1>Network Configuration</h1>

	<div style="width: 65%; text-align: right; margin: -50px auto 10px auto;">
		<button id="save" class="formgo" style="margin-right: 0;" disabled="disabled">Save Changes</button>
		<input type="reset" id="reset" value="Reset Values" class="formgo" onclick="return resetForm();">
	</div>

	<div class="module-content" style="padding: 0; width: 60%; margin-left: auto; margin-right: auto; padding: 10px;">
		<div style="width: 75%; margin-left: auto; margin-right: auto; text-align: center;">
			<table style="border: 0;">
			<?php
				$connected = @fsockopen("www.google.com", 443);
				print "\t\t\t<tr style=\"pointer-events: none; user-select: none;\"><td style=\"color: #444; background-color: transparent; border: 0; font-weight: normal; font-size: 10px;\"><img src=\"/icons/server.png\" style=\"width: 125px; height: 125px;\"><br>$hostname<br>" . $netifaces[0] . "</td><td style=\"color: #444; background-color: transparent; border: 0; font-weight: normal;\">";
				if (shell_exec("/usr/bin/ping -c1 $gateway -W1 | /usr/bin/grep ttl") != "") {
					print "<img src=\"/icons/greenlink.png\"></td><td style=\"color: #444; background-color: transparent; border: 0; font-weight: normal; font-size: 10px;\"><img src=\"/icons/firewall.png\" style=\"width: 125px; height: 125px;\">";
					print "<br>$gwhostname<br>$gateway</td><td style=\"color: #444; background-color: transparent; border: 0; font-weight: normal; font-size: 10px;\">";
					if ($connected) { print "<img src=\"/icons/greenlink.png\"></td><td style=\"color: #444; background-color: transparent; border: 0; font-weight: normal; font-size: 10px;\"><img src=\"/icons/internet.png\" style=\"width: 125px; height: 125px;\"><br>Internet<br>Connected</td></tr>\n"; }
					else { print "<img src=\"/icons/redlink.png\"></td><td style=\"color: #444; background-color: transparent; border: 0; font-weight: normal; font-size: 10px;\"><img src=\"/icons/internet.png\" style=\"width: 125px; height: 125px; opacity: 0.25;\"><br>Internet<br>Unreachable</td></tr>\n"; }
					fclose($connected);
					}
				else {
					print "<img src=\"/icons/redlink.png\"></td><td style=\"color: #444; background-color: transparent; border: 0; font-weight: normal; font-size: 10px;\"><img src=\"/icons/firewall.png\" style=\"width: 125px; height: 125px; opacity: 0.25\"><br>$gwhostname<br>$gateway</td><td style=\"color: #444; background-color: transparent; border: 0; font-weight: normal; font-size: 10px;\"><img src=\"/icons/redlink.png\"></td><td style=\"color: #444; background-color: transparent; border: 0; font-weight: normal; font-size: 10px;\"><img src=\"/icons/internet.png\" style=\"width: 125px; height: 125px; opacity: 0.25;\"><br>Internet<br>Unreachable</td></tr>\n";
					}
			?>
			</table>
		</div>
		<br>
		<hr style="width: 90%;">
		<br>

		<table style="border: 0; width: 85%; margin-left: auto; margin-right: auto;">
		<?php print "<tr><td style=\"color: #444; background-color: transparent; border: 0; font-weight: bold;\">Primary IP Address:</td><td style=\"color: #444; background-color: transparent; border: 0;\"><input id=\"ipaddr\" type=\"text\" style=\"width: 200px; font-size: 15px; padding: 3px; margin-top: 0;\" maxlength=\"39\" value=\"$netifaces[0]\" onchange=\"formCheck();\" tabindex=\"1\"></td><td style=\"color: #444; background-color: transparent; border: 0; font-weight: bold;\">Web Console Port:</td><td style=\"color: #444; background-color: transparent; border: 0;\"><input id=\"wcport\" type=\"text\" style=\"width: 100px; font-size: 15px; padding: 3px; margin-top: 0;\" maxlength=\"5\" value=\"$wcport\" onchange=\"formCheck();\" tabindex=\"6\"></td></tr>\n"; ?>
		<?php print "<tr><td style=\"color: #444; background-color: transparent; border: 0; font-weight: bold;\">Subnet Mask:</td><td style=\"color: #444; background-color: transparent; border: 0;\"><input id=\"subnetmask\" type=\"text\" style=\"width: 200px; font-size: 15px; padding: 3px; margin-top: 0;\" maxlength=\"39\" value=\"$netifaces[1]\" onchange=\"formCheck();\" tabindex=\"2\"></td><td style=\"color: #444; background-color: transparent; border: 0; font-weight: bold;\">Luminum Port:</td><td style=\"color: #444; background-color: transparent; border: 0;\"><input id=\"lport\" type=\"text\" style=\"width: 100px; font-size: 15px; padding: 3px; margin-top: 0;\" value=\"$lport\" onchange=\"formCheck();\" tabindex=\"7\"></td></tr>\n"; ?>
		<?php print "<tr><td style=\"color: #444; background-color: transparent; border: 0; font-weight: bold;\">Default Gateway:</td><td style=\"color: #444; background-color: transparent; border: 0;\"><input id=\"dgateway\" type=\"text\" style=\"width: 200px; font-size: 15px; padding: 3px; margin-top: 0;\" maxlength=\"39\" value=\"$gateway\" onchange=\"formCheck();\" tabindex=\"3\"></td></tr>\n"; ?>
		<?php print "<tr><td style=\"color: #444; background-color: transparent; border: 0; font-weight: bold;\">Primary DNS Server:</td><td style=\"color: #444; background-color: transparent; border: 0;\"><input id=\"dnsserver\" type=\"text\" style=\"width: 200px; font-size: 15px; padding: 3px; margin-top: 0;\" maxlength=\"39\" value=\"$dnscfg[1]\" onchange=\"formCheck();\" tabindex=\"4\"></td></tr>\n"; ?>
		<?php print "<tr><td style=\"color: #444; background-color: transparent; border: 0; font-weight: bold;\">Secondary DNS Server:</td><td style=\"color: #444; background-color: transparent; border: 0;\"><input id=\"dns2server\" type=\"text\" style=\"width: 200px; font-size: 15px; padding: 3px; margin-top: 0;\" maxlength=\"39\" value=\"$dnscfg[2]\" onchange=\"formCheck();\" tabindex=\"4\"></td></tr>\n"; ?>
		<?php print "<tr><td style=\"color: #444; background-color: transparent; border: 0; font-weight: bold;\">DNS Search Suffix:</td><td style=\"color: #444; background-color: transparent; border: 0;\"><input id=\"suffix\" type=\"text\" style=\"width: 200px; font-size: 15px; padding: 3px; margin-top: 0;\" maxlength=\"39\" value=\"$dnscfg[0]\" onchange=\"formCheck();\" tabindex=\"5\"></td></tr>\n"; ?>
		</table>
		<br>
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

<?php include ("layout/footer.php"); ?>
