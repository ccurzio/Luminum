# Luminum "Last Logged In User" Sensor (Windows)
# ==============================================

$p = Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" | Sort-Object CreationDate -Descending | Select-Object -First 1
if ($p) {
	(Invoke-CimMethod -InputObject $p -MethodName GetOwner).User
	}
else {
	(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI').LastLoggedOnSAMUser -replace '^.*\\'
	}
