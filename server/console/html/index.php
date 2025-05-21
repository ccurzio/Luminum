<?php
session_start();
date_default_timezone_set("America/New_York");

ini_set('display_errors', 1);
ini_set('display_startup_errors', 1);
error_reporting(E_ALL);

if ($_SERVER['REQUEST_METHOD'] === 'GET') {
	if (isset($_GET['logout']) && $_GET['logout'] == "1" && isset($_SESSION['SID'])) {
		$dbuser = system("/usr/bin/grep dbuser /opt/Luminum/LuminumServer/config/console.conf | /usr/bin/sed -e 's/^dbuser.*\= //'");
		$dbpass = system("/usr/bin/grep dbpass /opt/Luminum/LuminumServer/config/console.conf | /usr/bin/sed -e 's/^dbpass.*\= //'");
		$db = new mysqli("localhost", $dbuser, $dbpass, '', 0, "/var/run/mysqld/mysqld.sock");
		mysqli_select_db($db, "AUTH") or die( "<h5>Fatal Error</h5>\n\n<p>Unable to access database.\n</p>");
		mysqli_query($db, "delete from SESSION where ID = (select ID from USERS where USERNAME = '" . $_SESSION['USER'] . "')");
		mysqli_close($db);
		session_unset();
		session_destroy();
		}
	if (!isset($_SESSION['SID'])) {
		include ("login.php");
		}
	elseif (!ctype_alnum($_SESSION['SID'])) {
		$_GET["err"] = "badsession";
		include ("login.php");
		}
	}
else {
	if (!isset($_SESSION['SID'])) {
		if ($_POST['username'] == "" || $_POST['password'] == "" || !isset($_POST['username']) || !isset($_POST['password']) || !ctype_alnum($_POST['username'])) {
			$_GET["err"] = "credfail";
			include ("login.php");
			}
		else {
			$username = $_POST['username'];
			$options = [ 'cost' => 13, ];
			$passhash = password_hash($_POST['password'],PASSWORD_BCRYPT, $options);

			$dbuser = system("/usr/bin/grep dbuser /opt/Luminum/LuminumServer/config/console.conf | /usr/bin/sed -e 's/^dbuser.*\= //'");
			$dbpass = system("/usr/bin/grep dbpass /opt/Luminum/LuminumServer/config/console.conf | /usr/bin/sed -e 's/^dbpass.*\= //'");
			$db = new mysqli("localhost", $dbuser, $dbpass, '', 0, "/var/run/mysqld/mysqld.sock");
			mysqli_select_db($db, "AUTH") or die( "<h5>Fatal Error</h5>\n\n<p>Unable to access database.\n</p>");
			$passquery = mysqli_query($db, "select FULLNAME,PASSWORD,ROLE from USERS where USERNAME = '$username' and ENABLED = '1'");
			$storedhash = $passquery->fetch_assoc();

			if (!isset($storedhash["PASSWORD"]) || !password_verify($_POST['password'],$storedhash["PASSWORD"])) {
				$_GET["err"] = "credfail";
				include ("login.php");
				}
			else {
				$acctrole = $storedhash["ROLE"];
				$newsession = session_create_id('SID');
				setcookie("username",$username,time()+3600, "/","luminum.accipiter.org",0);
				setcookie("SID",$newsession,time()+3600, "/","luminum.accipiter.org",0);
				mysqli_query($db, "insert into SESSION (ID,SID,START,EXPIRES) values ((select ID from USERS where USERNAME = '$username'),'$newsession',now(),now()+interval 60 minute)");
				mysqli_query($db, "update USERS set LASTSEEN = now() where ID = (select ID from USERS where USERNAME = '$username')");
				$_SESSION['SID'] = $newsession;
				$_SESSION['USER'] = $username;
				$_SESSION['START'] = date("Y-m-d H:i:s");
				$_SESSION['NAME'] = $storedhash["FULLNAME"];
				}
			mysqli_close($db);
			}
		}
	}
?>

<?php include ("layout/header.php"); ?>

<?php if (!isset($_GET['view']) || $_GET['view'] == "home"): ?>
<?php include ("modules/query.php"); ?>

<?php elseif ($_GET['view'] == "clientstatus"): ?>
<?php include ("admin/cstatus.php"); ?>

<?php elseif ($_GET['view'] == "actions"): ?>
<?php include ("admin/actions.php"); ?>

<?php elseif ($_GET['view'] == "actionhistory"): ?>
<?php include ("admin/actionhistory.php"); ?>

<?php elseif ($_GET['view'] == "cgroups"): ?>
<div class="content">
	<h1>Computer Groups</h1>

<?php elseif ($_GET['view'] == "packages"): ?>
<?php include ("admin/packages.php"); ?>

<?php elseif ($_GET['view'] == "csets"): ?>
<div class="content">
	<h1>Content Sets</h1>

<?php elseif ($_GET['view'] == "sensors"): ?>
<?php include ("admin/sensors.php"); ?>

<?php elseif ($_GET['view'] == "sysinfo"): ?>
<?php include ("system/sysinfo.php"); ?>

<?php elseif ($_GET['view'] == "users"): ?>
<?php include ("admin/users.php"); ?>

<?php endif; ?>

</div>

<?php include ("layout/footer.php"); ?>
