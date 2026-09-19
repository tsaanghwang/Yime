@echo off
setlocal
rem Read-only preview. Run by double-clicking in File Explorer so Windows returns
rem the non-virtualized user-language-list view used by Apply.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\yimecore\retire-legacy-entry.ps1" -Action Plan
if errorlevel 1 echo Plan did not complete. No language-list write was requested.
pause

