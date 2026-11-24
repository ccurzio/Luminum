# Luminum "Uptime" Sensor (Windows)
# =================================

$up = (Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
"{0} Days, {1}:{2:D2}" -f $up.Days, $up.Hours, $up.Minutes