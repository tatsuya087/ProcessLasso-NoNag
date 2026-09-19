@echo off
setlocal
set "NONG_SHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "NONG_SHELL=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%NONG_SHELL%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\CLI.ps1"
if errorlevel 1 pause
