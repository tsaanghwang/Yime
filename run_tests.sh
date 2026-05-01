#!/usr/bin/env bash
set -e

cd "$(dirname "$0")"

if [[ -x "venv312/Scripts/python.exe" ]]; then
	PYTHON="venv312/Scripts/python.exe"
elif [[ -x ".venv/Scripts/python.exe" ]]; then
	PYTHON=".venv/Scripts/python.exe"
else
	PYTHON="python"
fi

echo "Using Python: $PYTHON"
echo "Rebuilding source pinyin assets..."

"$PYTHON" internal_data/pinyin_source_db/rebuild_pinyin_assets.py

echo "Running focused validation suite..."

"$PYTHON" tools/validate_yinyuan_source_consistency.py

"$PYTHON" -m unittest \
	tests/yinjie/verify_yinjie_encoder.py \
	tests/yinjie/test_yinjie_decoder.py \
	tests/yinjie/test_pinyin_bidirectional_validation.py \
	tests/yinjie/test_yinjie_roundtrip.py \
	tests/yinjie/verify_yinjie_encoder_stages.py \
	tests/yinjie/verify_yinjie_entry_manifests.py \
	syllable/analysis/slice/verify_encode_ganyin.py \
	utils/test_pinyin_normalizer.py
