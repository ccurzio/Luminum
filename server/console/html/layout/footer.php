<div class="footer">
<div style="padding-bottom: 10px;"><b>Session Start:</b> <?php print $_SESSION['START']; ?></div><div class="nav-text-right" style="padding-bottom: 10px; color: white; font-size: 15px;"><b>System Health:</b> <a href="/maintenance.php?view=diagnostics"><img style="vertical-align: text-bottom; width: 18px; height: 18px;" src="icons/sysgreen.png"></a></div>
</div>

<script>
function toggleMenu() {
	const nav = document.getElementById("navbar-links");
	nav.classList.toggle("active");
	}
</script>

</body>
</html>
