<?php include ("layout/header.php"); ?>

<?php if (!isset($_GET['view']) || $_GET['view'] == "profile"): ?>
<?php
        mysqli_select_db($db, "AUTH") or die( "<h5>Fatal Error</h5>\n\n<p>Unable to access database.\n</p>");
        $userquery = mysqli_query($db, "select ID,USERNAME,FULLNAME,EMAIL,PHONE,TYPE,ROLE,REGDATE from USERS where USERNAME = (select USERNAME from USERS where ID = (select ID from SESSION where SID = '" . $_SESSION["SID"] . "'))");
        $userinfo = $userquery->fetch_assoc();
	if ($userinfo["ROLE"] == "1") { $userrole = "Administrator"; }
	elseif ($userinfo["ROLE"] == "2") { $userrole = "Power User"; }
	elseif ($userinfo["ROLE"] == "3") { $userrole = "User"; }
	elseif ($userinfo["ROLE"] == "4") { $userrole = "Read-Only User"; }
?>

<div class="content">
	<h1>Account Profile</h1>

	<div class="module-content" style="width: 75%; margin-left: auto; margin-right: auto;">
		<div style="display: block; width: 100%; text-align: right;">
			<button id="saveuser" class="formgo" style="margin-top: 5px; margin-right: 0;" disabled="disabled">Save Changes</button>
		</div>
		<div style="margin-top: 10px;">
			<table style="width: 75%; border: 0; margin-left: auto; margin-right: auto; margin-top: 15px; margin-bottom: 45px;">
                        <tr><td style="color: #444; background-color: transparent; border: 0; font-weight: bold;">Userame:</td><td style="color: #444; background-color: transparent; border: 0; font-weight: normal;"> <input id="fullname" type="text" value="<?php print $userinfo["USERNAME"]; ?>"></td><td style="color: #444; background-color: transparent; border: 0; font-weight: bold;">Password: <span style="color: red;">*</span></td><td style="color: #444; background-color: transparent; border: 0; font-weight: normal;"><input id="password" type="password" value=""></td></tr>
                        <tr><td style="color: #444; background-color: transparent; border: 0; font-weight: bold;">Full Name:</td><td style="color: #444; background-color: transparent; border: 0; font-weight: normal;"> <input id="fullname" type="text" value="<?php print $userinfo["FULLNAME"]; ?>"></td><td style="color: #444; background-color: transparent; border: 0; font-weight: bold;">New Password:</td><td style="color: #444; background-color: transparent; border: 0; font-weight: normal;"><input id="newpassword" type="password"></td></tr>
                        <tr><td style="color: #444; background-color: transparent; border: 0; font-weight: bold;">Email Address:</td><td style="color: #444; background-color: transparent; border: 0; font-weight: normal;"><input id="email" type="text" value="<?php print $userinfo["EMAIL"]; ?>"></td><td style="color: #444; background-color: transparent; border: 0; font-weight: bold;">Confirm New Password:</td><td style="color: #444; background-color: transparent; border: 0; font-weight: normal;"><input id="confirmnewpass" type="password"></td></tr>
                        <tr><td style="color: #444; background-color: transparent; border: 0; font-weight: bold;">Phone:</td><td style="color: #444; background-color: transparent; border: 0; font-weight: normal;"><input id="phone" type="text" value="<?php print $userinfo["PHONE"]; ?>"></td><td style="color: #444; background-color: transparent; border: 0; font-weight: bold;">Two-Factor Authentication:</td><td style="color: #444; background-color: transparent; border: 0; font-weight: normal;">
			<select id="2FA" style="height: 28px; width: 200px; margin-left: 3px;"><option value="enabled">Enabled</option><option value="disabled">Disabled</option></select>
			</td></tr>
                        <tr><td style="color: #444; background-color: transparent; border: 0; font-weight: bold;">Role:</td><td style="color: #444; background-color: transparent; border: 0; font-weight: normal;"> <?php print $userrole; ?></td></tr>
                        <tr><td style="color: #444; background-color: transparent; border: 0; font-weight: bold;">Account Type:</td><td style="color: #444; background-color: transparent; border: 0; font-weight: normal;"><?php print $userinfo["TYPE"]; ?></td></tr>
                        <tr><td style="color: #444; background-color: transparent; border: 0; font-weight: bold;">Create Date:</td><td style="color: #444; background-color: transparent; border: 0; font-weight: normal;"><?php print $userinfo["REGDATE"]; ?></td></tr>

			</table>
		</div>
	</div>

<?php elseif ($_GET['view'] == "prefs"): ?>
<div class="content">
	<h1>User Preferences</h1>

<?php endif; ?>

</div>

<?php include ("layout/footer.php"); ?>
