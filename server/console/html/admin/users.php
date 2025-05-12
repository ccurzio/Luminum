<?php
$db = new mysqli("localhost", "***REMOVED***", "***REMOVED***", '', 0, "/var/run/mysqld/mysqld.sock");
mysqli_select_db($db, "AUTH") or die( "<h5>Fatal Error</h5>\n\n<p>Unable to access database.\n</p>");

$starttime = microtime(true);
$usersquery = mysqli_query($db, "select ID,USERNAME,FULLNAME,EMAIL,TYPE,ROLE,REGDATE,LASTSEEN,ENABLED from USERS order by ID");
$endtime = microtime(true);

$duration = number_format((float)$endtime - $starttime, 2, '.', '');
$usercount = mysqli_num_rows($usersquery);
?>

<div class="content">
	<h1>User Accounts</h1>

	<div class="module-content">
		<div style="display: block; width: 100%; text-align: right;">
			<button class="formgo" style="margin-top: 5px; margin-right: 0;">Add User</button>
			<button class="formgo" style="margin-top: 5px; margin-right: 0;">Delete Selected</button>
			<button class="formgo" style="margin-top: 5px; margin-right: 0;">Get Info</button>
		</div>
		<table style="margin-top: 10px;">
		<tr><td colspan="9"><div style="position: absolute; padding-top: 5px;"> <?php print "$usercount of $usercount items"; ?></div><div style="float: right; text-align: right">Filter: <input type="text" style="font-size: 12px; padding: 5px;"></div></td></tr>
		<tr><td style="width: 15px;"><input type="checkbox"></td><td style="width: 50px;">UID</td><td style="width: 75px;">Enabled</td><td style="width: 120px;">Username</td><td>Full Name</td><td style="width: 90px;">Role</td><td style="width: 90px;">Type</td><td>Created</td><td>Last Login</td></tr>

		<?php
			while($row = mysqli_fetch_assoc($usersquery)) {
				if ($row["ENABLED"] == "1") { $acctenabled = "True"; }
				else { $acctenabled = "False"; }
				if ($row["ROLE"] == "1") { $acctrole = "Admin"; }
				elseif ($row["ROLE"] == "2") { $acctrole = "Power User"; }
				elseif ($row["ROLE"] == "3") { $acctrole = "User"; }
				elseif ($row["ROLE"] == "4") { $acctrole = "Read-Only"; }
				print "<tr><td style=\"width: 15px; background-color: #494a69;\"><input type=\"checkbox\"></td><td style=\"width: 50px; background-color: #494a69; font-weight: normal;\">" . $row["ID"] . "</td><td style=\"width: 75px; background-color: #494a69; font-weight: normal;\">" . $acctenabled . "</td><td style=\"width: 120px; background-color: #494a69; font-weight: normal;\">" . $row["USERNAME"] . "</td><td style=\"background-color: #494a69; font-weight: normal;\">" . $row["FULLNAME"] . "</td><td style=\"width: 90px; background-color: #494a69; font-weight: normal;\">" . $acctrole . "</td>" . "<td style=\"width: 90px; background-color: #494a69; font-weight: normal;\">" . $row["TYPE"] . "</td><td style=\"background-color: #494a69; font-weight: normal;\">" . $row["REGDATE"] . "</td><td style=\"background-color: #494a69; font-weight: normal;\">" . (!isset($row["LASTSEEN"]) ? "Never" : $row["LASTSEEN"]) . "</td></tr>\n";
				}
		?>
		<tr style="height: 35px;"><td colspan="9"><div style="position: absolute; padding-top: 5px;"></div><div style="float: right; text-align: right">Query Completed in <?php print $duration; ?> Seconds</div></td></tr>
		</table>
	</div>

</div>
