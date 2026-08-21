#!/usr/bin/env python3
"""Build the gated Unihan/pypinyin/Wanxiang/PSC/BCC source lexicon bundle."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from yime.lexicon_bundle.builder import (
    BundleInputs,
    CategorizedPath,
    build_bundle,
    default_inputs,
)
from yime.lexicon_bundle.character_tiers import CharacterTierSources
from yime.lexicon_bundle.external_inputs import (
    DEFAULT_LOCK as DEFAULT_EXTERNAL_INPUT_LOCK,
    resolve_external_inputs,
)


BCC_CATEGORIES = (
    "modern_chinese",
    "news",
    "dialogue",
    "literature",
    "classical_chinese",
    "multi_domain",
)
WANXIANG_INPUT_IDS = (
    "wanxiang_zi",
    "wanxiang_jichu",
    "wanxiang_lianxiang",
    "wanxiang_duoyin",
    "wanxiang_diming",
    "wanxiang_fangyan",
    "wanxiang_huaxue",
    "wanxiang_mingren",
    "wanxiang_renming",
    "wanxiang_shici",
    "wanxiang_taifeng",
    "wanxiang_wuzhong",
    "wanxiang_yaopin",
    "wanxiang_yiren",
    "wanxiang_yixue",
)


def parse_args() -> argparse.Namespace:
    defaults = default_inputs()
    parser = argparse.ArgumentParser(
        description="Build a traceable, decoder-ready source lexicon bundle.",
    )
    parser.add_argument("--unihan", type=Path, default=defaults.unihan)
    parser.add_argument("--pypinyin-phrases", type=Path, default=defaults.pypinyin_phrases)
    parser.add_argument("--decoder-inventory", type=Path, default=defaults.decoder_inventory)
    parser.add_argument(
        "--orthoepy-coverage",
        type=Path,
        default=defaults.orthoepy_coverage,
        help="Reviewed orthoepy additions; adds coverage without primary/ranking decisions.",
    )
    parser.add_argument(
        "--psc-candidate-coverage",
        type=Path,
        default=defaults.psc_candidate_coverage,
        help="Reviewed PSC pairs missing from runtime candidates; candidate-only, non-primary coverage.",
    )
    assert defaults.character_tier_sources is not None
    parser.add_argument(
        "--unihan-other-mappings",
        type=Path,
        default=defaults.character_tier_sources.other_mappings,
    )
    parser.add_argument(
        "--unihan-readings",
        type=Path,
        help="Override the locked Unihan_Readings.txt path.",
    )
    parser.add_argument(
        "--unihan-character-db",
        type=Path,
        help="Override the locked character catalog database path.",
    )
    parser.add_argument(
        "--yinjie-codebook",
        type=Path,
        default=defaults.character_tier_sources.yinjie_codebook,
    )
    parser.add_argument(
        "--source-compliance-policy",
        type=Path,
        default=defaults.source_compliance_policy,
    )
    parser.add_argument(
        "--external-input-lock",
        type=Path,
        default=DEFAULT_EXTERNAL_INPUT_LOCK,
    )
    parser.add_argument(
        "--external-root",
        type=Path,
        help="Content-addressed external input root; otherwise use YIME_LEXICON_EXTERNAL_ROOT.",
    )
    parser.add_argument(
        "--no-legacy-external-paths",
        action="store_true",
        help="Reject transitional C:/dev legacy locations and require --external-root or the environment variable.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=ROOT / ".generated" / "lexicon_source_bundle",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    external = resolve_external_inputs(
        args.external_input_lock.resolve(),
        external_root=(args.external_root.resolve() if args.external_root else None),
        allow_legacy_paths=not args.no_legacy_external_paths,
    )
    inputs = BundleInputs(
        unihan=args.unihan.resolve(),
        pypinyin_phrases=args.pypinyin_phrases.resolve(),
        bcc_word_files=tuple(
            CategorizedPath(category, "word", external[f"bcc_word_{category}"])
            for category in BCC_CATEGORIES
        ),
        bcc_char_files=tuple(
            CategorizedPath(category, "char", external[f"bcc_char_{category}"])
            for category in BCC_CATEGORIES
        ),
        wanxiang_files=tuple(external[input_id] for input_id in WANXIANG_INPUT_IDS),
        decoder_inventory=args.decoder_inventory.resolve(),
        source_compliance_policy=args.source_compliance_policy.resolve(),
        orthoepy_coverage=(
            args.orthoepy_coverage.resolve() if args.orthoepy_coverage else None
        ),
        psc_candidate_coverage=(
            args.psc_candidate_coverage.resolve()
            if args.psc_candidate_coverage
            else None
        ),
        character_tier_sources=CharacterTierSources(
            other_mappings=args.unihan_other_mappings.resolve(),
            readings=(
                args.unihan_readings.resolve()
                if args.unihan_readings
                else external["unihan_readings"]
            ),
            character_catalog_db=(
                args.unihan_character_db.resolve()
                if args.unihan_character_db
                else external["character_catalog_db"]
            ),
            yinjie_codebook=args.yinjie_codebook.resolve(),
        ),
    )
    result = build_bundle(inputs, args.output_dir.resolve())
    payload = json.loads(result.manifest.read_text(encoding="utf-8"))
    print(json.dumps(payload["counts"], ensure_ascii=False, indent=2))
    print(f"bundle: {result.output_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
