@echo off
setlocal
cd /d "%~dp0"
python tools\powershell\run_checked.py --script tools\dual-product\prepare-rime-pime-coexistence-test.ps1 --edition ps5 --params-file test-delivery\rime-pime-coexistence-20260911\prepare-parameters.json
if errorlevel 1 (
  echo Preparation failed. Preserve the error. Do not run the installer.
) else (
  echo Preparation complete. Follow the handoff document with the displayed execution parameters.
)
pause
