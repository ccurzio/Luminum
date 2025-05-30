<?php
$instdir = exec("/usr/bin/grep instdir /opt/Luminum/LuminumServer/config/console.conf | /usr/bin/sed -e 's/^instdir.*\= //'");
$dbuser = exec("/usr/bin/grep dbuser /opt/Luminum/LuminumServer/config/console.conf | /usr/bin/sed -e 's/^dbuser.*\= //'");
$dbpass = exec("/usr/bin/grep dbpass /opt/Luminum/LuminumServer/config/console.conf | /usr/bin/sed -e 's/^dbpass.*\= //'");
$db = new mysqli("localhost", $dbuser, $dbpass, '', 0, "/var/run/mysqld/mysqld.sock");
mysqli_select_db($db, "AUTH") or die( "<h5>Fatal Error</h5>\n\n<p>Unable to access database.\n</p>");

date_default_timezone_set("America/New_York");

if (!isset($_SESSION)) { session_start(); }

if (!isset($_SESSION['SID'])) {
	print "<html lang=\"en\">\n\n";
	print "<head>\n";
	print "<meta http-equiv=\"refresh\" content=\"0; url=/index.php\">\n";
	print "</head>\n\n";
	print "<body>\n<p>\nRedirecting...\n</p>\n</body>";
	print "</html>";
	exit;
	}

$userquery = mysqli_query($db, "select ROLE from USERS where ENABLED = 1 and ID = (select ID from SESSION where SID = '" . $_SESSION["SID"] . "')");
$userinfo = $userquery->fetch_assoc();

$acctrole = $userinfo["ROLE"];

?>
<!DOCTYPE html>
<html lang="en">
<head>
	<meta charset="UTF-8">
	<title>Luminum (luminum.accipiter.org)</title>
	<meta name="viewport" content="width=device-width, initial-scale=1">
	<link rel="stylesheet" href="layout/default.css">
	<style type="text/css" media="screen">
		#leditor {
			position: relative;
			width: 600px;
			height: 400px;
			}
		#meditor {
			position: relative;
			width: 600px;
			height: 400px;
			}
		#weditor {
			position: relative;
			width: 600px;
			height: 400px;
			}
	</style>
</head>

<body>

<div id="overlay">
	<div style="width: 700px; margin-left: auto; margin-right: auto; margin-top: 12%; background-color: white; border-radius: 8px; padding: 20px; box-shadow: 5px 5px 10px rgba(0,0,0,0.5); text-align: center;">
		<span style="font-weight: bold; font-size: 20px;">Session Timeout</span><br>
		<div style="width: 100%; margin-left: auto; margin-right: auto; text-align: center;">
		</div>

		<div style="width: 100%; margin-left: auto; margin-right: auto; text-align: center;">
			Your session is about to time out due to inactivity, at which point you will automatically be logged out. You may click "extend" to renew your session,
			or you can manually log out.
		</div>
		<div style="margin-top: 20px; margin-left: auto; margin-right: auto; text-align: center;">
			<button class="formgo" id="extend" value="extend" style="margin-left: 0; margin-right: 0;">Extend</button> <button class="formgo" id="logout" value="logout" style="margin-left: 0; margin-right: 0;">Log Out</button>
		</div>
	</div>
</div>

