# Python 3.12 安装脚本
# 以管理员身份运行 PowerShell

Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host "Python 3.12 安装脚本" -ForegroundColor Green
Write-Host "=" * 60 -ForegroundColor Cyan

# 检查是否以管理员身份运行
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "警告: 建议以管理员身份运行" -ForegroundColor Yellow
}

# 1. 检查 pyenv-win
Write-Host "`n[1/7] 检查 pyenv-win..." -ForegroundColor Yellow
if (Get-Command pyenv -ErrorAction SilentlyContinue) {
    Write-Host "  pyenv-win 已安装" -ForegroundColor Green
    pyenv --version
} else {
    Write-Host "  安装 pyenv-win..." -ForegroundColor Yellow
    try {
        Invoke-WebRequest -UseBasicParsing https://raw.githubusercontent.com/pyenv-win/pyenv-win/master/pyenv-win/install.ps1 | iex
        Write-Host "  pyenv-win 安装成功" -ForegroundColor Green
    } catch {
        Write-Host "  pyenv-win 安装失败: $_" -ForegroundColor Red
        Write-Host "  请手动安装: https://github.com/pyenv-win/pyenv-win" -ForegroundColor Yellow
        exit 1
    }
}

# 2. 安装 Python 3.12
Write-Host "`n[2/7] 安装 Python 3.12.8..." -ForegroundColor Yellow
try {
    pyenv install 3.12.8 -f
    Write-Host "  Python 3.12.8 安装成功" -ForegroundColor Green
} catch {
    Write-Host "  Python 3.12.8 安装失败: $_" -ForegroundColor Red
    Write-Host "  尝试手动安装..." -ForegroundColor Yellow
    Write-Host "  下载: https://www.python.org/downloads/release/python-3128/" -ForegroundColor Cyan
    exit 1
}

# 3. 设置项目 Python 版本
Write-Host "`n[3/7] 设置项目 Python 版本..." -ForegroundColor Yellow
$projectDir = $PSScriptRoot
if (-not $projectDir) {
    $projectDir = Get-Location
}
Set-Location $projectDir
pyenv local 3.12.8
Write-Host "  项目 Python 版本设置为 3.12.8" -ForegroundColor Green

# 4. 创建虚拟环境
Write-Host "`n[4/7] 创建虚拟环境..." -ForegroundColor Yellow
if (Test-Path "venv312") {
    Write-Host "  虚拟环境已存在，跳过创建" -ForegroundColor Yellow
} else {
    python -m venv venv312
    Write-Host "  虚拟环境创建成功" -ForegroundColor Green
}

# 5. 激活虚拟环境
Write-Host "`n[5/7] 激活虚拟环境..." -ForegroundColor Yellow
& ".\venv312\Scripts\Activate.ps1"
Write-Host "  虚拟环境已激活" -ForegroundColor Green

# 6. 安装依赖
Write-Host "`n[6/7] 安装依赖..." -ForegroundColor Yellow
Write-Host "  升级 pip..." -ForegroundColor Cyan
python -m pip install --upgrade pip

Write-Host "  安装 pywin32..." -ForegroundColor Cyan
pip install pywin32

Write-Host "  安装 pynput..." -ForegroundColor Cyan
pip install pynput

Write-Host "  安装其他依赖..." -ForegroundColor Cyan
pip install pytest coverage tqdm

Write-Host "  依赖安装完成" -ForegroundColor Green

# 7. 验证安装
Write-Host "`n[7/7] 验证安装..." -ForegroundColor Yellow

Write-Host "  Python 版本:" -ForegroundColor Cyan
python --version

Write-Host "`n  pywin32:" -ForegroundColor Cyan
try {
    python -c "import win32api; print('    OK - pywin32 已安装')"
} catch {
    Write-Host "    失败: $_" -ForegroundColor Red
}

Write-Host "`n  pynput:" -ForegroundColor Cyan
try {
    python -c "import pynput; print('    OK - pynput 已安装')"
} catch {
    Write-Host "    失败: $_" -ForegroundColor Red
}

# 完成
Write-Host "`n" + ("=" * 60) -ForegroundColor Cyan
Write-Host "安装完成！" -ForegroundColor Green
Write-Host ("=" * 60) -ForegroundColor Cyan

Write-Host "`n使用说明:" -ForegroundColor Yellow
Write-Host "  1. 激活虚拟环境:" -ForegroundColor White
Write-Host "     .\venv312\Scripts\Activate.ps1" -ForegroundColor Cyan
Write-Host "  2. 启动输入法:" -ForegroundColor White
Write-Host "     python run_input_method.py" -ForegroundColor Cyan
Write-Host "  3. 或使用改进版:" -ForegroundColor White
Write-Host "     python run_input_method_v2.py" -ForegroundColor Cyan

Write-Host "`n现在可以使用完整的输入法功能了！" -ForegroundColor Green
