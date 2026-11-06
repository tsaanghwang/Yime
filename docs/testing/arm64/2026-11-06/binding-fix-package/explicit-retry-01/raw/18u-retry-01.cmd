@echo off
setlocal
echo [%date% %time%] 18u installer entry opened.>>"%~dp018u-entry-start.log"
chcp 65001 >nul
title 18u 修复版安装 - 先检查占用
echo 18u 修复版安装入口已经打开，正在检查，不需要先按键。
echo 这不是触摸键盘。每个阶段都会显示结果并保存日志。
if not exist "C:\Users\tsaan\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe" (
  echo 未找到本入口所需的本地运行程序。安装没有启动。请回到 Codex 核对。
  echo Local Python missing; installation not started.>>"%~dp018u-entry-start.log"
  pause
  exit /b 1
)
"C:\Users\tsaan\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe" -u "%~dp0run_18u_binding_retry_01.py"
set "YIME_BINDING_ENTRY_EXIT=%errorlevel%"
echo.
echo 本次入口返回值：%YIME_BINDING_ENTRY_EXIT%
echo 请保留当前显示和同目录的新日志，回到 Codex 核对结果。
pause
exit /b %YIME_BINDING_ENTRY_EXIT%
