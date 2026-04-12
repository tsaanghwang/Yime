# 设置 Windows Terminal 字体为 Noto Sans

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  设置终端字体为 Noto Sans" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 检查 Noto Sans 字体是否可用
Write-Host "检查 Noto Sans 字体..." -ForegroundColor Yellow

try {
    $fonts = [System.Drawing.FontFamily]::Families
    $notoSans = $fonts | Where-Object { $_.Name -eq "Noto Sans" }

    if ($notoSans) {
        Write-Host "✓ Noto Sans 字体已安装" -ForegroundColor Green
    } else {
        Write-Host "✗ Noto Sans 字体未安装" -ForegroundColor Red
        Write-Host ""
        Write-Host "请先安装 Noto Sans 字体：" -ForegroundColor Yellow
        Write-Host "1. 访问 https://fonts.google.com/noto" -ForegroundColor White
        Write-Host "2. 下载并安装 Noto Sans 字体" -ForegroundColor White
        Write-Host ""
        exit 1
    }
} catch {
    Write-Host "无法检查字体，继续配置..." -ForegroundColor Yellow
}

# Windows Terminal 配置文件路径
$settingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"

Write-Host ""
Write-Host "配置 Windows Terminal..." -ForegroundColor Yellow

if (Test-Path $settingsPath) {
    Write-Host "找到 Windows Terminal 配置文件" -ForegroundColor Green

    # 读取配置
    $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json

    # 设置默认字体
    if (-not $settings.profiles.defaults) {
        $settings.profiles | Add-Member -MemberType NoteProperty -Name "defaults" -Value @{} -Force
    }

    if (-not $settings.profiles.defaults.font) {
        $settings.profiles.defaults | Add-Member -MemberType NoteProperty -Name "font" -Value @{} -Force
    }

    $settings.profiles.defaults.font | Add-Member -MemberType NoteProperty -Name "face" -Value "Noto Sans" -Force
    $settings.profiles.defaults.font | Add-Member -MemberType NoteProperty -Name "size" -Value 12 -Force

    # 保存配置
    $settings | ConvertTo-Json -Depth 10 | Set-Content $settingsPath -Encoding UTF8

    Write-Host "✓ Windows Terminal 配置已更新" -ForegroundColor Green
} else {
    Write-Host "未找到 Windows Terminal 配置文件" -ForegroundColor Yellow
    Write-Host "请手动配置 Windows Terminal 字体" -ForegroundColor Yellow
}

# PowerShell 配置文件
Write-Host ""
Write-Host "配置 PowerShell..." -ForegroundColor Yellow

$psProfile = $PROFILE

if (Test-Path $psProfile) {
    Write-Host "找到 PowerShell 配置文件: $psProfile" -ForegroundColor Green

    # 检查是否已配置
    $profileContent = Get-Content $psProfile -Raw

    if ($profileContent -match "FontName.*Noto Sans") {
        Write-Host "✓ PowerShell 已配置 Noto Sans 字体" -ForegroundColor Green
    } else {
        # 添加字体配置
        $fontConfig = @"

# 设置终端字体为 Noto Sans
if (`$Host.UI.RawUI) {
    try {
        `$Host.UI.RawUI.FontName = "Noto Sans"
    } catch {
        # 某些终端不支持字体设置
    }
}
"@

        Add-Content -Path $psProfile -Value $fontConfig -Encoding UTF8
        Write-Host "✓ PowerShell 配置已更新" -ForegroundColor Green
    }
} else {
    Write-Host "PowerShell 配置文件不存在，创建新文件" -ForegroundColor Yellow

    $fontConfig = @"
# 设置终端字体为 Noto Sans
if (`$Host.UI.RawUI) {
    try {
        `$Host.UI.RawUI.FontName = "Noto Sans"
    } catch {
        # 某些终端不支持字体设置
    }
}
"@

    New-Item -Path $psProfile -ItemType File -Force | Out-Null
    Add-Content -Path $psProfile -Value $fontConfig -Encoding UTF8
    Write-Host "✓ PowerShell 配置已创建" -ForegroundColor Green
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  配置完成" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "重要提示：" -ForegroundColor Yellow
Write-Host "1. 需要重启终端才能生效" -ForegroundColor White
Write-Host "2. Windows Terminal: 关闭并重新打开" -ForegroundColor White
Write-Host "3. PowerShell: 关闭并重新打开" -ForegroundColor White
Write-Host "4. CMD: 右键标题栏 → 属性 → 字体 → 选择 Noto Sans" -ForegroundColor White
Write-Host ""
Write-Host "测试私用区字符：" -ForegroundColor Yellow
Write-Host "  python -c `"print('\uE4F1 \uE4E9')`"" -ForegroundColor White
Write-Host ""

