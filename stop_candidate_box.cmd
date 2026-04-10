@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'windows_candidate_box\.py' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }"
echo Yime Candidate Box stopped.
