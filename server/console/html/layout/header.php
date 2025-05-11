<?php
if (!isset($_SESSION)) {
	session_start();
	}
date_default_timezone_set("America/New_York");
?>

<!DOCTYPE html>
<html lang="en">
<head>
	<meta charset="UTF-8">
	<title>Luminum (luminum.accipiter.org)</title>
	<meta name="viewport" content="width=device-width, initial-scale=1">
	<link rel="stylesheet" href="layout/default.css">
</head>

<body>

<div class="header">
	<div class="logo">
		<img src="images/logo-light.png" alt="Luminum" class="logo-img">
	</div>
	<div class="user-menu">
		<button class="user-button">Luminum Admin ▾</button>
		<div class="user-dropdown">
			<a href="/user.php">Account</a>
			<a href="/user.php?view=prefs">Preferences</a>
			<a href="/index.php?logout=1">Logout</a>
		</div>
	</div>
</div>

<nav class="navbar">
	<button class="menu-toggle" onclick="toggleMenu()">☰</button>
	<div id="navbar-links" class="nav-links">
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
				Modules
			</button>
			<div class="dropdown-content">
				<a href="/modules.php">Management</a>
				<div class="dropdown-divider" style="width: 180px;"></div>
				<a href="/modules.php?view=delivery">Delivery</a>
				<a href="/modules.php?view=discovery">Discovery</a>
				<a href="/modules.php?view=integrity">Integrity</a>
				<a href="/modules.php?view=inventory">Inventory</a>
				<a href="/modules.php?view=policy">Policy</a>
			</div>
		</div>

		<div class="dropdown">
			<button class="dropbtn">
				<img src="icons/administration.png" class="icon">
				Administration
			</button>
			<div class="dropdown-content">
				<a href="/index.php?view=clientstatus">Client Status</a>
				<div class="submenu">
					<a href="#" class="submenu-link" style="cursor: default;">Content <span style="margin-left: 100px;" class="arrow">▸</span></a>
					<div class="submenu-content">
						<a href="/index.php?view=packages">Packages</a>
						<a href="/index.php?view=sensors">Sensors</a>
						<a href="/index.php?view=csets">Content Sets</a>
					</div>
				</div>
				<a href="/index.php?view=actions">Scheduled Actions</a>
				<a href="/index.php?view=actionhistory">Action History</a>
				<a href="/index.php?view=groups">Computer Groups</a>
			</div>
		</div>

		<div class="dropdown">
			<button class="dropbtn">
				<img src="icons/system.png" class="icon">
				System
			</button>
			<div class="dropdown-content">
				<a href="/index.php?view=sysinfo">System Information</a>
				<div class="dropdown-divider"></div>
				<a href="/config.php?view=clients">Client Management</a>
				<a href="/index.php?view=users">User Accounts</a>
				<div class="submenu">
					<a href="#" class="submenu-link" style="cursor: default;">Configuration <span style="margin-left: 70px;" class="arrow">▸</span></a>
					<div class="submenu-content">
						<a href="/config.php?view=options">Server Options</a>
						<a href="/config.php?view=network">Network</a>
						<a href="/config.php?view=certs">Certificates</a>
						<a href="/config.php?view=auth">Authentication</a>
					</div>
				</div>
				<div class="submenu">
					<a href="#" class="submenu-link" style="cursor: default;">Maintenance <span style="margin-left: 70px;" class="arrow">▸</span></a>
					<div class="submenu-content">
						<a href="/maintenance.php?view=updates">System Updates</a>
						<a href="/maintenance.php?view=downtime">Outage Management</a>
						<a href="/maintenance.php?view=services">Back-End Services</a>
						<a href="/maintenance.php?view=os">Operating System</a>
						<a href="/maintenance.php?view=logs">System Logs</a>
					</div>
				</div>
			</div>
		</div>
	</div>
	<div class="nav-text-right">
		Console v0.0.1
	</div>
</nav>

