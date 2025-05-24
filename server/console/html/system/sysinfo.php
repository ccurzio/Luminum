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
	$cpumodel = shell_exec("/usr/bin/cat /proc/cpuinfo | /usr/bin/grep -m 1 'model name' | /usr/bin/sed -e \"s/^.*\\\\: //\"");
	$cpuspeed = shell_exec("/usr/bin/cat /proc/cpuinfo | /usr/bin/grep -m 1 'MHz' | /usr/bin/sed -e \"s/^.*\\\\: //\"");
	$cpucores = shell_exec("/usr/bin/cat /proc/cpuinfo | /usr/bin/grep 'processor' | /usr/bin/wc -l");
	$cpuarch = shell_exec("/usr/bin/uname -m");
	$osver = shell_exec("/usr/bin/cat /etc/debian_version");
	$kernel = shell_exec("/usr/bin/uname -r");
	$uptime = shell_exec("/usr/bin/uptime -p | /usr/bin/sed -e 's/up //'");
	$disks = array_filter(preg_split("/\r\n|\n|\r/",shell_exec("/usr/bin/lsblk | /usr/bin/grep disk | /usr/bin/sed -E 's/^([A-Za-z0-9]+).*$/\/dev\/\1/'")));
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
			<?php print "<tr><td style=\"width: 50%; color: #444; background-color: transparent; border: 0; font-weight: bold;\">Server ID:</td><td style=\"width: 50%; color: #444; background-color: transparent; border: 0; font-weight: normal;\">$serverid</td></tr>\n"; ?>
			<tr><td style="width: 50%; color: #444; background-color: transparent; border: 0;">License:</td><td style="width: 50%; color: #444; background-color: transparent; border: 0; font-weight: normal;">Community</td></tr>
			<tr><td style="width: 50%; color: #444; background-color: transparent; border: 0;">Original Install Date:</td><td style="width: 50%; color: #444; background-color: transparent; border: 0; font-weight: normal;"><?php print $installdate; ?></td></tr>
			</table>
		</div>

		<div id="CPU" class="configtab" style="display: none;">
			<div class="row"style="margin-left: 20px; margin-top: 20px; margin-bottom: 20px; margin-right: 20px;">
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
			<img src="/images/drives.png" style="width: 200px; height: 200px;">
			<table style="width: 20%; border: 0; margin-left: auto; margin-right: auto; margin-top: 15px; margin-bottom: 15px;">
			<tr><td style="text-align: left; background-color: transparent; border: 0;">Connected Drives:</td><td style="font-weight: normal; background-color: transparent; border: 0; text-align: right;"><?php print count($disks); ?></td></tr>
			</table>

			<table style="width: 20%; border: 0; margin-left: auto; margin-right: auto; margin-top: 15px; margin-bottom: 15px;">
			<tr><td style="text-align: left; background-color: transparent; border: 0;">Capacity:</td><td style="font-weight: normal; background-color: transparent; border: 0; text-align: right;"><?php print $diskarray[1]; ?></td></tr>
			<tr><td style="text-align: left; background-color: transparent; border: 0;">Used Space:</td><td style="font-weight: normal; background-color: transparent; border: 0; text-align: right;"><?php print $diskarray[2]; ?></td></tr>
			<tr><td style="text-align: left; background-color: transparent; border: 0;">Free Space:</td><td style="font-weight: normal; background-color: transparent; border: 0; text-align: right;"><?php print $diskarray[3]; ?></td></tr>
			</table>
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
