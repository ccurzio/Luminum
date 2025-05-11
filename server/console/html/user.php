<?php include ("layout/header.php"); ?>

<?php if (!isset($_GET['view']) || $_GET['view'] == "profile"): ?>
<div class="content">
	<h1>Account Profile</h1>

<?php elseif ($_GET['view'] == "prefs"): ?>
<div class="content">
	<h1>User Preferences</h1>

<?php endif; ?>

</div>

<?php include ("layout/footer.php"); ?>
