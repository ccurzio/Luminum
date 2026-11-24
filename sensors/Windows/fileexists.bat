REM Luminum "File Exists" Sensor (Windows)
REM ======================================

@echo off

if exist "%~1" (
	echo TRUE
) else (
	echo FALSE
)
