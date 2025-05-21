<?php include ("layout/header.php"); ?>

<?php if (!isset($_GET['view']) || $_GET['view'] == "manage"): ?>
<div class="content">
	<h1>Lumy Management</h1>

<?php elseif ($_GET['view'] == "delivery"): ?>
<div class="content">
	<h1>Luminum Delivery</h1>

<?php elseif ($_GET['view'] == "discovery"): ?>
<div class="content">
	<h1>Luminum Discovery</h1>

<?php elseif ($_GET['view'] == "integrity"): ?>
<div class="content">
	<h1>Luminum Integrity</h1>

<?php elseif ($_GET['view'] == "inventory"): ?>
<div class="content">
	<h1>Luminum Inventory</h1>

<?php elseif ($_GET['view'] == "policy"): ?>
<div class="content">
	<h1>Luminum Policy</h1>

<?php endif; ?>

</div>

<?php include ("layout/footer.php"); ?>
