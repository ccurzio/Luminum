<?php include ("layout/header.php");

if ($acctrole > 1) {
	print "<div class=\"content\">\n";
	print "<h1 style=\"color: red\">Access Denied</h1>\n";
	}
else {
	if (!isset($_GET['view']) || $_GET['view'] == "options"): ?>
	<?php include ("system/serveropts.php"); ?>

	<?php elseif ($_GET['view'] == "clients"): ?>
	<div class="content">
	<h1>Client Management</h1>

	<?php elseif ($_GET['view'] == "network"): ?>
	<div class="content">
	<h1>Networking</h1>

	<div class="module-content" style="padding: 0; width: 60%; margin-left: auto; margin-right: auto; padding: 10px;">
		<div style="width: 75%; margin-left: auto; margin-right: auto; text-align: center;">
			<table style="border: 0;">
			<tr style="pointer-events: none; user-select: none;"><td style="color: #444; background-color: transparent; border: 0; font-weight: normal; font-size: 10px;"><img src="/icons/server.png" style="width: 125px; height: 125px;"><br>luminum.accipiter.org<br>192.168.1.10</td><td style="color: #444; background-color: transparent; border: 0; font-weight: normal;"><img src="/icons/greenlink.png"></td><td style="color: #444; background-color: transparent; border: 0; font-weight: normal; font-size: 10px;"><img src="/icons/firewall.png" style="width: 125px; height: 125px;"><br>defiant.accipiter.org<br>192.168.1.1</td><td style="color: #444; background-color: transparent; border: 0; font-weight: normal; font-size: 10px;"><img src="/icons/greenlink.png"></td><td style="color: #444; background-color: transparent; border: 0; font-weight: normal; font-size: 10px;"><img src="/icons/internet.png" style="width: 125px; height: 125px;"><br>Internet<br>Connected</td></tr>
			</table>
		</div>
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
