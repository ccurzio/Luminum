<?php include ("layout/header.php"); ?>
<div class="content">
	<h1>Investigate</h1>

	<div class="module-content" style="width: 75%; margin-left: auto; margin-right: auto; min-width: 850px; text-align: center;">
		<div style="margin-top: 10px; margin-right: 40px;">
			<span style="font-size: 30px; font-weight: bold;">Step 1</span>
			<img src="/images/stepline.png" style="width: 75px; height: 5px; margin-bottom: 7px; margin-left: 10px; margin-right: 10px; <?php if ($_GET["step"] <= 1) { print "opacity: 0.25"; } ?>">
			<span style="font-size: 30px; font-weight: bold; <?php if ($_GET["step"] <= 1) { print "opacity: 0.25"; } ?>">Step 2</span>
			<img src="/images/stepline.png" style="width: 75px; height: 5px; margin-bottom: 7px; margin-left: 10px; margin-right: 10px; <?php if ($_GET["step"] <= 2) { print "opacity: 0.25"; } ?>">
			<span style="font-size: 30px; font-weight: bold; <?php if ($_GET["step"] <= 2) { print "opacity: 0.25"; } ?>">Step 3</span>
			<img src="/images/stepline.png" style="width: 75px; height: 5px; margin-bottom: 7px; margin-left: 10px; margin-right: 10px; <?php if ($_GET["step"] <= 3) { print "opacity: 0.25"; } ?>">
			<span style="font-size: 30px; font-weight: bold; <?php if ($_GET["step"] <= 3) { print "opacity: 0.25"; } ?>">Step 4</span>
		</div>

<?php if (!isset($_GET['step']) || $_GET['step'] == "1"): ?>

<?php endif; ?>

		<div style="margin-top: 10px; text-align: right; width: 102%; margin-left: 0;">
			<button class="formgo" style="width: 75px;">Next</button>
		</div>
	</div>

<?php include ("layout/footer.php"); ?>
