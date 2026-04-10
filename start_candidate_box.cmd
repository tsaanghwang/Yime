@echo off
setlocal
set ROOT=%~dp0
set PYTHON_EXE=%ROOT%.venv\Scripts\python.exe

if not exist "%PYTHON_EXE%" (
  echo Python virtual environment not found: "%PYTHON_EXE%"
  pause
  exit /b 1
)

start "Yime Candidate Box" "%PYTHON_EXE%" "%ROOT%yime\windows_candidate_box.py"

echo Yime Candidate Box started.
echo Exit from the window's 退出 button, Ctrl+Alt+Q, or stop_candidate_box.cmd.
