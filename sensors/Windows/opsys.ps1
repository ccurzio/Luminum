# Luminum "Operating System" Sensor (Windows)
# ===========================================

@echo off
for /f "tokens=2,* delims=:" %%A in ('systeminfo ^| findstr /B /C:"OS Name" /C:"OS Version"') do (
	if not defined OS_NAME (set "OS_NAME=%%B") 
    else (for /f "tokens=1" %%C in ("%%B") do set "OS_VERSION=%%C")
	)
echo %OS_NAME:~1% (%OS_VERSION%)
