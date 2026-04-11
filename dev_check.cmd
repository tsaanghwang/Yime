@echo off
echo ========================================
echo   开发环境快速检查
echo ========================================
echo.

echo [1/2] 检查进程状态...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$procs = Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'input_method|windows_candidate_box' }; if ($procs) { Write-Host '⚠ 发现运行中的进程:'; $procs | ForEach-Object { Write-Host ('  PID: ' + $_.ProcessId + ' - ' + $_.Name) } } else { Write-Host '✓ 没有运行中的进程' }"

echo.
echo [2/2] 检查锁文件...
if exist yime.lock (
    echo ⚠ 发现锁文件: yime.lock
) else (
    echo ✓ 没有锁文件
)
if exist yime.pid (
    echo ⚠ 发现PID文件: yime.pid
) else (
    echo ✓ 没有PID文件
)

echo.
echo ========================================
echo   检查完成
echo ========================================
pause
