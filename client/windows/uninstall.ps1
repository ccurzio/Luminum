#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Luminum Client (Windows) uninstaller.

.DESCRIPTION
    Removes the Luminum Client completely, reversing everything install.ps1
    does: stops and deletes the LuminumClient Windows service, deletes the
    entire install directory (binary, config, logs, modules), and removes the
    Luminum registry entries.

    The install root is resolved in this order: an explicit -InstallRoot, the
    registry value HKLM\SOFTWARE\Luminum\LuminumClient\InstallRoot, then the
    default C:\Program Files\Luminum\LuminumClient.

    Registry entries removed:
      HKLM\SOFTWARE\Luminum\LuminumClient   (the InstallRoot value and key)
      HKLM\SOFTWARE\Luminum                 (only if left empty)
    The service's own SCM registry entry (HKLM\SYSTEM\CurrentControlSet\
    Services\LuminumClient) is removed by the service deletion.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File uninstall.ps1
    powershell -ExecutionPolicy Bypass -File uninstall.ps1 -InstallRoot D:\Luminum
#>
[CmdletBinding()]
param(
	[string]$InstallRoot = ""
)

$ErrorActionPreference = "Stop"

$svcName = "LuminumClient"
$regKey = "HKLM:\SOFTWARE\Luminum\LuminumClient"
$parentKey = "HKLM:\SOFTWARE\Luminum"
$defaultRoot = "C:\Program Files\Luminum\LuminumClient"

function Fail([string]$msg) {
	Write-Host "ERROR: $msg" -ForegroundColor Red
	exit 1
}

Write-Host "Luminum Client (Windows) uninstaller"
Write-Host "by Christopher R. Curzio <ccurzio@luminum.net>"
Write-Host ""

# --- must run as administrator (service removal + HKLM writes) ---------------
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
	Fail "must run as administrator (elevated shell required)"
}

# --- resolve the install root ------------------------------------------------
# An explicit -InstallRoot wins; otherwise the registry value; otherwise the
# default. Read the registry before it is removed below.
if (-not $InstallRoot) {
	if (Test-Path $regKey) {
		$InstallRoot = (Get-ItemProperty -Path $regKey -Name "InstallRoot" -ErrorAction SilentlyContinue).InstallRoot
	}
}
if (-not $InstallRoot) {
	$InstallRoot = $defaultRoot
}
$InstallRoot = $InstallRoot.TrimEnd('\')
Write-Host "Install root: $InstallRoot"

# --- safety: never recurse-delete a drive root or a system directory ---------
if (-not [System.IO.Path]::IsPathRooted($InstallRoot)) {
	Fail "install root is not an absolute path: $InstallRoot"
}
$driveRoot = [System.IO.Path]::GetPathRoot($InstallRoot).TrimEnd('\')
if ($InstallRoot -ieq $driveRoot) {
	Fail "refusing to delete a drive root: $InstallRoot"
}
foreach ($b in @("C:\Windows", "C:\Program Files", "C:\Program Files (x86)", "C:\ProgramData", "C:\Users")) {
	if ($InstallRoot -ieq $b) { Fail "refusing to delete a system directory: $InstallRoot" }
}

# --- stop and remove the service ---------------------------------------------
$svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
if ($svc) {
	Write-Host "Stopping service $svcName..."
	Stop-Service -Name $svcName -Force -ErrorAction SilentlyContinue
	Start-Sleep -Seconds 2
	Write-Host "Removing service $svcName..."
	& sc.exe delete $svcName | Out-Null
	if ($LASTEXITCODE -ne 0) {
		Write-Host "WARNING: 'sc.exe delete $svcName' returned $LASTEXITCODE" -ForegroundColor Yellow
	}
	Start-Sleep -Seconds 1
	if (Get-Service -Name $svcName -ErrorAction SilentlyContinue) {
		Write-Host "WARNING: service $svcName is still present after removal" -ForegroundColor Yellow
	} else {
		Write-Host "Removed service $svcName"
	}
} else {
	Write-Host "Service $svcName not present; skipping."
}

# --- stop any client process still running (e.g. launched in the foreground) -
Get-Process -Name "LuminumClient" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 1

# --- delete the install directory --------------------------------------------
if (Test-Path $InstallRoot) {
	Write-Host "Deleting $InstallRoot ..."
	Remove-Item -Path $InstallRoot -Recurse -Force
	Write-Host "Deleted $InstallRoot"
} else {
	Write-Host "Install directory not present; skipping."
}

# --- remove the registry entries ---------------------------------------------
if (Test-Path $regKey) {
	Write-Host "Removing registry key $regKey ..."
	Remove-Item -Path $regKey -Recurse -Force
}
# Remove the parent Luminum key only if it is now empty, so any other Luminum
# component's keys are left untouched.
if ((Test-Path $parentKey) -and -not (Get-ChildItem -Path $parentKey -ErrorAction SilentlyContinue)) {
	Write-Host "Removing now-empty registry key $parentKey ..."
	Remove-Item -Path $parentKey -Force
}

Write-Host ""
Write-Host "Luminum Client uninstalled."
exit 0
