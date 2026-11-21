<?php
require_once __DIR__ . '/sysinfomap.php';

if ($acctrole > 1) {
	print "<div class=\"content\">\n";
	print "<h1 style=\"color: red\">Access Denied</h1>\n";
	}
else {
	mysqli_select_db($db, "SYSTEM") or die( "<h5>Fatal Error</h5>\n\n<p>Unable to access database.\n</p>");
	$confquery = mysqli_query($db, "select CKEY,CVAL from CONFIG where CKEY = 'SID' or CKEY = 'INSTALLDATE'");
	$adminemail = "NONE";
	while($row = mysqli_fetch_assoc($confquery)) {
		if ($row["CKEY"] == "SID") { $serverid = $row["CVAL"]; }
		else if ($row["CKEY"] == "INSTALLDATE") { $installdate = $row["CVAL"]; }
		}
	// The administrator email lives on the lumadmin account, not in CONFIG.
	mysqli_select_db($db, "AUTH") or die( "<h5>Fatal Error</h5>\n\n<p>Unable to access database.\n</p>");
	$uquery = mysqli_query($db, "select EMAIL from USERS where USERNAME = 'lumadmin'");
	if ($urow = mysqli_fetch_assoc($uquery)) {
		if ($urow["EMAIL"] !== null && $urow["EMAIL"] !== "") { $adminemail = $urow["EMAIL"]; }
		}
	// CPUHIST lives in SYSTEM, not AUTH - switch back before querying it.
	mysqli_select_db($db, "SYSTEM") or die( "<h5>Fatal Error</h5>\n\n<p>Unable to access database.\n</p>");
	//$cpuhistquery = mysqli_query($db, "select TIMESTAMP,PCT from CPUHIST order by TIMESTAMP limit 8");
	$cpuhistquery = mysqli_query($db, "select * from (select TIMESTAMP,PCT from CPUHIST order by TIMESTAMP desc limit 9) as sub order by TIMESTAMP asc");
	$memhistquery = mysqli_query($db, "select * from (select TIMESTAMP,PCT from MEMHIST order by TIMESTAMP desc limit 9) as sub order by TIMESTAMP asc");
	$cpumodel = str_replace("\n", "", shell_exec("/usr/bin/cat /proc/cpuinfo | /usr/bin/grep -m 1 'model name' | /usr/bin/sed -e \"s/^.*\\\\: //\""));
	$cpuspeed = str_replace("\n", "",shell_exec("/usr/bin/cat /proc/cpuinfo | /usr/bin/grep -m 1 'MHz' | /usr/bin/sed -e \"s/^.*\\\\: //\""));
	$cpucores = str_replace("\n", "",shell_exec("/usr/bin/cat /proc/cpuinfo | /usr/bin/grep 'processor' | /usr/bin/wc -l"));
	$cpuarch = str_replace("\n", "",shell_exec("/usr/bin/uname -m"));
	$osver = shell_exec("/usr/bin/cat /etc/debian_version");
	$kernel = str_replace("\n", "",shell_exec("/usr/bin/uname -r"));
	$uptime = str_replace("\n", "",shell_exec("/usr/bin/uptime -p | /usr/bin/sed -e 's/up //'"));
	$disks = array_filter(preg_split("/\r\n|\n|\r/",shell_exec("/usr/bin/lsblk | /usr/bin/grep disk | /usr/bin/sed -E 's/^([A-Za-z0-9]+).*$/\\1/'")));
	$ifaces = shell_exec("/usr/sbin/ifconfig | /usr/bin/grep inet | /usr/bin/grep -v 127.0 | /usr/bin/wc -l");
	$disksinfo = array_filter(preg_split("/\r\n|\n|\r/",shell_exec("/usr/bin/lsblk -o MODEL,STATE,VENDOR,TYPE --nodeps | /usr/bin/grep -v VENDOR | /usr/bin/grep -E ' disk$' | /usr/bin/grep -vE '(DVD|CD)' | /usr/bin/sed -E 's/ *disk$//; s/\\s+running /,/g'")));
	// Memory: /proc/meminfo carries the totals; dmidecode carries the
	// per-slot module details (empty when it cannot read the SMBIOS data).
	$meminfo = luminum_meminfo_parse((string) shell_exec("/usr/bin/cat /proc/meminfo"));
	$memslots = luminum_mem_dmidecode_slots((string) shell_exec("sudo -n /usr/sbin/dmidecode -t memory 2>&1"));
	// Devices: sysfs enumerates the PCI and USB buses directly (no
	// lspci/lsusb dependency); the tree groups them Device Manager-style.
	$devpci = shell_exec('for d in /sys/bus/pci/devices/*; do [ -d "$d" ] || continue; printf "%s|%s|%s|%s|%s\n" "$(basename "$d")" "$(cat "$d/class" 2>/dev/null)" "$(cat "$d/vendor" 2>/dev/null)" "$(cat "$d/device" 2>/dev/null)" "$(basename "$(readlink "$d/driver" 2>/dev/null)" 2>/dev/null)"; done');
	$devusb = shell_exec('for d in /sys/bus/usb/devices/*; do n=$(basename "$d"); case "$n" in *:*) continue;; esac; case "$n" in *-*) ;; *) continue;; esac; [ -f "$d/idVendor" ] || continue; printf "%s|%s|%s|%s|%s\n" "$n" "$(cat "$d/idVendor" 2>/dev/null)" "$(cat "$d/idProduct" 2>/dev/null)" "$(cat "$d/manufacturer" 2>/dev/null)" "$(cat "$d/product" 2>/dev/null)"; done');
	$devtree = luminum_devices_build((string) $devpci, (string) $devusb, $cpumodel, $cpucores);
	$devtotal = 0;
	foreach ($devtree as $devlist) {
		$devtotal += count($devlist);
	}
?>

<div class="content">
	<h1>System Information</h1>

	<div class="module-content" style="padding: 0;">
		<div class="tabbar tabbarback">
			<button type="button" class="tabbaritem tabbutton tablink tabbarsel" style="border-right: 1px solid #07f;" onclick="switchTab(event, 'Luminum')">Luminum</button>
			<button type="button" class="tabbaritem tabbutton tablink" style="border-right: 1px solid #07f;" onclick="switchTab(event, 'CPU')">CPU</button>
			<button type="button" class="tabbaritem tabbutton tablink" style="border-right: 1px solid #07f;" onclick="switchTab(event, 'Disks')">Disks</button>
			<button type="button" class="tabbaritem tabbutton tablink" style="border-right: 1px solid #07f;" onclick="switchTab(event, 'Memory')">Memory</button>
			<button type="button" class="tabbaritem tabbutton tablink" style="border-right: 1px solid #07f;" onclick="switchTab(event, 'Devices')">Devices</button>
			<button type="button" class="tabbaritem tabbutton tablink" style="border-right: 1px solid #07f;" onclick="switchTab(event, 'Network')">Network</button>
		</div>

		<div id="Luminum" class="configtab">
			<div class="row" style="margin-left: 20px; margin-top: 20px; margin-bottom: 20px; margin-right: 20px;">
				<div class="column" style="width: 15%; min-width: 220px; pointer-events: none; user-select: none;"><img src="/images/Luminum.png" style="width: 200px; height: 200px;"></div>
				<div class="column" style="width: 40%; text-align: left; padding-right: 20px;">
					<table style="border: 0; width: 650px;">
						<tr><td style="color: #444; background-color: transparent; border: 0;">Luminum Server Version:</td><td style="color: #444; background-color: transparent; border: 0; font-weight: normal;">0.0.1</td></tr>
						<?php print "<tr><td style=\"color: #444; background-color: transparent; border: 0; font-weight: bold;\">Server ID:</td><td style=\"color: #444; background-color: transparent; border: 0; font-weight: normal;\">$serverid</td></tr>\n"; ?>
						<tr><td style="color: #444; background-color: transparent; border: 0;">License:</td><td style="color: #444; background-color: transparent; border: 0; font-weight: normal;">Community</td></tr>
						<tr><td style="color: #444; background-color: transparent; border: 0;">Original Install Date:</td><td style="color: #444; background-color: transparent; border: 0; font-weight: normal;"><?php print $installdate; ?></td></tr>
						<tr><td style="color: #444; background-color: transparent; border: 0;">Admin Contact:</td><td style="color: #444; background-color: transparent; border: 0; font-weight: normal;"><?php if ($adminemail == "NONE") { print "Not Available"; } else { print "<a href=\"mailto:$adminemail\">$adminemail</a>"; } ?></td></tr>
					</table>
				</div>
			</div>
		</div>

		<div id="CPU" class="configtab" style="display: none;">
			<div class="row" style="margin-left: 20px; margin-top: 20px; margin-bottom: 20px; margin-right: 20px;">
				<div class="column" style="width: 15%; min-width: 220px; pointer-events: none; user-select: none;"><img src="/images/cpu.png" style="width: 200px; height: 200px;"></div>
				<div class="column" style="width: 40%; text-align: left; padding-right: 20px;">
					<table style="border: 0;">
						<tr><td style="width: 150px; text-align: left; color: #444; background-color: transparent; border: 0;">Model:</td><td style="font-weight: normal; color: #444; background-color: transparent; border: 0; text-align: left;"><?php print $cpumodel; ?></td></tr>
						<tr><td style="width: 150px; text-align: left; color: #444; background-color: transparent; border: 0;">Speed:</td><td style="font-weight: normal; color: #444; background-color: transparent; border: 0; text-align: left;"><?php print $cpuspeed; ?> MHz</td></tr>
						<tr><td style="width: 150px; text-align: left; color: #444; background-color: transparent; border: 0;">Cores:</td><td style="font-weight: normal; color: #444; background-color: transparent; border: 0; text-align: left;"><?php print $cpucores; ?></td></tr>
						<tr><td style="width: 150px; text-align: left; color: #444; background-color: transparent; border: 0;">Architecture:</td><td style="font-weight: normal; color: #444; background-color: transparent; border: 0; text-align: left;"><?php print $cpuarch; ?></td></tr>
					</table>

					<hr style="width: 97%; margin-top: 20px; margin-bottom: 20px; min-width: 400px;">

					<table style="border: 0;">
						<tr><td style="width: 150px; text-align: left; color: #444; background-color: transparent; border: 0;">Operating System:</td><td style="font-weight: normal; color: #444; background-color: transparent; border: 0; text-align: left;"><?php print "Debian Linux $osver"; ?></td></tr>
						<tr><td style="width: 150px; text-align: left; color: #444; background-color: transparent; border: 0;">Kernel Version:</td><td style="font-weight: normal; color: #444; background-color: transparent; border: 0; text-align: left;"><?php print $kernel; ?></td></tr>
						<tr><td style="width: 150px; text-align: left; color: #444; background-color: transparent; border: 0;">System Uptime:</td><td style="font-weight: normal; color: #444; background-color: transparent; border: 0; text-align: left;"><?php print $uptime; ?></td></tr>
					</table>
				</div>
				<div class="column" style="width: 35%; padding-right: 20px;">
					 <canvas id="cpuchart" style="width: 100%; background-color: #fff; border: 1px solid #aaa; border-radius: 8px; padding: 5px 25px 5px 5px;"></canvas>
				</div>
			</div>
		</div>

		<div id="Disks" class="configtab" style="display: none;">
			<div class="row" style="margin-left: 20px; margin-top: 20px; margin-bottom: 20px; margin-right: 20px;">
				<div class="column" style="width: 15%; min-width: 220px; pointer-events: none; user-select: none;"><img src="/images/drives.png" style="width: 200px; height: 200px;"></div>
				<div class="column" style="width: 25%; text-align: left; padding-right: 5%;">
					<p style="margin-left: 3px;">
					<span style="color: #444;"><b>Connected Drives:</b> &nbsp;&nbsp; <?php print count($disks); ?><span>
					</p>

					<table style="border: 0; margin-top: 25px;">
						<?php
						$dcnt = 0;
						$allparts = array();
						foreach ($disks as $diskval) {
							$dcnt++;
							//$dparts = array_filter(preg_split("/\r\n|\n|\r/",shell_exec("lsblk | /usr/bin/grep $diskval | grep part")));
							$dcap = substr(shell_exec("lsblk -a -o name,size /dev/$diskval | /usr/bin/grep -E '$diskval\s+' | /usr/bin/sed -E 's/$diskval\s+//'"), 0, -1);
							$dparts = array_filter(preg_split("/\r\n|\n|\r/",shell_exec("lsblk -a -o name,size,type,mountpoints /dev/$diskval --list | /usr/bin/grep -vE '(NAME|disk)' | /usr/bin/sed -E 's/part \[SWAP\]/swap/; s/\\s+/ /; s/(K|M|G|T)/\\1B/'")));
							$allparts = array_merge($allparts, $dparts);
							print "\t\t\t\t\t\t<tr><td colspan=\"2\" style=\"text-align: left; color: #444; background-color: transparent; border: 0;\"><u>	Disk $dcnt (/dev/$diskval)</u>:</td></tr>\n";
							$hdinfo = explode(",", isset($disksinfo[$dcnt-1]) ? trim($disksinfo[$dcnt-1]) : "");
							print "\t\t\t\t\t\t<tr><td style=\"text-align: left; color: #444; background-color: transparent; border: 0;\">Manufacturer:</td><td style=\"font-weight: normal; color: #444; background-color: transparent; border: 0; text-align: left;\">" . ($hdinfo[1] ?? "") . "</td></tr>\n";
							print "\t\t\t\t\t\t<tr><td style=\"text-align: left; color: #444; background-color: transparent; border: 0;\">Model:</td><td style=\"font-weight: normal; color: #444; background-color: transparent; border: 0; text-align: left;\">" . ($hdinfo[0] ?? "") . "</td></tr>\n";
							print "\t\t\t\t\t\t<tr><td style=\"text-align: left; color: #444; background-color: transparent; border: 0;\">Capacity:</td><td style=\"font-weight: normal; color: #444; background-color: transparent; border: 0; text-align: left;\">" . $dcap . "B</td></tr>\n";
							print "\t\t\t\t\t\t<tr><td style=\"text-align: left; color: #444; background-color: transparent; border: 0;\">Partitions:</td><td style=\"font-weight: normal; color: #444; background-color: transparent; border: 0; text-align: left;\">" . count($dparts) . "</td></tr>\n";
							foreach ($dparts as $part) {
								$dpstats = array_filter(preg_split('/\s/',$part));
								print "\t\t\t\t\t\t<tr><td style=\"padding-left: 20px; text-align: left; color: #444; background-color: transparent; border: 0;\">/dev/" . $dpstats[0] . ":</td><td style=\"font-weight: normal; color: #444; background-color: transparent; border: 0; text-align: left;\">" . $dpstats[1] . "</td></tr>\n";
								}
							}
						?>
					</table>

				</div>

				<div class="column" style="width: 35%; padding-left: 10%; text-align: right; margin-right: 20px;">
					<div style="width: 100%; min-width: 425px; background-color: #fff; border: 1px solid #aaa; border-radius: 8px; padding: 15px; pointer-events: none; user-select: none;">
						<div style="width: 100%; text-align: center; color: #777; font-size: 13px;"><b>Disk Usage</b></div>
						<table style="border: 0; width: 400px; margin-top: 10px; margin-left: auto; margin-right: auto;">
					<?php
					foreach ($allparts as $part) {
						$dpstats = array_filter(preg_split('/\s/',$part));
						if (isset($dpstats[3]) && $dpstats[2] != "swap") {
							$partused = trim((string) shell_exec("/usr/bin/df -h | /usr/bin/grep -m 1 '\/dev\/" . $dpstats[0] . "' | /usr/bin/awk '{print \$5}' | /usr/bin/sed 's/%//'"));
							if (!is_numeric($partused)) {
								// df -h only lists mounted filesystems; a partition
								// with no df entry has no usage to display.
								print "<tr><td style=\"width: 200px; height: 30px; text-align: left; color: #777; background-color: transparent; border: 0; padding-bottom: 20px;\"><b>/dev/" . $dpstats[0] . ":</b></td><td style=\"text-align: left; background-color: transparent; width: 70%; border: 0; color: #777; font-weight: normal;\">Not mounted</td></tr>\n";
								}
							else {
							if ($partused < 50) { $pctbg = "#2d7d3c"; }
							else if ($partused >= 50 && $partused < 75) { $pctbg = "#d4bc08"; }
							else if ($partused > 75) { $pctbg = "#91110a"; }
							print "<tr><td style=\"width: 200px; height: 30px; text-align: left; color: #777; background-color: transparent; border: 0; padding-bottom: 20px;\"><b>/dev/" . $dpstats[0] . ":</b></td><td style=\"text-align: left; background-color: transparent; width: 70%; border: 0;\"><div style=\"border: 1px solid #aaa; border-radius: 5px; width: 100%; height: 25px; background-color: #ccc; text-align: left; margin-bottom: -20px;\"><div style=\"height: 100%; width: " . $partused . "%; background-color: " . $pctbg . "; border-radius: 5px; margin-bottom: 0;\"><div style=\"width: 100%; padding-top: 3px; text-align: center; color: #fff;\">" . $partused . "%</div></div></div><br><span style=\"color: #777; font-size: 12px; font-weight: normal;\">" . preg_replace('/(K|M|G|T)B/',"",$dpstats[1]) * ($partused / 100) . preg_replace('/\d+\.?\d+?/',"",$dpstats[1]) . " used of " . $dpstats[1] . "</span></td></tr>\n";
							//print "<tr><td style=\"width: 200px; text-align: left; color: #777; background-color: transparent; border: 0;\"></td><td style=\"width: 200px; font-size: 12px; text-align: left; color: #777; background-color: transparent; border: 0;\">Used: " . preg_replace('/(K|M|G|T)B/',"",$dpstats[1]) * ($partused / 100) . preg_replace('/\d+\.?\d+?/',"",$dpstats[1]) . " of " . $dpstats[1] . "</td></tr>\n";
							}
							}
						elseif ($dpstats[2] == "swap") {
							print "<tr><td style=\"width: 200px; height: 30px; text-align: left; color: #777; background-color: transparent; border: 0;\"><b>/dev/" . $dpstats[0] . ":</b></td><td style=\"background-color: transparent; width: 70%; border: 0; color: #777; font-weight: normal; text-align: left;\">Swap (" . $dpstats[1] . ")</td></tr>\n";
							}
						}
					?>
						</table>
					</div>
				</div>
			</div>
		</div>

		<div id="Memory" class="configtab" style="display: none;">
			<div class="row" style="margin-left: 20px; margin-top: 20px; margin-bottom: 20px; margin-right: 20px;">
				<div class="column" style="width: 15%; min-width: 220px; pointer-events: none; user-select: none;"><img src="/images/ram.png" style="width: 200px; height: 200px;"></div>
				<div class="column" style="width: 40%; text-align: left; padding-right: 20px;">
					<table style="border: 0;">
						<tr><td style="width: 150px; text-align: left; color: #444; background-color: transparent; border: 0;">Total Memory:</td><td style="font-weight: normal; color: #444; background-color: transparent; border: 0; text-align: left;"><?php print luminum_mem_kb_human($meminfo["MemTotal"]); ?></td></tr>
						<tr><td style="width: 150px; text-align: left; color: #444; background-color: transparent; border: 0;">Used:</td><td style="font-weight: normal; color: #444; background-color: transparent; border: 0; text-align: left;"><?php print luminum_mem_kb_human($meminfo["MemTotal"] - $meminfo["MemAvailable"]); ?></td></tr>
						<tr><td style="width: 150px; text-align: left; color: #444; background-color: transparent; border: 0;">Free:</td><td style="font-weight: normal; color: #444; background-color: transparent; border: 0; text-align: left;"><?php print luminum_mem_kb_human($meminfo["MemFree"]); ?></td></tr>
						<tr><td style="width: 150px; text-align: left; color: #444; background-color: transparent; border: 0;">Available:</td><td style="font-weight: normal; color: #444; background-color: transparent; border: 0; text-align: left;"><?php print luminum_mem_kb_human($meminfo["MemAvailable"]); ?></td></tr>
						<tr><td style="width: 150px; text-align: left; color: #444; background-color: transparent; border: 0;">Swap Total:</td><td style="font-weight: normal; color: #444; background-color: transparent; border: 0; text-align: left;"><?php print luminum_mem_kb_human($meminfo["SwapTotal"]); ?></td></tr>
						<tr><td style="width: 150px; text-align: left; color: #444; background-color: transparent; border: 0;">Swap Used:</td><td style="font-weight: normal; color: #444; background-color: transparent; border: 0; text-align: left;"><?php print luminum_mem_kb_human($meminfo["SwapTotal"] - $meminfo["SwapFree"]); ?></td></tr>
						<tr><td style="width: 150px; text-align: left; color: #444; background-color: transparent; border: 0;">Swap Free:</td><td style="font-weight: normal; color: #444; background-color: transparent; border: 0; text-align: left;"><?php print luminum_mem_kb_human($meminfo["SwapFree"]); ?></td></tr>
					</table>

					<hr style="width: 97%; margin-top: 20px; margin-bottom: 20px; min-width: 400px;">

					<table style="border: 0;">
						<?php if (empty($memslots)) { ?>
						<tr><td style="width: 150px; text-align: left; color: #444; background-color: transparent; border: 0;">Module Details:</td><td style="font-weight: normal; color: #444; background-color: transparent; border: 0; text-align: left;">Not available</td></tr>
						<?php } else { $scnt = 0; foreach ($memslots as $slot) { $scnt++; $slotlabel = "Slot $scnt"; if ($slot["Locator"] !== "") { $slotlabel .= " (" . $slot["Locator"] . ")"; } ?>
						<tr><td colspan="2" style="text-align: left; color: #444; background-color: transparent; border: 0;"><u><?php print $slotlabel; ?></u>:</td></tr>
						<?php if (!$slot["installed"]) { ?>
						<tr><td colspan="2" style="padding-left: 20px; text-align: left; color: #444; background-color: transparent; border: 0;">No Module Installed</td></tr>
						<?php } else { ?>
						<tr><td style="width: 150px; text-align: left; color: #444; background-color: transparent; border: 0;">Size:</td><td style="font-weight: normal; color: #444; background-color: transparent; border: 0; text-align: left;"><?php print $slot["Size"] !== "" ? $slot["Size"] : "Unknown"; ?></td></tr>
						<tr><td style="width: 150px; text-align: left; color: #444; background-color: transparent; border: 0;">Type:</td><td style="font-weight: normal; color: #444; background-color: transparent; border: 0; text-align: left;"><?php print $slot["Type"] !== "" ? $slot["Type"] : "Unknown"; ?></td></tr>
						<tr><td style="width: 150px; text-align: left; color: #444; background-color: transparent; border: 0;">Speed:</td><td style="font-weight: normal; color: #444; background-color: transparent; border: 0; text-align: left;"><?php print $slot["Speed"] !== "" ? $slot["Speed"] : "Unknown"; ?></td></tr>
						<tr><td style="width: 150px; text-align: left; color: #444; background-color: transparent; border: 0;">Manufacturer:</td><td style="font-weight: normal; color: #444; background-color: transparent; border: 0; text-align: left;"><?php print $slot["Manufacturer"] !== "" ? $slot["Manufacturer"] : "Unknown"; ?></td></tr>
						<tr><td style="width: 150px; text-align: left; color: #444; background-color: transparent; border: 0;">Part Number:</td><td style="font-weight: normal; color: #444; background-color: transparent; border: 0; text-align: left;"><?php print $slot["Part Number"] !== "" ? $slot["Part Number"] : "Unknown"; ?></td></tr>
						<?php } } } ?>
					</table>
				</div>
				<div class="column" style="width: 35%; padding-right: 20px;">
					<canvas id="memchart" style="width: 100%; background-color: #fff; border: 1px solid #aaa; border-radius: 8px; padding: 5px 25px 5px 5px;"></canvas>
				</div>
			</div>
		</div>

		<div id="Devices" class="configtab" style="display: none;">
			<div class="row" style="margin-left: 20px; margin-top: 20px; margin-bottom: 20px; margin-right: 20px;">
				<div class="column" style="width: 15%; min-width: 220px; pointer-events: none; user-select: none;"><img src="/images/devices.png" style="width: 200px; height: 200px;"></div>
				<div class="column" style="width: 70%; text-align: left; padding-right: 5%;">
					<p style="margin-left: 3px;">
					<span style="color: #444;"><b>Devices found:</b> &nbsp;&nbsp; <?php print $devtotal; ?></span>
					</p>

					<div style="margin-top: 25px;">
						<?php if (empty($devtree)) { ?>
						<p style="color: #444;">No devices found.</p>
						<?php } else { $dcid = 0; foreach ($devtree as $cat => $devs) { $dcid++; $cid = "devcat$dcid"; ?>
						<div style="padding: 4px 0; cursor: pointer; color: #444;" onclick="toggleDeviceCat('<?php print $cid; ?>')">
							<span id="<?php print $cid; ?>arrow" style="display: inline-block; width: 14px; color: #777;">&#9662;</span><b><?php print $cat; ?></b> <span style="color: #777; font-size: 12px;">(<?php print count($devs); ?>)</span>
						</div>
						<div id="<?php print $cid; ?>" style="margin-bottom: 6px;">
							<?php foreach ($devs as $dev) { ?>
							<div style="padding-left: 28px; padding-top: 2px; padding-bottom: 2px; color: #444;">
								<span style="color: #444;"><?php print $dev["label"]; ?></span>
								<?php if ($dev["detail"] !== "") { ?> <span style="color: #777; font-size: 12px;"><?php print $dev["detail"]; ?></span><?php } ?>
							</div>
							<?php } ?>
						</div>
						<?php } } ?>
					</div>
				</div>
			</div>
		</div>

		<div id="Network" class="configtab" style="display: none;">
			<div class="row" style="margin-left: 20px; margin-top: 20px; margin-bottom: 20px; margin-right: 20px;">
				<div class="column" style="width: 15%; min-width: 220px; pointer-events: none; user-select: none;"><img src="/images/network.png" style="width: 200px; height: 200px;"></div>
				<div class="column" style="width: 25%; text-align: left; padding-right: 5%;">
				</div>
			</div>
		</div>
	</div>

<script src="/layout/Chart.js"></script>

<script>
<?php
	$timevals = "";
	$cpuvals = "";
	while ($row = mysqli_fetch_assoc($cpuhistquery)) {
		$tentry = $row["TIMESTAMP"];
		$tentry = preg_replace('/\d\d\d\d-\d\d-\d\d (\d\d:\d\d):\d\d/',"$1",$tentry);
		$cuentry = $row["PCT"];
		$timevals .= "'$tentry',";
		$cpuvals .= "$cuentry,";
		}
	$timevals = substr($timevals, 0, -1);
	$cpuvals = substr($cpuvals, 0, -1);
	print "const xValues = [$timevals];\n";
	print "const yValues = [$cpuvals];\n\n";
	?>

new Chart("cpuchart", {
	type: "line",
	data: {
		labels: xValues,
		datasets: [{
			fill: false,
			lineTension: 0,
			backgroundColor: "rgba(200,100,100,0.1)",
			borderColor: "rgba(200,100,100,1.0)",
			data: yValues
			}]
		},
	options: {
		legend: { display: false },
		scales: { yAxes: [{ scaleLabel: { display: true, labelString: '% Utilization' }, ticks: { min: 0, max:100 } }],
			xAxes: [{ scaleLabel: { display: true, labelString: 'Time' } }],
			},
		title: {
			display: true,
			text: "CPU Usage History"
			},
		},
	});
</script>

<script>
<?php
	$memxvals = "";
	$memyvals = "";
	while ($row = mysqli_fetch_assoc($memhistquery)) {
		$tentry = $row["TIMESTAMP"];
		$tentry = preg_replace('/\d\d\d\d-\d\d-\d\d (\d\d:\d\d):\d\d/',"$1",$tentry);
		$muentry = $row["PCT"];
		$memxvals .= "'$tentry',";
		$memyvals .= "$muentry,";
		}
	$memxvals = substr($memxvals, 0, -1);
	$memyvals = substr($memyvals, 0, -1);
	print "const memXValues = [$memxvals];\n";
	print "const memYValues = [$memyvals];\n\n";
	?>

new Chart("memchart", {
	type: "line",
	data: {
		labels: memXValues,
		datasets: [{
			fill: false,
			lineTension: 0,
			backgroundColor: "rgba(100,150,220,0.1)",
			borderColor: "rgba(100,150,220,1.0)",
			data: memYValues
			}]
		},
	options: {
		legend: { display: false },
		scales: { yAxes: [{ scaleLabel: { display: true, labelString: '% Utilization' }, ticks: { min: 0, max:100 } }],
			xAxes: [{ scaleLabel: { display: true, labelString: 'Time' } }],
			},
		title: {
			display: true,
			text: "Memory Usage History"
			},
		},
	});
</script>

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

function toggleDeviceCat(cid) {
	var items = document.getElementById(cid);
	var arrow = document.getElementById(cid + "arrow");
	if (items.style.display === "none") {
		items.style.display = "block";
		arrow.innerHTML = "&#9662;";
		}
	else {
		items.style.display = "none";
		arrow.innerHTML = "&#9656;";
		}
	}
</script>

<?php } ?>
