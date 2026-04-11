@echo off
echo ========================================
echo   激活音元键盘
echo ========================================
echo.

echo 当前操作：将音元键盘添加到当前用户
echo.

REM 使用PowerShell添加键盘
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$preload = 'Registry::HKEY_CURRENT_USER\Keyboard Layout\Preload'; ^
     $substitutes = 'Registry::HKEY_CURRENT_USER\Keyboard Layout\Substitutes'; ^
     ^
     Write-Host '检查当前键盘列表...'; ^
     $current = Get-ItemProperty -Path $preload -ErrorAction SilentlyContinue; ^
     $hasYinyuan = $false; ^
     if ($current) { ^
         foreach ($prop in $current.PSObject.Properties) { ^
             if ($prop.Name -match '^[0-9]+$' -and $prop.Value -eq 'A0000804') { ^
                 $hasYinyuan = $true; ^
             } ^
         } ^
     } ^
     ^
     if ($hasYinyuan) { ^
         Write-Host '音元键盘已在列表中'; ^
     } else { ^
         Write-Host '添加音元键盘...'; ^
         ^
         REM 找到下一个可用的编号 ^
         $nextNum = 1; ^
         if ($current) { ^
             $nums = $current.PSObject.Properties | Where-Object { $_.Name -match '^[0-9]+$' } | ForEach-Object { [int]$_.Name }; ^
             if ($nums) { $nextNum = ($nums | Measure-Object -Maximum).Maximum + 1 } ^
         } ^
         ^
         REM 添加音元键盘 ^
         New-ItemProperty -Path $preload -Name $nextNum -Value 'A0000804' -PropertyType String -Force | Out-Null; ^
         ^
         REM 添加替换项 ^
         New-ItemProperty -Path $substitutes -Name 'A0000804' -Value 'A0000804' -PropertyType String -Force | Out-Null; ^
         ^
         Write-Host '音元键盘已添加'; ^
     }"

echo.
echo ========================================
echo   操作完成
echo ========================================
echo.
echo 重要提示：
echo 1. 需要注销并重新登录才能生效
echo 2. 或者重启系统
echo 3. 登录后使用 Win+Space 切换输入法
echo.
pause
