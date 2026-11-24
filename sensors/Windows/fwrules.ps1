# Luminum "Firewall Rules" Sensor (Windows)
# =========================================

$RegistryPaths = @(
	'HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\MDM\Firewall Rules',
	'HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\FirewallRules'
	)

if (-not ('FwRuleUtil.IndirectString' -as [type])) {
    Add-Type -Namespace FwRuleUtil -Name IndirectString -MemberDefinition @'
	[DllImport("shlwapi.dll", CharSet = CharSet.Unicode)]
	public static extern int SHLoadIndirectString(string pszSource, System.Text.StringBuilder pszOutBuf, int cchOutBuf, IntPtr ppvReserved);
	'@
	}

function Resolve-IndirectString {
	param([string]$Value)
	if ([string]::IsNullOrEmpty($Value) -or -not $Value.StartsWith('@')) { return $Value }
	$sb = New-Object System.Text.StringBuilder 1024
	if ([FwRuleUtil.IndirectString]::SHLoadIndirectString($Value, $sb, $sb.Capacity, [IntPtr]::Zero) -eq 0) {
		return $sb.ToString()
    	}
	return $Value
	}

function ConvertFrom-FirewallRuleString {
	param([string]$Data)
	$fields = @{}
	foreach ($token in ($Data -split '\|' | Select-Object -Skip 1)) {
		if ([string]::IsNullOrWhiteSpace($token)) { continue }
		$key, $value = $token -split '=', 2
		if (-not $fields.ContainsKey($key)) {
			$fields[$key] = New-Object System.Collections.Generic.List[string]
			}
		$fields[$key].Add($value)
		}
	return $fields
	}

function Get-FieldValue {
	param(
		[hashtable]$Fields,
		[string]$KeyPattern,
		[string]$Default = 'Any'
		)
	$values = foreach ($k in ($Fields.Keys | Where-Object { $_ -match $KeyPattern } | Sort-Object)) {
		$Fields[$k]
		}
	$values = @($values | Where-Object { $_ -ne $null -and $_ -ne '' })
	if ($values.Count -gt 0) { return ($values -join ';') }
	return $Default
	}

$ProtocolMap = @{
	'1'  = 'ICMPv4'
	'2'  = 'IGMP'
	'6'  = 'TCP'
	'17' = 'UDP'
	'41' = 'IPv6'
	'43' = 'IPv6-Route'
	'44' = 'IPv6-Frag'
	'47' = 'GRE'
	'58' = 'ICMPv6'
	'59' = 'IPv6-NoNxt'
	'60' = 'IPv6-Opts'
	'112' = 'VRRP'
	'113' = 'PGM'
	'115' = 'L2TP'
	}

$DirectionMap = @{
	'In'  = 'Inbound'
	'Out' = 'Outbound'
	}

$results = foreach ($path in $RegistryPaths) {
	if (-not (Test-Path -LiteralPath $path)) {
		Write-Warning "Registry key not found, skipping: $path"
		continue
		}

	$key = Get-Item -LiteralPath $path
	foreach ($valueName in $key.GetValueNames()) {
		$data = $key.GetValue($valueName)
		if ($data -isnot [string] -or -not $data.StartsWith('v')) { continue }

		$f = ConvertFrom-FirewallRuleString -Data $data

		$name = Get-FieldValue $f '^Name$' $valueName
		$dir  = Get-FieldValue $f '^Dir$' ''
		$proto = Get-FieldValue $f '^Protocol$' 'Any'
		if ($ProtocolMap.ContainsKey($proto)) { $proto = $ProtocolMap[$proto] }

		[pscustomobject][ordered]@{
			'Name'           = Resolve-IndirectString $name
			'Direction'      = $(if ($DirectionMap.ContainsKey($dir)) { $DirectionMap[$dir] } else { $dir })
			'Group'          = Resolve-IndirectString (Get-FieldValue $f '^EmbedCtxt$' '')
			'Profile'        = Get-FieldValue $f '^Profile$' 'All'
			'Enabled'        = [string]((Get-FieldValue $f '^Active$' 'FALSE') -eq 'TRUE')
			'Action'         = Get-FieldValue $f '^Action$' ''
			'Program'        = Get-FieldValue $f '^App$' 'Any'
			'Local Address'  = Get-FieldValue $f '^LA[46]$' 'Any'
			'Remote Address' = Get-FieldValue $f '^RA[46]$' 'Any'
			'Protocol'       = $proto
			'Local Port'     = Get-FieldValue $f '^LPort' 'Any'
			'Remote Port'    = Get-FieldValue $f '^RPort' 'Any'
			}
		}
	}

#$results | ConvertTo-Csv -NoTypeInformation
$results | ConvertTo-Csv -NoTypeInformation -Delimiter '|'