@echo off
setlocal EnableExtensions

set "YIME_UPGRADE_ENTRY=1"
call "%~dp0Build-Install-YimeCore-Trial-v3.cmd" %*
set "YIME_UPGRADE_EXIT_CODE=%ERRORLEVEL%"

endlocal & exit /b %YIME_UPGRADE_EXIT_CODE%
