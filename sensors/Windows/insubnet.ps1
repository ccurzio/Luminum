# Luminum "In Subnet" Sensor (Windows)
# ====================================

param([string]$Subnet)

function Test-InSubnet([string]$Subnet) {
	if ($Subnet -notmatch '^([^/]+)/(\d{1,3})$') { return $false }
	$netStr = $Matches[1]
	$prefix = [int]$Matches[2]

	if ($netStr -notmatch ':' -and $netStr -notmatch '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') { return $false }

	$net = $null
	if (-not [System.Net.IPAddress]::TryParse($netStr, [ref]$net)) { return $false }
	$netBytes = $net.GetAddressBytes()
	if ($prefix -gt $netBytes.Length * 8) { return $false }

	$fullBytes = [math]::Floor($prefix / 8)
	$remBits = $prefix % 8
	$mask = (0xFF -shl (8 - $remBits)) -band 0xFF

	foreach ($nic in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
		foreach ($ua in $nic.GetIPProperties().UnicastAddresses) {
			$b = $ua.Address.GetAddressBytes()
			if ($b.Length -ne $netBytes.Length) { continue }

			$match = $true
			for ($i = 0; $i -lt $fullBytes; $i++) {
				if ($b[$i] -ne $netBytes[$i]) { $match = $false; break }
				}
			if ($match -and $remBits -gt 0) {
				if (($b[$fullBytes] -band $mask) -ne ($netBytes[$fullBytes] -band $mask)) { $match = $false }
				}
			if ($match) { return $true }
			}
		}
	return $false
	}

try { if (Test-InSubnet $Subnet) { 'TRUE' } else { 'FALSE' } }
catch { 'FALSE' }
