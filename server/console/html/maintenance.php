<?php include ("layout/header.php");

if ($acctrole > 1) {
	print "<div class=\"content\">\n";
	print "<h1 style=\"color: red\">Access Denied</h1>\n";
	}
else {
	if (!isset($_GET['view']) || $_GET['view'] == "updates"): ?>
	<div class="content">
	<h1>System Updates</h1>

	<?php elseif ($_GET['view'] == "diagnostics"): ?>
	<div class="content">
	<h1>Diagnostics</h1>

	<?php elseif ($_GET['view'] == "downtime"): ?>
	<div class="content">
	<h1>Outage Management</h1>

	<?php elseif ($_GET['view'] == "services"): ?>
	<div class="content">
	<h1>Back-End Service Management</h1>

	<?php elseif ($_GET['view'] == "os"): ?>
	<div class="content">
	<h1>Server Operating System</h1>

	<?php elseif ($_GET['view'] == "logs"): ?>
	<div class="content">
	<h1>System Logs</h1>

	<?php endif;
	} ?>

</div>

<?php include ("layout/footer.php"); ?>
