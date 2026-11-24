<?php
require_once __DIR__ . '/db.php';
require_once __DIR__ . '/csrf.php';
$instdir = luminum_console_conf('instdir');
$hostname = luminum_console_conf('hostname');
if ($hostname === '') { $hostname = explode(':', $_SERVER['HTTP_HOST'] ?? '')[0]; }
$db = luminum_db();
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

// Inactivity timeout: bounce expired sessions to the login page, otherwise
// refresh the deadline (a page load is user activity).
require_once __DIR__ . '/session.php';
luminum_session_gate($db);

$userquery = mysqli_query($db, "select ROLE from USERS where ENABLED = 1 and ID = (select ID from SESSION where SID = '" . $_SESSION["SID"] . "')");
$userinfo = $userquery->fetch_assoc();
$acctrole = $userinfo["ROLE"];

$iquery = mysqli_query($db, "select CVAL from SYSTEM.CONFIG where CKEY = 'INVESTIGATE'");
$invinfo = $iquery->fetch_assoc();
$ienabled = $invinfo["CVAL"];
?>
<!DOCTYPE html>
<html lang="en">
<head>
	<meta charset="UTF-8">
	<title>Luminum (<?php print $hostname; ?>)</title>
	<meta name="viewport" content="width=device-width, initial-scale=1">
	<!-- The session's CSRF token: the console JS (layout/session.js,
	     layout/querybuilder.js) sends it as the X-CSRF-Token header on
	     every state-changing API call (/api/touch.php, /api/commands.php).
	     HTML forms carry the same token in a hidden input
	     (luminum_csrf_field in layout/csrf.php). -->
	<meta name="csrf-token" content="<?php print luminum_csrf_token(); ?>">
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

<!-- Full-screen dim + forced-focus popup. The content is filled in by
     LuminumOverlay.show() in layout/session.js; hidden until then. -->
