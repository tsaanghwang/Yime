@echo off
setlocal EnableExtensions

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
echo [1/4] Building and verifying the YimeCore trial package...
"%YIME_PS%" -NoProfile -ExecutionPolicy Bypass -File "%YIME_ROOT%\tools\yimecore\run-e6c-package-experiment.ps1" -BasePackageRoot "%YIME_BASE%" -OutputRoot "%YIME_OUT%"
if errorlevel 1 (
    echo.
    echo BUILD FAILED. Evidence directory:
    echo   %YIME_OUT%
    pause
    exit /b 1
)

echo [2/4] Force-uninstalling the existing YimeCore trial package...
"%YIME_PS%" -NoProfile -ExecutionPolicy Bypass -File "%YIME_ROOT%\tools\yimecore\manage-e6c-trial-install.ps1" -Action Uninstall -Force
if errorlevel 1 (
    echo.
    echo UNINSTALL FAILED.
    pause
    exit /b 1
)

echo [3/4] Installing the new trial package from a clean registration state...
"%YIME_PS%" -NoProfile -ExecutionPolicy Bypass -File "%YIME_ROOT%\tools\yimecore\manage-e6c-trial-install.ps1" -Action Install -PackageRoot "%YIME_OUT%\package" -Force
if errorlevel 1 (
    echo.
    echo INSTALL FAILED. Package directory:
    echo   %YIME_OUT%\package
    pause
    exit /b 1
)

echo [4/4] Build, uninstall, and installation completed successfully.
echo Evidence directory:
echo   %YIME_OUT%
echo.
if /I "%~1"=="/norestart" (
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
