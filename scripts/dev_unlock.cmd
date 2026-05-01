@echo off
echo ========================================
echo   音元输入法快速解锁工具
echo ========================================
echo.

REM 1. 停止所有相关进程
echo [1/3] 停止所有相关进程...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'input_method|windows_candidate_box' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }"
echo ✓ 进程已停止

REM 2. 清理锁文件
echo.
echo [2/3] 清理锁文件...
if exist yime.lock del /f /q yime.lock 2>nul
if exist yime.pid del /f /q yime.pid 2>nul
if exist yime_state.json del /f /q yime_state.json 2>nul
echo ✓ 锁文件已清理

REM 3. 验证清理结果
echo.
echo [3/3] 验证清理结果...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$procs = Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'input_method|windows_candidate_box' }; if ($procs) { Write-Host '⚠ 仍有进程运行:'; $procs | ForEach-Object { Write-Host ('  PID: ' + $_.ProcessId + ' - ' + $_.Name) } } else { Write-Host '✓ 所有进程已清理' }"

echo.
echo ========================================
echo   解锁完成！可以重新启动应用
echo ========================================
pause