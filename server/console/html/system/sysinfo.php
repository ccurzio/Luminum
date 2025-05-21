<?php

if ($acctrole > 1) {
	print "<div class=\"content\">\n";
	print "<h1 style=\"color: red\">Access Denied</h1>\n";
	}
else {
	$cpumodel = shell_exec("cat /proc/cpuinfo | grep -m 1 'model name' | sed -e \"s/^.*\\\\: //\"");
	$cpuspeed = shell_exec("cat /proc/cpuinfo | grep -m 1 'MHz' | sed -e \"s/^.*\\\\: //\"");
	$cpucores = shell_exec("cat /proc/cpuinfo | grep 'processor' | wc -l");
	$cpuarch = shell_exec("uname -m");
	$osver = shell_exec("cat /etc/debian_version");
	$kernel = shell_exec("uname -r");
	$uptime = shell_exec("uptime -p | sed -e 's/up //'");
	$numdisks = shell_exec("ls /dev/sd* | grep -vE '[0-9]' | wc -l");
	$diskinfo = shell_exec("df -h | grep -vE '(udev|tmpfs|Filesy)' | sed -e 's/\s......//' -e 's/  / /g' -e 's/  / /g' -e 's/\/$//' -e 's/G/GB/g'");
	$diskarray = explode(" ",$diskinfo);
	$ifaces = shell_exec("ifconfig | grep inet | grep -v 127.0 | wc -l");
?>

<div class="content">
	<h1>System Information</h1>

	<div style="width: 98%; margin-left: auto; margin-right: auto; text-align: center; height: 400px;">
		<div class="module-content" style="float: left; position: relative; width: 390px; margin-bottom: 20px; margin-left: 30px; padding-top: 15px; padding-left: 5px;">
			<span style="font-weight: bold; font-size: 28px;">CPU</span>

			<table style="border: 0; margin-top: 20px; margin-left: 8px;">
			<tr><td style="text-align: left; background-color: transparent; border: 0; color: black;">Model:</td><td style="font-weight: normal; background-color: transparent; border: 0; color: black; text-align: right;"><?php print $cpumodel; ?></td></tr>
			<tr><td style="text-align: left; background-color: transparent; border: 0; color: black;">Speed:</td><td style="font-weight: normal; background-color: transparent; border: 0; color: black; text-align: right;"><?php print $cpuspeed; ?> MHz</td></tr>
			<tr><td style="text-align: left; background-color: transparent; border: 0; color: black;">Cores:</td><td style="font-weight: normal; background-color: transparent; border: 0; color: black; text-align: right;"><?php print $cpucores; ?></td></tr>
			<tr><td style="text-align: left; background-color: transparent; border: 0; color: black;">Architecture:</td><td style="font-weight: normal; background-color: transparent; border: 0; color: black; text-align: right;"><?php print $cpuarch; ?></td></tr>
			</table>

			<hr style="width: 97%; margin-left: 13px; margin-top: 20px; margin-bottom: 20px;">

			<table style="border: 0; margin-top: 20px; margin-left: 8px;">
			<tr><td style="text-align: left; background-color: transparent; border: 0; color: black;">Operating System:</td><td style="font-weight: normal; background-color: transparent; border: 0; color: black; text-align: right;"><?php print "Debian Linux $osver"; ?></td></tr>
			<tr><td style="text-align: left; background-color: transparent; border: 0; color: black;">Kernel Version:</td><td style="font-weight: normal; background-color: transparent; border: 0; color: black; text-align: right;"><?php print $kernel; ?></td></tr>
			<tr><td style="text-align: left; background-color: transparent; border: 0; color: black;">System Uptime:</td><td style="font-weight: normal; background-color: transparent; border: 0; color: black; text-align: right;"><?php print $uptime; ?></td></tr>
			</table>
		</div>

		<div class="module-content" style="float: left; position: relative; width: 390px; margin-bottom: 20px; margin-left: 10px; padding-top: 15px; padding-left: 5px; padding-right: 25px;">
			<span style="font-weight: bold; font-size: 28px;">Disks</span>

			<table style="border: 0; margin-top: 20px; margin-left: 8px;">
			<tr><td style="text-align: left; background-color: transparent; border: 0; color: black;">Physical Drives:</td><td style="font-weight: normal; background-color: transparent; border: 0; color: black; text-align: right;"><?php print $numdisks; ?></td></tr>
			<tr><td style="text-align: left; background-color: transparent; border: 0; color: black;">Used Space:</td><td style="font-weight: normal; background-color: transparent; border: 0; color: black; text-align: right;"><?php print $diskarray[2]; ?></td></tr>
			<tr><td style="text-align: left; background-color: transparent; border: 0; color: black;">Free Space:</td><td style="font-weight: normal; background-color: transparent; border: 0; color: black; text-align: right;"><?php print $diskarray[3]; ?></td></tr>
			<tr><td style="text-align: left; background-color: transparent; border: 0; color: black;">Total Storage:</td><td style="font-weight: normal; background-color: transparent; border: 0; color: black; text-align: right;"><?php print $diskarray[1]; ?></td></tr>
			</table>
		</div>

		<div class="module-content" style="float: left; position: relative; width: 390px; margin-bottom: 20px; margin-left: 10px; padding-top: 15px;">
			<span style="font-weight: bold; font-size: 28px;">Memory</span>
		</div>
	</div>

	<div style="width: 100%; margin-left: auto; margin-right: auto; text-align: center;">
		<div class="module-content" style="float: left; position: relative; width: 390px; margin-bottom: 20px; margin-left: 45px; padding-top: 15px; padding-left: 5px;">
			<span style="font-weight: bold; font-size: 28px;">Network</span>

			<table style="border: 0; margin-top: 20px; margin-left: 8px;">
			<tr><td style="text-align: left; background-color: transparent; border: 0; color: black;">Physical Interfaces:</td><td style="font-weight: normal; background-color: transparent; border: 0; color: black; text-align: right;"><?php print $ifaces; ?></td></tr>
			</table>
		</div>


		<div class="module-content" style="float: left; position: relative; width: 390px; margin-bottom: 20px; margin-left: 17px; padding-top: 15px; padding-left: 5px; margin-right: 40px;">

		</div>


		<div class="module-content" style="float: left; position: relative; width: 390px; margin-bottom: 20px; margin-left: 10px; padding-top: 15px; padding-left: 5px;">

		</div>
	</div>
</div>

<?php } ?>
