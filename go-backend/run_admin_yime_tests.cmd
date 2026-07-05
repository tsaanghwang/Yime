@echo off
setlocal

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

set "TMPDIR=%ROOT%\.tmp_go"
set "CACHEDIR=%ROOT%\.go_cache"
set "ENVLOG=%TMPDIR%\admin-yime-test.env.log"
set "TESTLOG=%TMPDIR%\admin-yime-test.full.log"
set "METALOG=%TMPDIR%\admin-yime-test.meta.log"

if not exist "%TMPDIR%" mkdir "%TMPDIR%"
if not exist "%CACHEDIR%" mkdir "%CACHEDIR%"

del /q "%ENVLOG%" "%TESTLOG%" "%METALOG%" 2>nul

set "TMP=%TMPDIR%"
set "TEMP=%TMPDIR%"
set "GOTMPDIR=%TMPDIR%"
set "GOCACHE=%CACHEDIR%"

cd /d "%ROOT%"

(
  echo TMP=%TMP%
  echo TEMP=%TEMP%
  echo GOTMPDIR=%GOTMPDIR%
  echo GOCACHE=%GOCACHE%
  go env TMP TEMP GOTMPDIR GOCACHE
) > "%ENVLOG%" 2>&1

go test ./input_methods/yime > "%TESTLOG%" 2>&1
set "EXITCODE=%ERRORLEVEL%"

> "%METALOG%" echo EXIT=%EXITCODE%
exit /b %EXITCODE%
