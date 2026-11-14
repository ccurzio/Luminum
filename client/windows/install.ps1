#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Luminum Client (Windows) installer.

.DESCRIPTION
    Barebones installer: copies the client binary (and any Lumy modules) to
    the install root, records the install root in the registry, imports the
    provisioning file (config.ini) or runs the setup wizard, and creates the
    LuminumClient Windows service (auto-start, restart on failure).

    Installed layout:
      <root>\LuminumClient.exe
      <root>\config\    client.conf.db, server.crt, server-signing.crt
      <root>\logs\      client.log
      <root>\modules\   Lumy module binaries

    Registry:
      HKLM\SOFTWARE\Luminum\LuminumClient\InstallRoot = <root>

    Out-of-band provisioning: the distribution may ship an infra-specific
    config.ini (a self-contained JSON document) next to this script or in
    dist\. When one is found and the client is not yet configured, it is
    imported non-interactively (LuminumClient.exe --import) in place of the
    interactive wizard; otherwise the wizard still runs. An explicit
    -Provision always wins over auto-discovery.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File install.ps1
    powershell -ExecutionPolicy Bypass -File install.ps1 -InstallRoot D:\Luminum -Provision C:\provision\config.ini
#>
[CmdletBinding()]
param(
	[string]$InstallRoot = "C:\Program Files\Luminum\LuminumClient",
	[string]$Binary = "",
	[string]$Provision = "",
	[switch]$NoSetup,
	[switch]$NoStart
)

$ErrorActionPreference = "Stop"

function Fail([string]$msg) {
	Write-Host "ERROR: $msg" -ForegroundColor Red
	exit 1
}

Write-Host "Luminum Client (Windows) installer"
Write-Host "by Christopher R. Curzio <ccurzio@luminum.net>"
Write-Host ""

# --- must run as administrator (HKLM writes + service creation) --------------
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
	Fail "must run as administrator (elevated shell required)"
}

$scriptDir = $PSScriptRoot

# --- provisioning file (out-of-band setup) -----------------------------------
# An explicit -Provision always wins; otherwise auto-detect config.ini next to
# the installer, then in dist\. Empty means "no provisioning file" -> wizard.
$provisionFile = ""
if ($Provision) {
	$provisionFile = $Provision
} elseif (Test-Path (Join-Path $scriptDir "config.ini")) {
	$provisionFile = Join-Path $scriptDir "config.ini"
} elseif (Test-Path (Join-Path $scriptDir "dist\config.ini")) {
	$provisionFile = Join-Path $scriptDir "dist\config.ini"
}

# --- obtain the client binary ------------------------------------------------
if ($Binary) {
	$clientBin = $Binary
} else {
	$clientBin = Join-Path $scriptDir "dist\LuminumClient.exe"
}
if (-not (Test-Path $clientBin)) {
	Fail "missing binary: $clientBin (the distribution must include the prebuilt LuminumClient.exe in dist\)"
}

# --- install layout ----------------------------------------------------------
foreach ($d in @("config", "logs", "modules")) {
	$p = Join-Path $InstallRoot $d
	if (-not (Test-Path $p)) { New-Item -Path $p -ItemType Directory -Force | Out-Null }
}

$exePath = Join-Path $InstallRoot "LuminumClient.exe"
Copy-Item -Path $clientBin -Destination $exePath -Force
Write-Host "Installed $exePath"

# --- Lumy modules ------------------------------------------------------------
# Each directory under dist\modules\ mirrors its installed location:
# dist\modules\<lumy>\Lumy_* -> <root>\modules\<lumy>\Lumy_*.
$modDist = Join-Path $scriptDir "dist\modules"
if (Test-Path $modDist) {
	Get-ChildItem -Path $modDist -Directory | ForEach-Object {
		$mname = $_.Name
		$files = Get-ChildItem -Path $_.FullName -File -Filter "Lumy_*"
		if ($files) {
			$dest = Join-Path $InstallRoot "modules\$mname"
			New-Item -Path $dest -ItemType Directory -Force | Out-Null
			$files | ForEach-Object { Copy-Item -Path $_.FullName -Destination $dest -Force }
			Write-Host "Installed module $mname ($($files.Count) file(s))"
		}
	}
}

# --- registry: record the install root ---------------------------------------
# The client (and every Lumy) resolve their install root from this value.
$regPath = "HKLM:\SOFTWARE\Luminum\LuminumClient"
if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
Set-ItemProperty -Path $regPath -Name "InstallRoot" -Value $InstallRoot
Write-Host "Registry: $regPath\InstallRoot = $InstallRoot"

# --- configuration (provisioning import, else wizard) ------------------------
$confDb = Join-Path $InstallRoot "config\client.conf.db"
if (Test-Path $confDb) {
	Write-Host "Client already configured; skipping setup."
} elseif (-not $NoSetup) {
	if ($provisionFile) {
		if (-not (Test-Path $provisionFile)) { Fail "provisioning file not found: $provisionFile" }
		Write-Host ""
		Write-Host "Importing provisioning file: $provisionFile"
		& "$exePath" --import $provisionFile
		if ($LASTEXITCODE -ne 0) {
			Write-Host ""
			Write-Host "Provisioning import failed; re-run '$exePath --import $provisionFile' and start the service manually." -ForegroundColor Red
			exit 1
		}
	} else {
		Write-Host ""
		Write-Host "No provisioning file found; running the interactive setup wizard."
		& "$exePath" -s
		if ($LASTEXITCODE -ne 0) {
			Write-Host ""
			Write-Host "Configuration wizard failed; re-run '$exePath -s' and start the service manually." -ForegroundColor Red
			exit 1
		}
	}
}

# --- service (auto-start, restart on failure) --------------------------------
$svcName = "LuminumClient"
$existing = Get-Service -Name $svcName -ErrorAction SilentlyContinue
if ($existing) {
	Write-Host "Replacing existing $svcName service..."
	Stop-Service -Name $svcName -Force -ErrorAction SilentlyContinue
	Start-Sleep -Seconds 2
	sc.exe delete $svcName | Out-Null
	Start-Sleep -Seconds 1
}
New-Service -Name $svcName -BinaryPathName $exePath -DisplayName "Luminum Client" -StartupType Automatic | Out-Null
# Restart on failure: retry at 5s, 10s, 30s; reset the failure counter after 24h.
sc.exe failure $svcName reset= 86400 actions= restart/5000/restart/10000/restart/30000 | Out-Null
Write-Host "Created service $svcName (auto-start, restart on failure)"

# --- start -------------------------------------------------------------------
if (-not $NoStart) {
	if (-not (Test-Path $confDb)) {
		Write-Host "Client is not configured; skipping start (run '$exePath -s' first)."
	} else {
		Start-Service -Name $svcName
		Start-Sleep -Seconds 2
		$st = Get-Service -Name $svcName
		if ($st.Status -ne "Running") {
			Write-Host "ERROR: $svcName service is not running after start" -ForegroundColor Red
			exit 1
		}
		Write-Host "Started service $svcName"
	}
}

Write-Host ""
Write-Host "Luminum Client installed:"
Write-Host "  Install root:  $InstallRoot"
Write-Host "  Service:       $svcName (manage via services.msc)"
Write-Host "  Configure:     $exePath -s"
Write-Host "  Logs:          $(Join-Path $InstallRoot 'logs\client.log')"
exit 0
