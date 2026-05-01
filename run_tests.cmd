@echo off
setlocal

cd /d "%~dp0"

if exist "venv312\Scripts\python.exe" (
  set "PYTHON=venv312\Scripts\python.exe"
) else if exist ".venv\Scripts\python.exe" (
  set "PYTHON=.venv\Scripts\python.exe"
) else (
  set "PYTHON=python"
)

echo Using Python: %PYTHON%
echo Rebuilding source pinyin assets...

"%PYTHON%" internal_data\pinyin_source_db\rebuild_pinyin_assets.py
if errorlevel 1 (
  echo.
  echo Rebuild failed with exit code %ERRORLEVEL%.
  exit /b %ERRORLEVEL%
)

echo Running focused validation suite...

"%PYTHON%" tools\validate_yinyuan_source_consistency.py
if errorlevel 1 (
  echo.
  echo Yinyuan source consistency validation failed with exit code %ERRORLEVEL%.
  exit /b %ERRORLEVEL%
)

"%PYTHON%" -m unittest ^
  tests\yinjie\verify_yinjie_encoder.py ^
  tests\yinjie\test_yinjie_decoder.py ^
  tests\yinjie\test_pinyin_bidirectional_validation.py ^
  tests\yinjie\test_yinjie_roundtrip.py ^
  tests\yinjie\verify_yinjie_encoder_stages.py ^
  tests\yinjie\verify_yinjie_entry_manifests.py ^
  syllable/analysis/slice/verify_encode_ganyin.py ^
  utils/test_pinyin_normalizer.py

set "EXIT_CODE=%ERRORLEVEL%"

if not "%EXIT_CODE%"=="0" (
  echo.
  echo Validation failed with exit code %EXIT_CODE%.
)

exit /b %EXIT_CODE%