<div class="header" style="justify-content: space-between;">
	<img src="images/logo-light.png" alt="Luminum" class="logo-img" style="margin-bottom: 4px;">
	<div style="width: 1200px;">
		<div class="dropdown">
			<a href="/index.php">
					<button class="dropbtn" style="cursor: pointer;">
						<img src="icons/home.png" class="icon">
						Home
					</button>
				</a>
			</div>
			<div class="dropdown">
				<a href="/investigate.php">
					<button class="dropbtn" style="cursor: pointer;">
						<img src="icons/investigate.png" class="icon">
						Investigate
					</button>
				</a>
			</div>

			<div class="dropdown">
				<button class="dropbtn">
					<img src="icons/modules.png" class="icon">
					Lumys
			</button>
			<div class="dropdown-content">
				<?php
				if (isset($acctrole) && $acctrole == "1") {
					print "<a href=\"/modules.php\">Management</a>\n";
					print "<div class=\"dropdown-divider\" style=\"width: 200px;\"></div>\n";
					}
				print "<a href=\"/modules.php?view=summary\">Summary</a>\n";
				mysqli_select_db($db, "SYSTEM") or die( "<h5>Fatal Error</h5>\n\n<p>Unable to access database.\n</p>");
				$lumyquery = mysqli_query($db, "select CVAL from CONFIG where CKEY = 'ENLUMYS'");
				$lumyinfo = $lumyquery->fetch_assoc();
				$lumys = explode(',', $lumyinfo["CVAL"]);
				sort($lumys);

				foreach ($lumys as $lumy) {
					print "<a href=\"/modules.php?view=$lumy\">" . ucfirst($lumy) . "</a>\n";
					}
				?>
			</div>
		</div>

		<div class="dropdown">
			<button class="dropbtn">
				<img src="icons/administration.png" class="icon">
				Administration
			</button>
			<div class="dropdown-content">
				<div class="submenu">
					<a href="#" class="submenu-link" style="cursor: default;">Endpoints <span class="arrow" style="margin-left: 57%;">▸</span></a>
					<div class="submenu-content">
						<a href="/index.php?view=clientstatus">Client Status</a>
						<a href="/index.php?view=missing">Missing Clients</a>
					</div>
				</div>
				<div class="submenu">
					<a href="#" class="submenu-link" style="cursor: default;">Actions <span class="arrow" style="margin-left: 66%;">▸</span></a>
					<div class="submenu-content">
						<a href="/index.php?view=actions">Scheduled Actions</a>
						<a href="/index.php?view=actionhistory">Action History</a>
					</div>
				</div>
				<div class="submenu">
					<a href="#" class="submenu-link" style="cursor: default;">Content <span class="arrow" style="margin-left: 65%;">▸</span></a>
					<div class="submenu-content">
						<a href="/index.php?view=packages">Packages</a>
						<a href="/index.php?view=sensors">Sensors</a>
						<a href="/index.php?view=csets">Content Sets</a>
					</div>
				</div>
				<a href="/index.php?view=savedqueries">Saved Queries</a>
				<a href="/index.php?view=cgroups">Computer Groups</a>
				<a href="/index.php?view=ugroups">User Groups</a>
			</div>
		</div>

		<div class="dropdown">
			<button class="dropbtn">
				<img src="icons/system.png" class="icon">
				System
			</button>
			<div class="dropdown-content">
				<?php
				if (isset($acctrole) && $acctrole <= "2") {
					print "<a href=\"/index.php?view=sysinfo\">System Information</a>\n";
					print "<div class=\"dropdown-divider\"></div>\n";
					}

				if (isset($acctrole) && $acctrole == "1") {
					print "<div class=\"submenu\" style=\"justify-content: space-between;\">\n";
					print "<a href=\"#\" class=\"submenu-link\" style=\"cursor: default;\">Configuration<span class=\"arrow\" style=\"margin-left: 48%;\">▸</span></a>\n";
					print "<div class=\"submenu-content\">\n";
					print "<a href=\"/config.php?view=options\">Server Options</a>\n";
					print "<a href=\"/config.php?view=network\">Network</a>\n";
					print "<a href=\"/config.php?view=certs\">Certificates</a>\n";
					print "<a href=\"/config.php?view=auth\">Authentication</a>\n";
					print "</div>\n";
					print "</div>\n";
					print "<div class=\"submenu\">\n";
					print "<a href=\"#\" class=\"submenu-link\" style=\"cursor: default;\">Maintenance <span class=\"arrow\" style=\"margin-left: 48%;\">▸</span></a>\n";
					print "<div class=\"submenu-content\">\n";
					print "<a href=\"/maintenance.php?view=diagnostics\">Diagnostics</a>\n";
					print "<a href=\"/maintenance.php?view=updates\">System Update</a>\n";
					print "<a href=\"/maintenance.php?view=downtime\">Outage Management</a>\n";
					print "<a href=\"/maintenance.php?view=os\">Operating System</a>\n";
					print "<a href=\"/maintenance.php?view=services\">Back-End Services</a>\n";
					print "<a href=\"/maintenance.php?view=logs\">System Logs</a>\n";
					print "</div>\n";
					print "</div>\n";
					print "<a href=\"/config.php?view=clients\">Client Management</a>\n";
					print "<a href=\"/index.php?view=users\">User Accounts</a>\n";
					}
				?>
			</div>
		</div>
	</div>
	<div class="user-menu" style="height: 100%;">
		<button class="user-button" style="width: 175px; padding-bottom: 15px;"><?php print $_SESSION["NAME"]; ?> <span style="margin-left: 2px; font-size: 18px;">▾</span></button>
		<div class="user-dropdown">
			<a href="/user.php">Account</a>
			<a href="/user.php?view=prefs">Preferences</a>
			<a href="/index.php?logout=1">Logout</a>
		</div>
	</div>
</div>


