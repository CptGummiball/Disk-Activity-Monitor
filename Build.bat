@echo off
title Disk Activity Monitor - Build
echo.
echo   Building DiskMonitor.exe ...
echo.
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0Build.ps1"
echo.
pause
