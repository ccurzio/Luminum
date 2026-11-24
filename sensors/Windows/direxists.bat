REM Luminum "Directory Exists" Sensor (Windows)
REM ===========================================

@echo off

if exist "%~1" (
	echo TRUE
) else (
	echo FALSE
)