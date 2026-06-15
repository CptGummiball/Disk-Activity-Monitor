@echo off
title Disk Activity Monitor
:: ═══════════════════════════════════════════════════
::   Disk Activity Monitor - Launcher
::   Doppelklick genuegt - keine Installation noetig
:: ═══════════════════════════════════════════════════

:: Attempt to run as admin for full process visibility
net session >nul 2>&1
if errorlevel 1 (
    echo.
    echo   Starte mit Administrator-Rechten fuer volle Sichtbarkeit...
    echo   (Falls UAC-Dialog erscheint, bitte bestaetigen)
    echo.
    powershell -Command "Start-Process cmd -ArgumentList '/c cd /d \"%~dp0\" && powershell.exe -ExecutionPolicy Bypass -NoProfile -File \"%~dp0DiskMonitor.ps1\"' -Verb RunAs" 2>nul
    if errorlevel 1 (
        echo   Konnte nicht als Admin starten - starte normal...
        powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0DiskMonitor.ps1"
    )
) else (
    powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0DiskMonitor.ps1"
)
