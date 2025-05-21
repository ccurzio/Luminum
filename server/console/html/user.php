<?php include ("layout/header.php"); ?>

<?php if (!isset($_GET['view']) || $_GET['view'] == "profile"): ?>
<?php
	$dbuser = exec("/usr/bin/grep dbuser /opt/Luminum/LuminumServer/config/console.conf | /usr/bin/sed -e 's/^dbuser.*\= //'");
	$dbpass = exec("/usr/bin/grep dbpass /opt/Luminum/LuminumServer/config/console.conf | /usr/bin/sed -e 's/^dbpass.*\= //'");
	$db = new mysqli("localhost", $dbuser, $dbpass, '', 0, "/var/run/mysqld/mysqld.sock");
        mysqli_select_db($db, "AUTH") or die( "<h5>Fatal Error</h5>\n\n<p>Unable to access database.\n</p>");
        $userquery = mysqli_query($db, "select ID,USERNAME,FULLNAME,EMAIL,TYPE,ROLE,REGDATE from USERS where USERNAME = (select USERNAME from USERS where ID = (select ID from SESSION where SID = '" . $_SESSION["SID"] . "'))");
        $userinfo = $userquery->fetch_assoc();
	if ($userinfo["ROLE"] == "1") { $userrole = "Administrator"; }
	elseif ($userinfo["ROLE"] == "2") { $userrole = "Power User"; }
	elseif ($userinfo["ROLE"] == "3") { $userrole = "User"; }
	elseif ($userinfo["ROLE"] == "4") { $userrole = "Read-Only User"; }
?>

<div class="content">
	<h1>Account Profile</h1>

	<div class="module-content" style="width: 60%; margin-left: auto; margin-right: auto;">
		<div style="margin-top: 20px;">
			<h3><?php print "UID #" . $userinfo["ID"] . ": " . $userinfo["USERNAME"] . " (" . $userrole . ")"; ?></h3>
			<span style="font-weight: bold;">Name: </span> <?php print $userinfo["FULLNAME"]; ?> <br>
			<span style="font-weight: bold;">Email: </span> <?php print $userinfo["EMAIL"]; ?> <br>
			<span style="font-weight: bold;">Registered: </span> <?php print $userinfo["REGDATE"]; ?> <br>
			<span style="font-weight: bold;">Account Type: </span> <?php print $userinfo["TYPE"]; ?> <br>
		</div>
	</div>

<?php elseif ($_GET['view'] == "prefs"): ?>
<div class="content">
	<h1>User Preferences</h1>

<?php endif; ?>

</div>

<?php include ("layout/footer.php"); ?>
