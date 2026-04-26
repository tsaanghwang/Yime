@echo off
setlocal
set ROOT=%~dp0
set PYTHON_EXE=%ROOT%venv312\Scripts\python.exe

if not exist "%PYTHON_EXE%" (
  set PYTHON_EXE=%ROOT%.venv\Scripts\python.exe
)
if not exist "%PYTHON_EXE%" (
  echo Python virtual environment not found: "%PYTHON_EXE%"
  pause
  exit /b 1
)

start "Yime Input Method" "%PYTHON_EXE%" "%ROOT%run_input_method.py"

echo Yime Input Method started.
echo Exit by pressing ESC or closing the terminal.
