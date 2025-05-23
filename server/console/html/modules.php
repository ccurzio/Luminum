<?php include ("layout/header.php"); ?>

<?php if (!isset($_GET['view']) || $_GET['view'] == "manage") {
	print "<div class=\"content\">\n";
	print "<h1>Lumy Management</h1>\n\n";
	}
else {
	if ($_GET['view'] == "summary") {
		print "<div class=\"content\">\n";
		print "<h1>Luminum Summary</h1>\n\n";
		}
	else {
		if (preg_match("/^[a-z]+$/",$_GET['view']) && file_exists($instdir . "/modules/" . $_GET['view'] . ".php")) {
			include ($instdir . "/modules/" . $_GET['view'] . ".php");
			}
		else {
			print "<div class=\"content\">\n";
			print "NOT FOUND";
			}
		}
	}
?>

</div>

<?php include ("layout/footer.php"); ?>
