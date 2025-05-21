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

<div style="width: 800px; margin-left: auto; margin-right: auto; margin-top: 12%;">
	<div style="width: 400px; height: 420px; float: left; background-color: #222; text-align: center; box-shadow: 5px 5px 10px rgba(0,0,0,0.5);">
		<img src="/images/logo-light.png" style="margin-top: 46%; margin-left: 15px; width: 250px;">
	</div>
	<div style="width: 400px; height: 420px; float: left; background-color: #ccc; text-align: center; box-shadow: 5px 5px 10px rgba(0,0,0,0.5);">
		<div style="margin-top: 15%; margin-left: 20px; margin-bottom: 7%;"><span id="message" style="color: red; opacity: <?php print "$showmsg"; ?>;"><?php print "$message"; ?></span></div>
		<form action="/index.php" method="post" id="loginform">
			<div style="width: 275px; text-align: left; padding-left: 65px;">
			<span style="color: #444; font-weight: bold; font-size: 15px;">Username:</span><br>
			<input type="text" name="username" id="username" style="width: 250px; font-size: 16px; margin-top: 5px;">
			</div>
			<div style="width: 277px; text-align: left; margin-top: 20px; padding-left: 65px;">
			<span style="color: #444; font-weight: bold; font-size: 15px;">Password:</span><br>
			<input type="password" name="password" id="password" style="width: 250px; font-size: 16px; margin-top: 5px;">
			<br>
			<button type="submit" class="formgo" form="loginform" style="margin-top: 20px; width: 100%; margin-left: 1px;">Sign In</button>
			</div>
		</form>
	</div>
</div>

</body>
</html>

<?php exit; ?>
