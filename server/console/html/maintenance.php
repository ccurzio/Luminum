<?php include ("layout/header.php"); ?>

<?php if (!isset($_GET['view']) || $_GET['view'] == "updates"): ?>
<div class="content">
	<h1>System Updates</h1>

<?php elseif ($_GET['view'] == "downtime"): ?>
<div class="content">
	<h1>Outage Management</h1>

<?php elseif ($_GET['view'] == "services"): ?>
<div class="content">
	<h1>Service Management</h1>

<?php elseif ($_GET['view'] == "os"): ?>
<div class="content">
	<h1>Server Operating System</h1>

<?php elseif ($_GET['view'] == "logs"): ?>
<div class="content">
	<h1>System Logs</h1>

<?php endif; ?>

</div>

<?php include ("layout/footer.php"); ?>
