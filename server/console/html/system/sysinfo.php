<?php

if ($acctrole > 1) {
	print "<div class=\"content\">\n";
	print "<h1 style=\"color: red\">Access Denied</h1>\n";
	}
else {
	mysqli_select_db($db, "SYSTEM") or die( "<h5>Fatal Error</h5>\n\n<p>Unable to access database.\n</p>");
	$confquery = mysqli_query($db, "select CVAL from CONFIG where CKEY = 'SKEY'");
	$confresult = mysqli_fetch_assoc($confquery);
	$cpumodel = shell_exec("/usr/bin/cat /proc/cpuinfo | /usr/bin/grep -m 1 'model name' | /usr/bin/sed -e \"s/^.*\\\\: //\"");
	$cpuspeed = shell_exec("/usr/bin/cat /proc/cpuinfo | /usr/bin/grep -m 1 'MHz' | /usr/bin/sed -e \"s/^.*\\\\: //\"");
	$cpucores = shell_exec("/usr/bin/cat /proc/cpuinfo | /usr/bin/grep 'processor' | /usr/bin/wc -l");
	$cpuarch = shell_exec("/usr/bin/uname -m");
	$osver = shell_exec("/usr/bin/cat /etc/debian_version");
	$kernel = shell_exec("/usr/bin/uname -r");
	$uptime = shell_exec("/usr/bin/uptime -p | /usr/bin/sed -e 's/up //'");
	$disks = array();
	//foreach (preg_split("/\r\n|\n|\r/",shell_exec("/usr/sbin/fdisk -l | /usr/bin/grep '/dev' | /usr/bin/grep -v sectors | /usr/bin/sed -E 's/^(\/dev\/[A-Za-z]+)[0-9]+.*$/\1/' | /usr/bin/uniq")) as $value) {
	$disks = shell_exec("/usr/sbin/fdisk -l | /usr/bin/grep sectors | /usr/bin/grep -v Units | /usr/bin/uniq | /usr/bin/wc -l");
	$diskinfo = shell_exec("/usr/bin/df -h | /usr/bin/grep -vE '(udev|tmpfs|Filesy)' | /usr/bin/sed -e 's/\s......//' -e 's/  / /g' -e 's/  / /g' -e 's/\/$//' -e 's/G/GB/g'");
	$diskarray = explode(" ",$diskinfo);
	$ifaces = shell_exec("/usr/sbin/ifconfig | /usr/bin/grep inet | /usr/bin/grep -v 127.0 | /usr/bin/wc -l");
?>

<div class="content">
	<h1>System Information</h1>

	<div class="module-content" style="padding: 0;">
		<div class="tabbar tabbarback">
			<button type="button" class="tabbaritem tabbutton tablink tabbarsel" style="border-right: 1px solid #07f;" onclick="switchTab(event, 'Luminum')">Luminum</button>
			<button type="button" class="tabbaritem tabbutton tablink" style="border-right: 1px solid #07f;" onclick="switchTab(event, 'CPU')">CPU</button>
			<button type="button" class="tabbaritem tabbutton tablink" style="border-right: 1px solid #07f;" onclick="switchTab(event, 'Disks')">Disks</button>
			<button type="button" class="tabbaritem tabbutton tablink" style="border-right: 1px solid #07f;" onclick="switchTab(event, 'Memory')">Memory</button>
			<button type="button" class="tabbaritem tabbutton tablink" style="border-right: 1px solid #07f;" onclick="switchTab(event, 'Network')">Network</button>
		</div>

		<div id="Luminum" class="configtab">
			<table style="width: 50%; border: 0; margin-left: auto; margin-right: auto; margin-top: 15px; margin-bottom: 15px;">
			<tr><td style="width: 50%; color: #444; background-color: transparent; border: 0;">Luminum Server Version:</td><td style="width: 50%; color: #444; background-color: transparent; border: 0; font-weight: normal;">0.0.1</td></tr>
			<tr><td style="width: 50%; color: #444; background-color: transparent; border: 0;">Web Console Version:</td><td style="width: 50%; color: #444; background-color: transparent; border: 0; font-weight: normal;">0.0.1</td></tr>
			<tr><td style="width: 50%; color: #444; background-color: transparent; border: 0;">Server License:</td><td style="width: 50%; color: #444; background-color: transparent; border: 0; font-weight: normal;">Community</td></tr>
			<?php print "<tr><td style=\"width: 50%; color: #444; background-color: transparent; border: 0; font-weight: bold;\">Server Key:</td><td style=\"width: 50%; color: #444; background-color: transparent; border: 0; font-weight: normal;\">" . $confresult["CVAL"] . "</td></tr>\n"; ?>
			</table>
		</div>

		<div id="CPU" class="configtab" style="display: none;">
			<div style="width: 100%; margin-left: 20px; margin-top: 20px; margin-bottom: 80px;">
				<img src="/images/cpu.png" style="width: 200px; height: 200px; float: left; position: absolute;">
				<table style="border: 0; position: relative; margin-left: 220px; width: 450px;">
					<tr><td style="text-align: left; background-color: transparent; border: 0; color: black;">Model:</td><td style="font-weight: normal; background-color: transparent; border: 0; color: black; text-align: left;"><?php print $cpumodel; ?></td></tr>
					<tr><td style="text-align: left; background-color: transparent; border: 0; color: black;">Speed:</td><td style="font-weight: normal; background-color: transparent; border: 0; color: black; text-align: left;"><?php print $cpuspeed; ?> MHz</td></tr>
					<tr><td style="text-align: left; background-color: transparent; border: 0; color: black;">Cores:</td><td style="font-weight: normal; background-color: transparent; border: 0; color: black; text-align: left;"><?php print $cpucores; ?></td></tr>
					<tr><td style="text-align: left; background-color: transparent; border: 0; color: black;">Architecture:</td><td style="font-weight: normal; background-color: transparent; border: 0; color: black; text-align: left;"><?php print $cpuarch; ?></td></tr>
				</table>
			</div>

			<hr style="width: 97%; margin-left: 13px; margin-top: 20px; margin-bottom: 20px;">

			<table style="border: 0; margin-top: 20px; margin-left: 8px;">
			<tr><td style="text-align: left; background-color: transparent; border: 0; color: black;">Operating System:</td><td style="font-weight: normal; background-color: transparent; border: 0; color: black; text-align: right;"><?php print "Debian Linux $osver"; ?></td></tr>
			<tr><td style="text-align: left; background-color: transparent; border: 0; color: black;">Kernel Version:</td><td style="font-weight: normal; background-color: transparent; border: 0; color: black; text-align: right;"><?php print $kernel; ?></td></tr>
			<tr><td style="text-align: left; background-color: transparent; border: 0; color: black;">System Uptime:</td><td style="font-weight: normal; background-color: transparent; border: 0; color: black; text-align: right;"><?php print $uptime; ?></td></tr>
			</table>
		</div>

		<div id="Disks" class="configtab" style="display: none;">
			<img src="/images/drives.png" style="width: 200px; height: 200px;">
			<table style="width: 20%; border: 0; margin-left: auto; margin-right: auto; margin-top: 15px; margin-bottom: 15px;">
			<tr><td style="text-align: left; background-color: transparent; border: 0; color: black;">Connected Drives:</td><td style="font-weight: normal; background-color: transparent; border: 0; color: black; text-align: right;"><?php print $disks; ?></td></tr>
			</table>

			<table style="width: 20%; border: 0; margin-left: auto; margin-right: auto; margin-top: 15px; margin-bottom: 15px;">
			<tr><td style="text-align: left; background-color: transparent; border: 0; color: black;">Capacity:</td><td style="font-weight: normal; background-color: transparent; border: 0; color: black; text-align: right;"><?php print $diskarray[1]; ?></td></tr>
			<tr><td style="text-align: left; background-color: transparent; border: 0; color: black;">Used Space:</td><td style="font-weight: normal; background-color: transparent; border: 0; color: black; text-align: right;"><?php print $diskarray[2]; ?></td></tr>
			<tr><td style="text-align: left; background-color: transparent; border: 0; color: black;">Free Space:</td><td style="font-weight: normal; background-color: transparent; border: 0; color: black; text-align: right;"><?php print $diskarray[3]; ?></td></tr>
			</table>
		</div>

		<div id="Memory" class="configtab" style="display: none;">
			<img src="/images/ram.png" style="width: 200px; height: 200px;">
		</div>

		<div id="Network" class="configtab" style="display: none;">
			<img src="/images/network.png" style="width: 200px; height: 200px;">
			<table style="border: 0; margin-top: 20px; margin-left: 8px;">
			<tr><td style="text-align: left; background-color: transparent; border: 0; color: black;">Physical Interfaces:</td><td style="font-weight: normal; background-color: transparent; border: 0; color: black; text-align: right;"><?php print $ifaces; ?></td></tr>
			</table>
		</div>
	</div>

<script>
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

<?php } ?>
