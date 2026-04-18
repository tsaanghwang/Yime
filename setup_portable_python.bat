@echo off
chcp 65001 >nul
cd /d "%~dp0"

echo ============================================================
echo Portable Python 3.12 Setup (No Admin Required)
echo ============================================================
echo.

REM Check if python312 exists
if exist python312\python.exe (
    echo [OK] Python 3.12 portable found
    python312\python.exe --version
) else (
    echo [MISSING] Python 3.12 portable not found
    echo.
    echo Please follow these steps:
    echo.
    echo   1. Download Python 3.12 embedded:
    echo      https://www.python.org/ftp/python/3.12.8/python-3.12.8-embed-amd64.zip
    echo.
    echo   2. Extract to: python312\
    echo      The directory should contain python.exe
    echo.
    echo   3. Edit python312\python312._pth
    echo      Uncomment the line: import site
    echo.
    echo   4. Download get-pip.py:
    echo      https://bootstrap.pypa.io/get-pip.py
    echo      Save to: python312\get-pip.py
    echo.
    echo   5. Install pip:
    echo      python312\python.exe python312\get-pip.py
    echo.
    echo After completing these steps, run this script again.
    echo.
    pause
    exit /b 1
)

REM Check pip
echo.
echo Checking pip...
python312\python.exe -m pip --version >nul 2>&1
if errorlevel 1 (
    echo [MISSING] pip not installed
    echo.
    echo Please install pip:
    echo   1. Download get-pip.py to python312\
    echo   2. Run: python312\python.exe python312\get-pip.py
    echo.
    pause
    exit /b 1
) else (
    echo [OK] pip installed
)

REM Create virtual environment
echo.
echo [1/3] Creating virtual environment...
if exist venv312 (
    echo   Virtual environment already exists
) else (
    python312\python.exe -m venv venv312
    if errorlevel 1 (
        echo   Failed to create virtual environment
        pause
        exit /b 1
    )
    echo   Virtual environment created
)

REM Activate
echo.
echo [2/3] Activating virtual environment...
call venv312\Scripts\activate.bat
echo   Activated

REM Install dependencies
echo.
echo [3/3] Installing dependencies...
echo   Upgrading pip...
python -m pip install --upgrade pip >nul 2>&1

echo   Installing pywin32...
pip install pywin32

echo   Installing pynput...
pip install pynput

echo   Installing other dependencies...
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
python -c "import win32api; print('  [OK] pywin32 installed')" 2>nul
if errorlevel 1 (
    echo   [FAIL] pywin32 not working
)
echo.
echo pynput:
python -c "import pynput; print('  [OK] pynput installed')" 2>nul
if errorlevel 1 (
    echo   [FAIL] pynput not working
)

echo.
echo ============================================================
echo Setup Complete!
echo ============================================================
echo.
echo Usage:
echo   1. Activate: venv312\Scripts\activate
echo   2. Start: python -m yime.input_method.app
echo   3. Or: python run_input_method.py
echo.
echo Now you have full input method features!
echo.
pause
