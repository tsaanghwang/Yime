@echo off
chcp 65001 >nul
cd /d "%~dp0\.."

echo ============================================================
echo Python 3.12 Environment Activation
echo ============================================================
echo.

if exist venv312\Scripts\activate.bat (
    set "YIME_ENV_NAME=venv312"
    echo Activating Python 3.12 virtual environment...
    call venv312\Scripts\activate.bat
    goto :env_ready
) else if exist .venv\Scripts\activate.bat (
    set "YIME_ENV_NAME=.venv"
    echo Activating workspace virtual environment...
    call .venv\Scripts\activate.bat
    goto :env_ready
) else (
    goto :env_missing
)

:env_ready
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
    echo Environment Ready! (%YIME_ENV_NAME%)
    echo ============================================================
    echo.
    echo Usage:
    echo   python -m yime.input_method.app
    echo   python run_input_method.py
    echo.

    goto :eof

:env_missing
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