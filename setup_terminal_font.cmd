setup_terminal_font.cmd@echo off
echo ========================================
echo   设置终端字体为 Noto Sans
echo ========================================
echo.

REM 运行 PowerShell 脚本
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup_terminal_font.ps1"

echo.
pause
