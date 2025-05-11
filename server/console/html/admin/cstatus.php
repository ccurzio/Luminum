<div class="content">
	<h1>Client Status</h1>

	<div class="module-content" style="display: flex; justify-content: space-between; align-items: flex-start; width: 70%; float: left; margin-right: 0px;">
		<div style="display: block; width: 100%; text-align: right;">
			<button class="formgo" style="margin-top: 5px; margin-right: 0;">Deploy Action</button> <button class="formgo" style="margin-top: 5px; margin-right: 0;">Connect</button> <button class="formgo" style="margin-top: 5px; margin-right: 0;">Get Info</button>
			<table style="margin-top: 10px; text-align: left;">
			<tr><td colspan="8"><div style="position: absolute; padding-top: 5px; padding-left: 5px;">1 of 1 items <img src="icons/refresh.png" style="cursor: pointer; margin-left: 2px; width: 20px; height: 20px; vertical-align: text-bottom;"></div><div style="float: right; text-align: right; padding-right: 5px;">Filter: <input type="text" style="font-size: 12px; padding: 5px;"></div></td></tr>
			<tr><td style="width: 15px;"><input type="checkbox"></td><td>Hostname</td><td style="width: 125px;">IP Address</td><td style="width: 50px;">OS</td><td style="width: 150px;">Release</td><td style="width: 120px;">Client Version</td><td style="width: 60px;">Status</td><td style="width: 175px;">Last Registration</td></tr>
			<!-- <tr><td colspan="8" style="text-align: center; background-color: #494a69; font-weight: normal; font-style: italic;">No Results</td></tr> -->
			<tr><td style="background-color: #494a69; width: 15px;"><input type="checkbox"></td><td style="background-color: #494a69; font-weight: normal;">haverford.accipiter.org</td><td style="background-color: #494a69; font-weight: normal;">192.168.0.43</td><td style="text-align: center; background-color: #494a69;"><img src="/images/linux.png" style="width: 24px; height: 24px;"></td><td style="background-color: #494a69; font-weight: normal;">Kali Linux 2025.1c</td><td style="background-color: #494a69; font-weight: normal;">Unknown</td><td style="background-color: #494a69; font-weight: normal; text-align: center;"><img style="vertical-align: text-bottom; width: 18px; height: 18px;" src="icons/sysyellow.png"></td><td style="background-color: #494a69; font-weight: normal;">2025-05-11 09:37:22</td></tr>
			</table>
		</div>
	</div>

	<div class="module-content" style="width: 21%; float: right; font-size: 13px;">
	<p>
		<b><input type="checkbox" checked> Show systems that have checked in within:</b><br>
		<input type="text" style="font-size: 15px; padding: 5px; margin-top: 3px; width: 20px;" value="1">
		<select name="filterint" id="filterint" style="font-size: 15px; height: 30px; margin-left: 2px;">
			 <option value="reg">Registration Interval</option>
			 <option value="minutes">Minute(s)</option>
			 <option value="hours">Hour(s)</option>
			 <option value="days">Day(s)</option>
			 <option value="weeks">Week(s)</option>
			 <option value="months">Month(s)</option>
		</select>
		<button class="formgo" style="margin-top: 5px; margin-right: 0; margin-left: 3px; height: 30px; padding-top: 5px;">Apply</button>
	</p>

	<p style="margin-top: 20px;">
	<span style="font-size: 15px; font-weight: bold;">Filter by Operating System:</span>
	</p>
	<table style="margin-bottom: 20px;">
	<tr><td style="width: 15px;"></td><td>Platform</td><td>Percentage</td><td>Count</td></tr>
	<tr><td style="background-color: #494a69; width: 15px;"><input type="checkbox" id="filterlinux"></td><td style="background-color: #494a69;">Linux</td><td style="background-color: #494a69; text-align: center;">100%</td><td style="background-color: #494a69;">1</td></tr>
	<tr><td style="background-color: #494a69; width: 15px;"><input type="checkbox" id="filtermac"></td><td style="background-color: #494a69;">macOS</td><td style="background-color: #494a69; text-align: center;">0%</td><td style="background-color: #494a69;">0</td></tr>
	<tr><td style="background-color: #494a69; width: 15px;"><input type="checkbox" id="filterwin"></td><td style="background-color: #494a69;">Windows</td><td style="background-color: #494a69; text-align: center;">0%</td><td style="background-color: #494a69;">0</td></tr>
	</table>

	<span style="font-size: 15px; font-weight: bold;">Filter by Client Version:</span>
	<p>
	</p>
	</div>

</div>