<div id="overlay">
	<div class="overlay-popup">
		<span id="overlay-title" style="font-weight: bold; font-size: 20px;"></span><br>
		<div id="overlay-message" style="margin-top: 15px;"></div>
		<div id="overlay-buttons" style="margin-top: 20px;"></div>
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
			<button class="dropbtn">
				<img src="icons/modules.png" class="icon">
				Lumys
			</button>
			<div class="dropdown-content">
				<?php
				if (isset($acctrole) && $acctrole == "1") {
					print "<a href=\"/modules.php\">Lumy Management</a>\n";
					print "<div class=\"dropdown-divider\" style=\"width: 200px;\"></div>\n";
					}
				//print "<a href=\"/modules.php?view=query\">Query</a>\n";
				print "<div class=\"submenu\">\n";
				print "<a href=\"#\" class=\"submenu-link\" style=\"cursor: default;\">Query <span class=\"arrow\">▸</span></a>\n";
				print "<div class=\"submenu-content\">\n";
				print "\t<a href=\"/modules.php?view=query\">Query Builder</a>\n";
				print "\t<a href=\"/modules.php?view=query&tab=saved\">Saved Queries</a>\n";
				print "\t<a href=\"/index.php?view=queryhistory\">Query History</a>\n";
				print "</div>\n";
				print "</div>\n";
				print "<a href=\"/modules.php?view=convey\">Convey</a>\n";
				mysqli_select_db($db, "SYSTEM") or die( "<h5>Fatal Error</h5>\n\n<p>Unable to access database.\n</p>");
				$lumyquery = mysqli_query($db, "select CVAL from CONFIG where CKEY = 'ENLUMYS'");
				$lumyinfo = $lumyquery ? $lumyquery->fetch_assoc() : null;
				$lumys = ($lumyinfo && $lumyinfo["CVAL"] !== '') ? explode(',', $lumyinfo["CVAL"]) : [];
				sort($lumys);

				foreach ($lumys as $lumy) {
					print "<a href=\"/modules.php?view=$lumy\">" . ucfirst($lumy) . "</a>\n";
					}
				?>
			</div>
		</div>

		<?php if ($ienabled == "Enabled") {
			print "\t\t\t\t<div class=\"dropdown\">\n";
			print "\t\t\t\t<a href=\"/investigate.php\">\n";
			print "\t\t\t\t<button class=\"dropbtn\" style=\"cursor: pointer;\">\n";
			print "\t\t\t\t\t<img src=\"icons/investigate.png\" class=\"icon\">Investigate</button>\n";
			print "\t\t\t\t</a>\n";
			print "\t\t\t</div>\n\n";
			}
		?>

		<div class="dropdown">
			<button class="dropbtn">
				<img src="icons/administration.png" class="icon">
				Administration
			</button>
			<div class="dropdown-content">
				<div class="submenu">
					<a href="#" class="submenu-link" style="cursor: default;">Endpoints <span class="arrow">▸</span></a>
					<div class="submenu-content">
						<a href="/index.php?view=clientstatus">Client Status</a>
						<a href="/index.php?view=egroups">Endpoint Groups</a>
						<a href="/index.php?view=missing">Missing Clients</a>
					</div>
				</div>
				<div class="submenu">
					<a href="#" class="submenu-link" style="cursor: default;">Actions <span class="arrow">▸</span></a>
					<div class="submenu-content">
						<a href="/index.php?view=actions">Scheduled Actions</a>
						<a href="/index.php?view=actionhistory">Action History</a>
					</div>
				</div>
				<div class="submenu">
					<a href="#" class="submenu-link" style="cursor: default;">Content <span class="arrow">▸</span></a>
					<div class="submenu-content">
						<a href="/index.php?view=sensors">Sensors</a>
						<a href="/index.php?view=packages">Packages</a>
						<a href="/index.php?view=csets">Content Sets</a>
					</div>
				</div>
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
					print "<div class=\"submenu\">\n";
					print "<a href=\"#\" class=\"submenu-link\" style=\"cursor: default;\">Configuration<span class=\"arrow\">▸</span></a>\n";
					print "<div class=\"submenu-content\">\n";
					print "<a href=\"/config.php?view=options\">Server Options</a>\n";
					print "<a href=\"/config.php?view=network\">Network</a>\n";
					print "<a href=\"/config.php?view=encryption\">Encryption</a>\n";
					print "<a href=\"/config.php?view=auth\">Authentication</a>\n";
					print "</div>\n";
					print "</div>\n";
					print "<div class=\"submenu\">\n";
					print "<a href=\"#\" class=\"submenu-link\" style=\"cursor: default;\">Users<span class=\"arrow\">▸</span></a>\n";
					print "<div class=\"submenu-content\">\n";
					print "<a href=\"/index.php?view=users\">User Accounts</a>\n";
					print "<a href=\"/index.php?view=ugroups\">User Groups</a>\n";
					print "<a href=\"/index.php?view=roles\">Roles</a>\n";
					print "<a href=\"/index.php?view=perms\">Permissions</a>\n";
					print "</div>\n";
					print "</div>\n";
					print "<div class=\"submenu\">\n";
					print "<a href=\"#\" class=\"submenu-link\" style=\"cursor: default;\">Maintenance <span class=\"arrow\">▸</span></a>\n";
					print "<div class=\"submenu-content\">\n";
					print "<a href=\"/maintenance.php?view=diagnostics\">Diagnostics</a>\n";
					print "<a href=\"/maintenance.php?view=update\">Luminum Update</a>\n";
					print "<a href=\"/maintenance.php?view=downtime\">Outage Management</a>\n";
					print "<a href=\"/maintenance.php?view=os\">Operating System</a>\n";
					print "<a href=\"/maintenance.php?view=services\">Back-End Services</a>\n";
					print "<a href=\"/maintenance.php?view=logs\">System Logs</a>\n";
					print "</div>\n";
					print "</div>\n";
					print "<a href=\"/config.php?view=clients\">Client Management</a>\n";
					}
				?>
			</div>
		</div>
		<div class="dropdown">
			<button class="dropbtn">
				<img src="icons/help.png" class="icon">
				Help
			</button>
			<div class="dropdown-content">
				<a href="/docs.php">Documentation</a>
				<div class="dropdown-divider" style="width: 200px;"></div>
				<a href="/tickets.php">Problem Reports</a>
				<a href="/support.php">Contact Luminum Support</a>
			</div>
		</div>
	</div>
	<div class="user-menu" style="height: 100%;">
		<button class="user-button" style="padding-bottom: 15px;"><?php print $_SESSION["NAME"]; ?> <span style="margin-left: 2px; font-size: 18px;">▾</span></button>
		<div class="user-dropdown">
			<a href="/user.php">Account</a>
			<a href="/user.php?view=prefs">Preferences</a>
			<a href="/index.php?logout=1">Logout</a>
		</div>
	</div>
</div>


