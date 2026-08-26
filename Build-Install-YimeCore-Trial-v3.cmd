@echo off
setlocal EnableExtensions

set "YIME_NORESTART=0"
:parse_args
if "%~1"=="" goto args_ready
if /I "%~1"=="/norestart" (
    set "YIME_NORESTART=1"
    shift
    goto parse_args
)
if /I "%~1"=="/help" goto usage
if /I "%~1"=="/?" goto usage
echo ERROR: Unknown argument: %~1
echo.
goto usage_error

:usage
echo Usage: %~nx0 [/norestart]
echo.
echo   /norestart  Build, install, and verify without restarting Windows.
exit /b 0

:usage_error
echo Usage: %~nx0 [/norestart]
exit /b 2

:args_ready

set "YIME_ROOT=C:\dev\Yime"
if exist "%~dp0tools\yimecore\run-e6c-package-experiment.ps1" (
    for %%I in ("%~dp0.") do set "YIME_ROOT=%%~fI"
)
cd /d "%YIME_ROOT%"

if /I "%YIME_FORCE_WINDOWS_POWERSHELL%"=="1" goto use_windows_powershell
where pwsh.exe >nul 2>&1
if errorlevel 1 (
    goto use_windows_powershell
) else (
    set "YIME_PS=pwsh.exe"
    goto powershell_ready
)

:use_windows_powershell
    set "PSModulePath=%SystemRoot%\System32\WindowsPowerShell\v1.0\Modules;%PSModulePath%"
    set "YIME_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
:powershell_ready
set "YIME_BASE=%YIME_ROOT%\.tmp\yimecore-experiment\e6c\20260824-language-bar-final\package"

if not exist "%YIME_BASE%\package-manifest.json" (
    echo ERROR: Base package is missing:
    echo   %YIME_BASE%
    pause
    exit /b 2
)

set "YIME_STAMP=%RANDOM%-%RANDOM%"
set "YIME_OUT=%YIME_ROOT%\.tmp\yimecore-experiment\e6c\local-%YIME_STAMP%"

echo YIME_CLICK_VERSION=3
echo YIME_ROOT=%YIME_ROOT%
echo YIME_POWERSHELL=%YIME_PS%
echo YIME_OUTPUT=%YIME_OUT%
echo.
echo [1/3] Building and verifying the YimeCore trial package...
"%YIME_PS%" -NoProfile -ExecutionPolicy Bypass -File "%YIME_ROOT%\tools\yimecore\run-e6c-package-experiment.ps1" -BasePackageRoot "%YIME_BASE%" -OutputRoot "%YIME_OUT%"
if errorlevel 1 (
    echo.
    echo BUILD FAILED. Evidence directory:
    echo   %YIME_OUT%
    pause
    exit /b 1
)

echo [2/3] Installing the new trial package with one administrator confirmation...
echo The installer performs its own forced pre-cleanup and removes partial state after failure.
"%YIME_PS%" -NoProfile -ExecutionPolicy Bypass -File "%YIME_ROOT%\tools\yimecore\manage-e6c-trial-install.ps1" -Action Install -PackageRoot "%YIME_OUT%\package" -Force
if errorlevel 1 (
    echo.
    echo INSTALL FAILED. Package directory:
    echo   %YIME_OUT%\package
    pause
    exit /b 1
)

echo [3/3] Verifying the installed runtime and all three modes...
"%YIME_PS%" -NoProfile -ExecutionPolicy Bypass -File "%YIME_ROOT%\tools\yimecore\verify-e6c-trial-runtime.ps1"
if errorlevel 1 (
    echo.
    echo INSTALL COMPLETED, BUT LIVE RUNTIME VERIFICATION FAILED.
    echo Package directory:
    echo   %YIME_OUT%\package
    echo Runtime diagnostics:
    echo   %LOCALAPPDATA%\YimeCore Experimental Trial
    pause
    exit /b 1
)

echo Build, installation, and live runtime verification completed successfully.
echo Evidence directory:
echo   %YIME_OUT%
echo.
if "%YIME_NORESTART%"=="1" (
    echo Restart skipped by /norestart. Restart Windows before checking the taskbar language item.
    exit /b 0
)
choice /C YN /N /M "Restart Windows now? Save all work first. [Y/N]: "
if errorlevel 2 (
    echo Restart skipped. Restart Windows before checking the taskbar language item.
    pause
    exit /b 0
)

shutdown.exe /r /t 0
exit /b 0
