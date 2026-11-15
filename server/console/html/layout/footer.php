<div class="footer">
<!-- TEMP test hook: clicking the session start time forces the 2-minute
     logout warning so it can be inspected on demand. onActivity is
     neutralized first because any activity (including the mousedown that
     would click the warning's own buttons) dismisses it. Remove after
     testing. -->
<div style="padding-bottom: 10px;"><b>Session Start:</b> <span style="cursor: pointer; text-decoration: underline dotted;" title="TEST: force the logout warning" onclick="LuminumSession.onActivity = function () {}; LuminumSession.showWarning();"><?php print $_SESSION['START']; ?></span></div><div class="nav-text-right" style="padding-bottom: 10px; color: white; font-size: 15px;"><b>System Health:</b> <a href="/maintenance.php?view=diagnostics"><img style="vertical-align: text-bottom; width: 18px; height: 18px;" src="icons/sysgreen.png"></a></div>
</div>

<script>
function toggleMenu() {
	const nav = document.getElementById("navbar-links");
	nav.classList.toggle("active");
	}
</script>

<?php
// Inactivity timeout client config: the current deadline (Unix seconds on
// the server clock), the inactivity window, and whether the 2-minute warning
// is enabled. The gate in layout/header.php has already bounced expired
// sessions, so a live deadline exists here.
require_once __DIR__ . '/session.php';
$deadline = 0;
$utsecs = 900;
$warn = true;
if (isset($_SESSION['SID']) && ctype_alnum($_SESSION['SID'])) {
	$sid = mysqli_real_escape_string($db, $_SESSION['SID']);
	$sq = mysqli_query($db, "select unix_timestamp(EXPIRES) as deadline from AUTH.SESSION where SID = '$sid'");
	$srow = $sq ? $sq->fetch_assoc() : null;
	if ($srow && $srow['deadline'] !== null) { $deadline = (int)$srow['deadline']; }
	$utsecs = luminum_utimeout_seconds($db);
	$wq = mysqli_query($db, "select CVAL from SYSTEM.CONFIG where CKEY = 'UTIMEOUTWARN'");
	$wrow = $wq ? $wq->fetch_assoc() : null;
	$warn = ($wrow && $wrow['CVAL'] === 'Enabled');
}
?>
<script src="layout/session.js"></script>
<script>
LuminumSession.init({
	deadline: <?php echo json_encode($deadline); ?>,
	timeout: <?php echo json_encode($utsecs); ?>,
	warn: <?php echo $warn ? 'true' : 'false'; ?>,
	serverNow: <?php echo json_encode(time()); ?>
});
</script>

</body>
</html>
