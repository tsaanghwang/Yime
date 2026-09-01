@echo off
set "YIME_UPGRADE_ENTRY=1"
call "%~dp0Build-Install-YimeCore-Trial-v3.cmd" %*
exit /b %ERRORLEVEL%
