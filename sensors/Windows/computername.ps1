# Luminum "Computer Name" Sensor (Windows)
# ========================================

function Test-Fqdn([string]$Name) {
	$Name -and $Name.Contains('.') -and -not $Name.StartsWith('localhost', 'OrdinalIgnoreCase')
	}

$short = $env:COMPUTERNAME
$fqdn  = $null

try {
	$props = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties()
	if ($props.DomainName) { $fqdn = "$($props.HostName).$($props.DomainName)" }
	}
catch {}

if (-not (Test-Fqdn $fqdn)) {
	try { $fqdn = [System.Net.Dns]::GetHostEntry($short).HostName } catch {}
	}

if (Test-Fqdn $fqdn) { $fqdn.TrimEnd('.') } else { $short }
