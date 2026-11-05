@echo off
setlocal
title Yime 18u ARM64 .5 repair installation
if exist "%~dp0installation-output.log" (
  echo A previous installation attempt is recorded. Preserve its logs and return to Codex.
  pause
  exit /b 1
)
echo Save your documents and close Codex and Notepad before continuing.
echo If Explorer keeps the old input component loaded, restart Windows first.
echo This entry uses the standard installer and Windows UAC.
pause
cd /d "%~dp0package"
if errorlevel 1 exit /b 1
YimeMaintenance.exe -action Check > "%~dp0package-check-on-install.log" 2>&1
if errorlevel 1 (
  type "%~dp0package-check-on-install.log"
  pause
  exit /b 1
)
YimeMaintenance.exe -action Install > "%~dp0installation-output.log" 2>&1
set "YIME_BINDING_INSTALL_EXIT=%errorlevel%"
type "%~dp0installation-output.log"
echo.
echo Installer exit code: %YIME_BINDING_INSTALL_EXIT%
echo Keep this output and the Yime Setup Logs folder. Return to Codex for verification.
pause
exit /b %YIME_BINDING_INSTALL_EXIT%
