@echo off
setlocal
rem Run from File Explorer as the ordinary MYCOMPUTER user. This removes only
rem the exact legacy user-language-list entry; it does not delete files or
rem unregister any input method. The PowerShell tool creates recovery evidence.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\yimecore\retire-legacy-entry.ps1" -Action Apply
if errorlevel 1 (
  echo Retirement did not complete. Preserve the displayed evidence path.
) else (
  echo Legacy user entry retired. Registrations and historical files were preserved.
)
pause

