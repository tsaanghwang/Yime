@echo off
setlocal EnableExtensions

if /I not "%YIME_UPGRADE_ENTRY%"=="1" (
    echo NOTICE: This legacy filename is an upgrade-only compatibility entry point.
    echo Canonical command: "%~dp0Upgrade-YimeCore-Trial.cmd"
    echo.
)

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
echo Usage: Upgrade-YimeCore-Trial.cmd [/norestart]
echo.
echo   /norestart  Build, upgrade, and verify without restarting Windows.
exit /b 0

:usage_error
echo Usage: Upgrade-YimeCore-Trial.cmd [/norestart]
exit /b 2

:args_ready

tasklist.exe /FI "IMAGENAME eq WINWORD.EXE" 2>nul | find.exe /I "WINWORD.EXE" >nul
if not errorlevel 1 (
    echo ERROR: Microsoft Word is still running and may keep the old trial DLL loaded.
    echo Save your documents, close every Word window, and run this script again.
    pause
    exit /b 3
)

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
if not exist "%LOCALAPPDATA%\YimeCore Experimental Trial\runtime-config.json" (
    echo ERROR: No installed YimeCore trial configuration was found.
    echo Install a verified trial package once before using this upgrade entry point.
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
echo [1/6] Building and verifying the YimeCore trial package...
echo The currently installed, manifest-verified trial is used as the package base.
"%YIME_PS%" -NoProfile -ExecutionPolicy Bypass -File "%YIME_ROOT%\tools\yimecore\run-e6c-package-experiment.ps1" -OutputRoot "%YIME_OUT%"
if errorlevel 1 (
    echo.
    echo BUILD FAILED. Evidence directory:
    echo   %YIME_OUT%
    pause
    exit /b 1
)

echo [2/6] Installing the new trial package with one administrator confirmation...
echo The installer stages first and restores the previous trial if registration or startup fails.
"%YIME_PS%" -NoProfile -ExecutionPolicy Bypass -File "%YIME_ROOT%\tools\yimecore\manage-e6c-trial-install.ps1" -Action Install -PackageRoot "%YIME_OUT%\package" -Force
if errorlevel 1 (
    echo.
    echo INSTALL FAILED. Package directory:
    echo   %YIME_OUT%\package
    pause
    exit /b 1
)

echo [3/6] Repairing and verifying current-user autostart...
"%YIME_PS%" -NoProfile -ExecutionPolicy Bypass -File "%YIME_ROOT%\tools\yimecore\repair-e6c-trial-autostart.ps1" -OutputPath "%YIME_OUT%\installed-autostart-repair.json"
if errorlevel 1 (
    echo.
    echo INSTALL COMPLETED, BUT CURRENT-USER AUTOSTART VERIFICATION FAILED.
    pause
    exit /b 1
)

echo [4/6] Verifying the installed runtime and all three modes...
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

echo [5/6] Verifying this development machine's x64 TSF host only...
echo ARM64, x86 and other hardware targets are frozen, not accepted.
"%YIME_OUT%\package\x64\YimeRegisteredHostTests.exe" "\\.\pipe\YimeBroker.YimeCoreTrial.v1"
if errorlevel 1 (
    echo.
    echo X64 REGISTERED-HOST VERIFICATION FAILED.
    pause
    exit /b 1
)

echo [6/6] Reading back current-user autostart after all host checks...
"%YIME_PS%" -NoProfile -ExecutionPolicy Bypass -File "%YIME_ROOT%\tools\yimecore\repair-e6c-trial-autostart.ps1" -ValidateOnly -OutputPath "%YIME_OUT%\installed-autostart-final.json"
if errorlevel 1 (
    echo.
    echo INSTALL COMPLETED, BUT FINAL AUTOSTART READBACK FAILED. DO NOT REPORT ACCEPTANCE AS PASSED.
    echo Evidence directory: %YIME_OUT%
    pause
    exit /b 1
)

echo Build, installation, and live runtime verification completed successfully.
echo After reboot, verify autostart again; a currently running new process alone is not sufficient.
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
