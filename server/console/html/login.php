<?php

$showmsg = "0";
$message = "Awaiting Credential Submission";

if (isset($_GET["err"])) {
	if ($_GET["err"] == "credfail") {
		$message = "Invalid Username or Password";
		$showmsg = "1";
		}
	elseif ($_GET["err"] == "badsession") {
		$message = "Session Expired";
		$showmsg = "1";
		}
	}

?>

<!DOCTYPE html>
<html lang="en">
<head>
	<meta charset="UTF-8">
	<title>Luminum (luminum.accipiter.org)</title>
	<meta name="viewport" content="width=device-width, initial-scale=1">
	<link rel="stylesheet" href="layout/default.css">
</head>

<body>

<div style="width: 900px; margin-left: auto; margin-right: auto; margin-top: 12%;">
	<div style="width: 450px; height: 500px; float: left; background-color: #555; text-align: center; box-shadow: 5px 5px 10px rgba(0,0,0,0.5);">
		<img src="/images/logo-light.png" style="margin-top: 48%; margin-left: 20px;">
	</div>
	<div style="width: 450px; height: 500px; float: left; background-color: #222; text-align: center; box-shadow: 5px 5px 10px rgba(0,0,0,0.5);">
		<div style="margin-top: 31%; margin-left: 20px;"><span id="message" style="color: red; opacity: <?php print "$showmsg"; ?>;"><?php print "$message"; ?></span></div>
		<form action="/index.php" method="post" id="loginform">
			<input type="text" name="username" id="username" style="width: 200px; font-size: 16px; margin-top: 20px; margin-left: 20px;" placeholder="Username">
			<br>
			<input type="password" name="password" id="password" style="width: 200px; font-size: 16px; margin-top: 15px; margin-left: 20px;" placeholder="Password">
			<br>
			<button type="submit" class="formgo" form="loginform" style="width: 90px; margin-top: 15px; margin-left: 35px;">Log In</button>
		</form>
	</div>
</div>

</body>
</html>

<?php exit; ?>
