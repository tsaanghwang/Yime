@echo off
chcp 65001 >nul
cd /d "c:\Users\Freeman Golden\OneDrive\Yime"

echo ============================================================
echo Python 3.12 Environment Activation
echo ============================================================
echo.

if exist venv312\Scripts\activate.bat (
    echo Activating Python 3.12 virtual environment...
    call venv312\Scripts\activate.bat
    echo.
    echo Python version:
    python --version
    echo.
    echo Checking pywin32...
    python -c "import win32api; print('  OK - pywin32 installed')" 2>nul
    if errorlevel 1 (
        echo   Not installed. Run: pip install pywin32
    )
    echo.
    echo Checking pynput...
    python -c "import pynput; print('  OK - pynput installed')" 2>nul
    if errorlevel 1 (
        echo   Not installed. Run: pip install pynput
    )
    echo.
    echo ============================================================
    echo Environment Ready!
    echo ============================================================
    echo.
    echo Usage:
    echo   python -m yime.input_method.app
    echo   python run_input_method.py
    echo.
) else (
    echo Virtual environment not found!
    echo.
    echo Please create it first:
    echo.
    echo   1. Install Python 3.12 from:
    echo      https://www.python.org/downloads/release/python-3128/
    echo.
    echo   2. Create virtual environment:
    echo      py -3.12 -m venv venv312
    echo.
    echo   3. Activate and install dependencies:
    echo      venv312\Scripts\activate
    echo      pip install pywin32 pynput pytest coverage tqdm
    echo.
    pause
)
