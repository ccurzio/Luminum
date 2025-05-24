<?php

if ($acctrole > 1) {
	print "<div class=\"content\">\n";
	print "<h1 style=\"color: red\">Access Denied</h1>\n";
	}
else {
	mysqli_select_db($db, "SYSTEM") or die( "<h5>Fatal Error</h5>\n\n<p>Unable to access database.\n</p>");
	$confquery = mysqli_query($db, "select CKEY,CVAL from CONFIG where CKEY = 'SID' or CKEY = 'INSTALLDATE'");
	while($row = mysqli_fetch_assoc($confquery)) {
		if ($row["CKEY"] == "SID") { $serverid = $row["CVAL"]; }
		else if ($row["CKEY"] == "INSTALLDATE") { $installdate = $row["CVAL"]; }
		}
	$cpuhistquery = mysqli_query($db, "select TIMESTAMP,PCT from CPUHIST order by TIMESTAMP limit 12");
	$cpumodel = str_replace("\n", "", shell_exec("/usr/bin/cat /proc/cpuinfo | /usr/bin/grep -m 1 'model name' | /usr/bin/sed -e \"s/^.*\\\\: //\""));
	$cpuspeed = str_replace("\n", "",shell_exec("/usr/bin/cat /proc/cpuinfo | /usr/bin/grep -m 1 'MHz' | /usr/bin/sed -e \"s/^.*\\\\: //\""));
	$cpucores = str_replace("\n", "",shell_exec("/usr/bin/cat /proc/cpuinfo | /usr/bin/grep 'processor' | /usr/bin/wc -l"));
	$cpuarch = str_replace("\n", "",shell_exec("/usr/bin/uname -m"));
	$osver = shell_exec("/usr/bin/cat /etc/debian_version");
	$kernel = str_replace("\n", "",shell_exec("/usr/bin/uname -r"));
	$uptime = str_replace("\n", "",shell_exec("/usr/bin/uptime -p | /usr/bin/sed -e 's/up //'"));
	$disks = array_filter(preg_split("/\r\n|\n|\r/",shell_exec("/usr/bin/lsblk | /usr/bin/grep disk | /usr/bin/sed -E 's/^([A-Za-z0-9]+).*$/\\1/'")));
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
			<?php print "<tr><td style=\"width: 50%; color: #444; background-color: transparent; border: 0; font-weight: bold;\">Server ID:</td><td style=\"width: 50%; color: #444; background-color: transparent; border: 0; font-weight: normal;\">$serverid</td></tr>\n"; ?>
			<tr><td style="width: 50%; color: #444; background-color: transparent; border: 0;">License:</td><td style="width: 50%; color: #444; background-color: transparent; border: 0; font-weight: normal;">Community</td></tr>
			<tr><td style="width: 50%; color: #444; background-color: transparent; border: 0;">Original Install Date:</td><td style="width: 50%; color: #444; background-color: transparent; border: 0; font-weight: normal;"><?php print $installdate; ?></td></tr>
			</table>
		</div>

		<div id="CPU" class="configtab" style="display: none;">
			<div class="row" style="margin-left: 20px; margin-top: 20px; margin-bottom: 20px; margin-right: 20px;">
				<div class="column" style="width: 15%; min-width: 220px;"><img src="/images/cpu.png" style="width: 200px; height: 200px;"></div>
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
				<div class="column" style="width: 15%; min-width: 220px;"><img src="/images/drives.png" style="width: 200px; height: 200px;"></div>
				<div class="column" style="width: 25%; text-align: left; padding-right: 5%;">
					<p style="margin-left: 3px;">
					<span style="color: #444;"><b>Connected Drives:</b> &nbsp;&nbsp; <?php print count($disks); ?><span>
					</p>

					<table style="border: 0; margin-top: 25px;">
						<?php
						$dcnt = 0;
						foreach ($disks as $diskval) {
							$dcnt++;
							//$dparts = array_filter(preg_split("/\r\n|\n|\r/",shell_exec("lsblk | /usr/bin/grep $diskval | grep part")));
							$dcap = substr(shell_exec("lsblk -a -o name,size /dev/$diskval | /usr/bin/grep -E '$diskval\s+' | /usr/bin/sed -E 's/$diskval\s+//'"), 0, -1);
							$dparts = array_filter(preg_split("/\r\n|\n|\r/",shell_exec("lsblk -a -o name,size,type,mountpoints /dev/$diskval --list | /usr/bin/grep -vE '(NAME|disk)' | /usr/bin/sed -E 's/part \[SWAP\]/swap/; s/\\s+/ /; s/(K|M|G|T)/\\1B/'")));
							print "\t\t\t\t\t\t<tr><td colspan=\"2\" style=\"text-align: left; color: #444; background-color: transparent; border: 0;\"><u>	Disk $dcnt (/dev/$diskval)</u>:</td></tr>\n";
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
					<div style="width: 100%; min-width: 425px; background-color: #fff; border: 1px solid #aaa; border-radius: 8px; padding: 15px;">
						<div style="width: 100%; text-align: center; color: #777; font-size: 13px;"><b>Disk Usage</b></div>
						<table style="border: 0; width: 400px; margin-top: 10px; margin-left: auto; margin-right: auto;">
					<?php
					foreach ($dparts as $part) {
						$dpstats = array_filter(preg_split('/\s/',$part));
						if (isset($dpstats[3]) && $dpstats[2] != "swap") {
							$partused = substr(shell_exec("/usr/bin/df -h | /usr/bin/grep '\/dev\/" . $dpstats[0] . "' | /usr/bin/sed -E 's/^.*(1?[0-9][0-9])\%.*$/\\1/'"), 0, -1);
							if ($partused < 50) { $pctbg = "#2d7d3c"; }
							else if ($partused >= 50 && $dcap < 75) { $pctbg = "#d4bc08"; }
							else if ($partused > 75) { $pctbg = "#91110a"; }
							print "<tr><td style=\"width: 200px; height: 30px; text-align: left; color: #777; background-color: transparent; border: 0; padding-bottom: 20px;\"><b>/dev/" . $dpstats[0] . ":</b></td><td style=\"text-align: left; background-color: transparent; width: 70%; border: 0;\"><div style=\"border: 1px solid #aaa; border-radius: 5px; width: 100%; height: 25px; background-color: #ccc; text-align: left; margin-bottom: -20px;\"><div style=\"height: 100%; width: " . $partused . "%; background-color: " . $pctbg . "; border-radius: 5px; margin-bottom: 0;\"><div style=\"width: 100%; padding-top: 3px; text-align: center; color: #fff;\">" . $partused . "%</div></div></div><br><span style=\"color: #777; font-size: 12px; font-weight: normal;\">" . preg_replace('/(K|M|G|T)B/',"",$dpstats[1]) * ($partused / 100) . preg_replace('/\d+\.?\d+?/',"",$dpstats[1]) . " used of " . $dpstats[1] . "</span></td></tr>\n";
							//print "<tr><td style=\"width: 200px; text-align: left; color: #777; background-color: transparent; border: 0;\"></td><td style=\"width: 200px; font-size: 12px; text-align: left; color: #777; background-color: transparent; border: 0;\">Used: " . preg_replace('/(K|M|G|T)B/',"",$dpstats[1]) * ($partused / 100) . preg_replace('/\d+\.?\d+?/',"",$dpstats[1]) . " of " . $dpstats[1] . "</td></tr>\n";
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
			<img src="/images/ram.png" style="width: 200px; height: 200px;">
		</div>

		<div id="Network" class="configtab" style="display: none;">
			<img src="/images/network.png" style="width: 200px; height: 200px;">
			<table style="border: 0; margin-top: 20px; margin-left: 8px;">
			<tr><td style="text-align: left; background-color: transparent; border: 0;">Physical Interfaces:</td><td style="font-weight: normal; background-color: transparent; border: 0;text-align: right;"><?php print $ifaces; ?></td></tr>
			</table>
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
			backgroundColor: "rgba(200,100,100,1.0)",
			borderColor: "rgba(200,100,100,0.1)",
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
