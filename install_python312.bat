@echo off
chcp 65001 >nul
REM Python 3.12 Installation Script

echo ============================================================
echo Python 3.12 Installation Script
echo ============================================================
echo.

REM Check pyenv
echo [1/3] Checking pyenv-win...
where pyenv >nul 2>&1
if %errorlevel% equ 0 (
    echo   pyenv-win is installed
    pyenv --version
) else (
    echo   pyenv-win is NOT installed
    echo.
    echo   Please install pyenv-win first:
    echo   Method 1: Run in PowerShell (Admin):
    echo     Invoke-WebRequest -UseBasicParsing https://raw.githubusercontent.com/pyenv-win/pyenv-win/master/pyenv-win/install.ps1 ^| iex
    echo.
    echo   Method 2: Use pip:
    echo     pip install pyenv-win --target %%USERPROFILE%%\.pyenv
    echo.
    echo   Or download Python 3.12 directly:
    echo     https://www.python.org/downloads/release/python-3128/
    echo.
    pause
    exit /b 1
)

REM Install Python 3.12
echo.
echo [2/3] Installing Python 3.12.8...
pyenv install 3.12.8 -f
if %errorlevel% neq 0 (
    echo   Installation failed
    pause
    exit /b 1
)
echo   Python 3.12.8 installed successfully

REM Set project version
echo.
echo [3/3] Setting project Python version...
pyenv local 3.12.8
echo   Project Python version set to 3.12.8

REM Create virtual environment
echo.
echo Creating virtual environment...
if exist venv312 (
    echo   Virtual environment already exists
) else (
    python -m venv venv312
    echo   Virtual environment created
)

REM Activate and install dependencies
echo.
echo Activating virtual environment and installing dependencies...
call venv312\Scripts\activate.bat

echo Upgrading pip...
python -m pip install --upgrade pip

echo Installing pywin32...
pip install pywin32

echo Installing pynput...
pip install pynput

echo Installing other dependencies...
pip install pytest coverage tqdm

REM Verify
echo.
echo ============================================================
echo Verifying Installation
echo ============================================================
echo.
echo Python version:
python --version
echo.
echo pywin32:
python -c "import win32api; print('  OK - pywin32 installed')" 2>nul
if %errorlevel% neq 0 (
    echo   Failed
)
echo.
echo pynput:
python -c "import pynput; print('  OK - pynput installed')" 2>nul
if %errorlevel% neq 0 (
    echo   Failed
)

echo.
echo ============================================================
echo Installation Complete!
echo ============================================================
echo.
echo Usage:
echo   1. Activate virtual environment:
echo      venv312\Scripts\activate.bat
echo.
echo   2. Start input method:
echo      python run_input_method.py
echo.
echo   3. Or use improved version:
echo      python run_input_method_v2.py
echo.
echo Now you can use full input method features!
echo.
pause
