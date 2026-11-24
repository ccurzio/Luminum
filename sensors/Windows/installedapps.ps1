# Luminum "Installed Applications" Sensor (Windows)
# =================================================

$uninstallPaths = @(
	'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
	'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
	)

function Get-UninstallEntries([Microsoft.Win32.RegistryKey]$Root) {
	foreach ($path in $uninstallPaths) {
		$key = $Root.OpenSubKey($path)
		if (-not $key) { continue }
		foreach ($sub in $key.GetSubKeyNames()) {
			$entry = $key.OpenSubKey($sub)
			if (-not $entry) { continue }
			$name = $entry.GetValue('DisplayName')
			if ($name -and $entry.GetValue('SystemComponent') -ne 1
			-and -not $entry.GetValue('ParentKeyName')
			-and $entry.GetValue('ReleaseType') -notmatch 'Update|Hotfix') {
				"$name|$($entry.GetValue('DisplayVersion'))"
				}
			$entry.Close()
			}
		$key.Close()
		}
	}

$hklm = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', 'Registry64')
$hku  = [Microsoft.Win32.RegistryKey]::OpenBaseKey('Users', 'Registry64')

$output = & {
	Get-UninstallEntries $hklm
	$profiles = $hklm.OpenSubKey('SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList')

	foreach ($sid in $profiles.GetSubKeyNames() | Where-Object { $_ -like 'S-1-5-21-*' }) {
		$userKey = $hku.OpenSubKey($sid)
		if ($userKey) {
			Get-UninstallEntries $userKey
			$userKey.Close()
			continue
			}

		$profileKey = $profiles.OpenSubKey($sid)
		$profilePath = $profileKey.GetValue('ProfileImagePath')
		$profileKey.Close()
		if (-not $profilePath) { continue }
		$hive = Join-Path $profilePath 'NTUSER.DAT'
		if (-not (Test-Path -LiteralPath $hive)) { continue }

		$temp = "TempHive_$sid"
		reg.exe load "HKU\$temp" "$hive" *> $null
		if ($LASTEXITCODE -ne 0) { continue }

		$userKey = $hku.OpenSubKey($temp)
		if ($userKey) {
			Get-UninstallEntries $userKey
			$userKey.Close()
			}
		[gc]::Collect()
		[gc]::WaitForPendingFinalizers()
		reg.exe unload "HKU\$temp" *> $null
		}
	$profiles.Close()

	Get-AppxPackage -AllUsers -PackageTypeFilter Main -ErrorAction SilentlyContinue |
	Where-Object { -not $_.IsFramework } | ForEach-Object { "$($_.Name)|$($_.Version)" }
	}

$output | Sort-Object -Unique
