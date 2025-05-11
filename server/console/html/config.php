<?php include ("layout/header.php"); ?>

<?php if (!isset($_GET['view']) || $_GET['view'] == "options"): ?>
<div class="content">
	<h1>Configuration Options</h1>

<?php elseif ($_GET['view'] == "clients"): ?>
<div class="content">
	<h1>Client Management</h1>

<?php elseif ($_GET['view'] == "network"): ?>
<div class="content">
	<h1>Networking</h1>

<?php elseif ($_GET['view'] == "auth"): ?>
<div class="content">
	<h1>Authentication</h1>

<?php elseif ($_GET['view'] == "certs"): ?>
<div class="content">
	<h1>Certificates</h1>

<?php endif; ?>

</div>

<?php include ("layout/footer.php"); ?>
