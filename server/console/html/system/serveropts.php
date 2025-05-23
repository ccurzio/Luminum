<?php

if ($acctrole > 1) {
	print "<div class=\"content\">\n";
	print "<h1 style=\"color: red\">Access Denied</h1>\n";
	}
else {
?>

<div class="content">
	<h1>Server Configuration Options</h1>

	<form action="/system/serveropts.php" method="POST">
	<div style="width: 100%; text-align: right; margin: -50px auto 10px auto;">
		<button id="save" class="formgo" style="margin-right: 0;" disabled="disabled">Save Changes</button>
		<input type="reset" id="reset" value="Reset Values" class="formgo">
	</div>

	<div class="module-content" style="padding: 0;">
		<div class="tabbar tabbarback">
			<button type="button" class="tabbaritem tabbutton tablink tabbarsel" style="border-right: 1px solid #07f;" onclick="switchTab(event, 'General')">General</button>
			<button type="button" class="tabbaritem tabbutton tablink" style="border-right: 1px solid #07f;" onclick="switchTab(event, 'Endpoints')">Endpoints</button>
			<button type="button" class="tabbaritem tabbutton tablink" style="border-right: 1px solid #07f;" onclick="switchTab(event, 'SMTP')">SMTP</button>
			<button type="button" class="tabbaritem tabbutton tablink" style="border-right: 1px solid #07f;" onclick="switchTab(event, 'Encryption')">Encryption</button>
			<button type="button" class="tabbaritem tabbutton tablink" style="border-right: 1px solid #07f;" onclick="switchTab(event, 'Logins')">User Logins</button>
		</div>

		<div id="General" class="configtab">
			<table style="width: 50%; border: 0; margin-left: auto; margin-right: auto; margin-top: 15px; margin-bottom: 15px;">
			<tr><td style="background-color: transparent; border: 0; color: #000; font-weight: bold;">Minimum Action Target Confirmation: </td><td style="background-color: transparent; border: 0;"><select id="minactconf" style="width: 175px; height: 28px;"><option value="enabled">Enabled</option><option value="disabled">Disabled</option></select> <div class="tooltip"><img src="/icons/help.png" style="width: 15px; height: 15px; opacity: 0.33; vertical-align: top;"> <span class="tooltiptext">Specifies the minimum number of targeted clients requiring confirmation for action deployments<br><br>Default: Enabled; 250 Endpoints</span></div></td></tr>
			<tr><td style="background-color: transparent; border: 0; color: #000; font-weight: normal; padding-left: 30px;">Confirmation Threshold:</td><td style="background-color: transparent; border: 0; color: #000; font-weight: normal;"><input id="actconfclients" type="text" style="width: 60px; font-size: 15px; padding: 3px; margin-top: 0;" maxlength="5"> Endpoints</td></tr>
			</table>
		</div>

		<div id="Endpoints" class="configtab" style="display: none;">
			<table style="width: 50%; border: 0; margin-left: auto; margin-right: auto; margin-top: 15px; margin-bottom: 15px;">
			<tr><td style="background-color: transparent; border: 0; color: #000; font-weight: bold;">Communication Method: </td><td style="background-color: transparent; border: 0;"><select id="commproto" style="width: 175px; height: 28px;"><option value="mqtt">MQTT</option><option value="direct">Hub &amp; Spoke</option><option value="hybrid">Hybrid</option></select> <div class="tooltip"><img src="/icons/help.png" style="width: 15px; height: 15px; opacity: 0.33; vertical-align: top;"> <span class="tooltiptext">The method of communication used between the server and endpoint clients.<br><br><u>MQTT</u>: Message Queuing Telemetry Transport provides a method by which clients subscribe to feeds on which messages are published<br><br><u>Hub &amp; Spoke</u>: Direct client/server connections (NOT RECOMMENDED FOR LARGE MULTI-NETWORK DEPLOYMENTS)<br><br><u>Hybrid</u>: Uses a combination of both MQTT and Hub &amp; Spoke with the server automatically choosing the best method based on endpoint network positioning<br><br>Default: MQTT</span></div></td></tr>
			<tr><td style="background-color: transparent; border: 0; color: #000; font-weight: bold;">Check-In Interval: </td><td style="background-color: transparent; border: 0; color: #000; font-weight: normal;"><input id="checkinint" type="text" style="width: 25px; font-size: 15px; padding: 3px; margin-top: 0;" maxlength="2"> Minutes <div class="tooltip"><img src="/icons/help.png" style="width: 15px; height: 15px; opacity: 0.33; vertical-align: top;"> <span class="tooltiptext">The interval at which clients ping the server with their status and request updates<br><br>Default: 5 Minutes</span></div></td></tr>
			<tr><td style="background-color: transparent; border: 0; color: #000; font-weight: bold;">Mark as Missing After: </td><td style="background-color: transparent; border: 0; color: #000; font-weight: normal;"><input id="checkinint" type="text" style="width: 25px; font-size: 15px; padding: 3px; margin-top: 0;" maxlength="2"> Days <div class="tooltip"><img src="/icons/help.png" style="width: 15px; height: 15px; opacity: 0.33; vertical-align: top;"> <span class="tooltiptext">The length of time after which offline endpoints are marked as missing<br><br>Default: 90 Days</span></div></td></tr>
			</table>
		</div>

		<div id="SMTP" class="configtab" style="display: none;">
			<p>SMTP Settings</p>
		</div>

		<div id="Encryption" class="configtab" style="display: none;">
			<p>Encryption Settings</p>
		</div>

		<div id="Logins" class="configtab" style="display: none;">
			<table style="width: 50%; border: 0; margin-left: auto; margin-right: auto; margin-top: 15px; margin-bottom: 15px;">
			<tr><td style="background-color: transparent; border: 0; color: #000; font-weight: bold;">Minimum Password Length: </td><td style="background-color: transparent; border: 0; color: #000; font-weight: normal;"><input id="passlen" type="text" style="width: 25px; font-size: 15px; padding: 3px; margin-top: 0;" maxlength="2"> Characters</td></tr>
			<tr><td style="background-color: transparent; border: 0; color: #000; font-weight: bold;">Password Complexity Enforcement: </td><td style="background-color: transparent; border: 0; color: #000; font-weight: normal;"><select id="minactconf" style="width: 175px; height: 28px;"><option value="enabled">Enabled</option><option value="disabled">Disabled</option></select> <div class="tooltip"><img src="/icons/help.png" style="width: 15px; height: 15px; opacity: 0.33; vertical-align: top;"> <span class="tooltiptext">Require user passwords to include specified characters<br><br>Default: Disabled</span></div></td></tr>
			<tr><td style="background-color: transparent; border: 0; color: #000;"></td><td style="background-color: transparent; border: 0; color: #000; font-weight: normal;"><input id="pwdcase" type="checkbox"> Upper and Lowercase<br><input id="pwdnums" type="checkbox"> Letters and Numbers<br><input id="pwdspec" type="checkbox"> Special Characters</td></tr>
			<tr><td style="background-color: transparent; border: 0; color: #000; font-weight: bold;">Inactivity Timeout: </td><td style="background-color: transparent; border: 0;"><input id="inactiveint" type="text" style="width: 25px; font-size: 15px; padding: 3px; margin-top: 0;" maxlength="2"> <select id="inttype" style="width: 175px; height: 28px;"><option value="min">Minute(s)</option><option value="hour">Hour(s)</option><option value="day">Day(s)</option></select> <div class="tooltip"><img src="/icons/help.png" style="width: 15px; height: 15px; opacity: 0.33; vertical-align: top;"> <span class="tooltiptext">The length of time before a user is automatically logged out due to inactivity<br><br>Default: 15 Minutes</span></div></td></tr>
			<tr><td style="background-color: transparent; border: 0; color: #000; font-weight: normal; padding-left: 30px;">2 Minute Warning:</td><td style="background-color: transparent; border: 0; color: #000; font-weight: normal;"><select id="2minwarn" style="width: 175px; height: 28px;"><option value="enabled">Enabled</option><option value="disabled">Disabled</option></select> <div class="tooltip"><img src="/icons/help.png" style="width: 15px; height: 15px; opacity: 0.33; vertical-align: top;"> <span class="tooltiptext">Displays a warning to the user 2 minutes before they are automatically logged out<br><br>Default: Enabled</span></div></td></tr></td></tr>
			</table>
		</div>
	</div>
	</form>
</div>

<script>
function switchTab(evt, configSect) {
	var i, x, tablinks;
	x = document.getElementsByClassName("configtab");

	for (i = 0; i < x.length; i++) {
		x[i].style.display = "none";
		}

	tablinks = document.getElementsByClassName("tablink");
	for (i = 0; i < x.length; i++) {
		tablinks[i].className = tablinks[i].className.replace(" tabbarsel", "");
		}

	document.getElementById(configSect).style.display = "block";
	evt.currentTarget.className += " tabbarsel";
	}
</script>

<?php } ?>
