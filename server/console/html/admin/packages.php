<?php
$db = new mysqli("localhost", "***REMOVED***", "***REMOVED***", '', 0, "/var/run/mysqld/mysqld.sock");
mysqli_select_db($db, "CONTENT") or die( "<h5>Fatal Error</h5>\n\n<p>Unable to access database.\n</p>");

$starttime = microtime(true);
$pkgquery = mysqli_query($db, "select ID,NAME,DESCRIPTION,MAC,LIN,WIN,AUTHOR,CREATED,MODIFIED,EDITOR,REVISIONS from PACKAGES order by ID");
$csets = mysqli_query($db, "select ID,NAME from SETS order by NAME");
$endtime = microtime(true);

$duration = number_format((float)$endtime - $starttime, 2, '.', '');
$pkgcount = mysqli_num_rows($pkgquery);
?>
<div class="content">
	<h1>Packages</h1>

	<div class="module-content">
                <?php
                print "<div style=\"display: block; width: 100%; text-align: right;\">\n";
                if (isset($acctrole) && $acctrole <= 2) {
                        print "<button class=\"formgo\" style=\"margin-top: 5px; margin-right: 0;\">Create New</button>\n";
                        print "<button class=\"formgo\" style=\"margin-top: 5px; margin-right: 0;\" disabled=\"disabled\">Modify Selected</button>\n";
                        print "<button class=\"formgo\" style=\"margin-top: 5px; margin-right: 0;\" disabled=\"disabled\">Delete Selected</button>\n";
                        }
                print "<button class=\"formgo\" style=\"margin-top: 5px; margin-right: 0;\" disabled=\"disabled\">Get Info</button>\n";
                print "</div>\n";
                ?>
		<table style="margin-top: 10px;">
		<tr><td colspan="10"><div style="position: absolute; padding-top: 7px; padding-left: 5px;"">0 of <?php print $pkgcount; ?> items</div>
		<div style="float: right; text-align: right; padding-right: 5px;">Content Set: <select id="contentset" name="contentset" style="background-color: #eee; border-radius: 8px; font-size: 14px; height: 26px; margin-left: 2px; margin-right: 30px; margin-top: 2px; width: 170px;" <?php if ($pkgcount == 0) { print "disabled=\"disabled\""; } ?>>
			<option value="all">All</option>
			<?php
			while ($csrow = mysqli_fetch_assoc($csets)) {
				print "<option value=\"" . $csrow["ID"] . "\">" . $csrow["NAME"] . "</option>\n";
				}
			?>
		</select> Filter: <input type="text" style="font-size: 15px; padding: 3px; margin-top: 0;" <?php if ($pkgcount == 0) { print "disabled=\"disabled\""; } ?>></div></td></tr>
		<tr><td style="width: 15px;">
		<?php
			if ($pkgcount == 0) { print "<input type=\"checkbox\" disabled=\"disabled\">"; }
			else { print "<input type=\"checkbox\">"; }
		?>
		</td><td style="width: 200px;">Name</td><td>Description</td><td style="width: 120px;">Compatibility</td><td style="width: 75px;">Size</td><td style="width: 100px;">Author</td><td style="width: 175px;">Create Date</td><td style="width: 175px;">Last Modification</td><td style="width: 100px;">Modified By</tr>
		<?php

		if ($pkgcount == 0) {
			print "<tr><td colspan=\"10\" style=\"text-align: center; background-color: #494a69; font-weight: normal; font-style: italic;\">No Results</td></tr>\n";
			}
		else {
			while($row = mysqli_fetch_assoc($pkgquery)) {
				print "<tr><td id=\"" . $row["ID"] . "A\" style=\"width: 15px; background-color: #494a69;\"><input id=\"ID" . $row["ID"] . "\" type=\"checkbox\" onclick=\"rowHighlight(" . $row["ID"] . ")\"></td><td id=\"" . $row["ID"] . "B\" style=\"width: 50px; background-color: #494a69; font-weight: normal;\">" . $row["NAME"] . "</td><td id=\"" . $row["ID"] . "C\" style=\"width: 75px; background-color: #494a69; font-weight: normal;\">" . $row["DESCRIPTION"] . "</td><td id=\"" . $row["ID"] . "D\" style=\"width: 120px; background-color: #494a69; font-weight: normal;\">" . "COMPAT" . "</td><td id=\"" . $row["ID"] . "E\" style=\"background-color: #494a69; font-weight: normal;\">" . "SIZE" . "</td><td id=\"" . $row["ID"] . "F\" style=\"width: 90px; background-color: #494a69; font-weight: normal;\">" . $row["AUTHOR"] . "</td><td id=\"" . $row["ID"] . "F\" style=\"width: 90px; background-color: #494a69; font-weight: normal;\">" . $row["CREATED"] . "</td>" . "<td id=\"" . $row["ID"] . "G\" style=\"width: 90px; background-color: #494a69; font-weight: normal;\">" . $row["MODIFIED"] . "</td><td id=\"" . $row["ID"] . "H\" style=\"background-color: #494a69; font-weight: normal;\">" . $row["EDITOR"] . "</td></tr>\n";
				}
			}
		?>
		<tr style="height: 35px;"><td colspan="10"><div style="position: absolute; padding-top: 5px;"></div><div style="float: right; text-align: right; padding-bottom: 2px; padding-right: 5px; font-weight: normal;">Query Completed in <?php print $duration; ?> Seconds</div></td></tr>
		</table>
	</div>
