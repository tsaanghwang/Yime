@echo off
setlocal

cd /d "%~dp0\.."

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
  tests\yinjie\test_yinjie_encoder.py ^
  tests\yinjie\test_yinjie_model.py ^
  tests\test_yinjie_legacy_helpers.py ^
  tests\yinjie\test_yinjie_structure_pipeline.py ^
  tests\yinjie\test_yinjie_decoder.py ^
  tests\yinjie\test_pinyin_bidirectional_validation.py ^
  tests\yinjie\test_yinjie_roundtrip.py ^
  tests\yinjie\test_yinjie_encoder_stages.py ^
  tests\yinjie\test_yinjie_entry_manifests.py ^
  tests\syllable_analysis\test_encode_ganyin.py ^
  tests\pinyin_source_db\test_marked_syllable_to_numeric.py ^
  tests\pinyin_source_db\test_export_pinyin_normalized_inventory.py ^
  tests\yime\test_char_frequency_policy.py ^
  tests\yime\test_yinjie_slot_decomposition.py ^
  tests\yime\test_blcu_word_frequency_import.py ^
  tests\yime\test_unihan_readings_frequency.py ^
  tests\test_pinyin_normalizer.py
if errorlevel 1 (
  set "EXIT_CODE=%ERRORLEVEL%"
  goto :finish
)

"%PYTHON%" -m pytest ^
  tests\test_asset_paths.py ^
  tests\input_method\ ^
  -q --tb=short
set "EXIT_CODE=%ERRORLEVEL%"

:finish

if not "%EXIT_CODE%"=="0" (
  echo.
  echo Validation failed with exit code %EXIT_CODE%.
)

exit /b %EXIT_CODE%
