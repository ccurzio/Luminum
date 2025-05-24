<?php
mysqli_select_db($db, "CLIENTS") or die( "<h5>Fatal Error</h5>\n\n<p>Unable to access database.\n</p>");

$starttime = microtime(true);
$clientsquery = mysqli_query($db, "select ID,HOSTNAME,IPV4,OSPLATFORM,OSRELEASE,CLIENTVER,CSTATE,LASTSEEN from STATUS where MISSING = 1 order by ID");
$endtime = microtime(true);

$duration = number_format((float)$endtime - $starttime, 2, '.', '');
$clientscount = mysqli_num_rows($clientsquery);
$lincount = 0;
$maccount = 0;
$wincount = 0;
?>

<div class="content">
	<h1>Missing Clients</h1>
