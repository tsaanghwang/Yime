@echo off
setlocal

cd /d "%~dp0\.."

if exist "venv312\Scripts\python.exe" (
  set "PYTHON=venv312\Scripts\python.exe"
) else if exist ".venv\Scripts\python.exe" (
  set "PYTHON=.venv\Scripts\python.exe"
) else (
  set "PYTHON=python"
)

echo Phase 1: dry-run BCC word frequency import...
"%PYTHON%" yime\import_blcu_word_frequency.py --dry-run
if errorlevel 1 exit /b %ERRORLEVEL%

echo.
echo Phase 2: apply BCC word frequency import...
"%PYTHON%" yime\import_blcu_word_frequency.py
exit /b %ERRORLEVEL%
