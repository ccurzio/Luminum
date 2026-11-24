# Luminum "BIOS Information" Sensor (Windows)
# ===========================================

$b = Get-CimInstance -ClassName Win32_BIOS
"{0}|{1}|{2}.{3}|{4:MM/dd/yyyy}" -f $b.Manufacturer, $b.SMBIOSBIOSVersion, $b.SystemBiosMajorVersion, $b.SystemBiosMinorVersion, $b.ReleaseDate
