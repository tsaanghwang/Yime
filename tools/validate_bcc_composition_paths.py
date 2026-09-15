#!/usr/bin/env python3
"""Export read-only BCC component Pinyin and three-mode code paths."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from yime.input_model.bcc_composition_validation import (
    BccCompositionValidationConfig,
    validate_bcc_composition_paths,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Export source-gated component input paths for unannotated BCC strings; "
            "never creates a whole-string reading or candidate."
        )
    )
    parser.add_argument(
        "--source-database",
        type=Path,
        default=ROOT / ".generated" / "lexicon_source_bundle" / "source_lexicon.sqlite3",
    )
    parser.add_argument(
        "--input-model-database",
        type=Path,
        default=ROOT / ".generated" / "input_candidate_model" / "input_model.sqlite3",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=ROOT / ".generated" / "bcc_recursive_validation",
    )
    parser.add_argument("--sample-limit", type=int, default=10)
    parser.add_argument("--scan-limit", type=int, default=1_000)
    parser.add_argument(
        "--seed",
        help="deterministic random sample seed; omitted keeps highest-frequency ordering",
    )
    parser.add_argument("--minimum-target-length", type=int, default=3)
    parser.add_argument("--maximum-target-length", type=int, default=12)
    parser.add_argument("--maximum-structural-alternatives", type=int, default=128)
    parser.add_argument("--maximum-paths-per-target", type=int, default=4_096)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    result = validate_bcc_composition_paths(
        source_database=args.source_database,
        input_model_database=args.input_model_database,
        output_dir=args.output_dir,
        config=BccCompositionValidationConfig(
            sample_limit=args.sample_limit,
            scan_limit=args.scan_limit,
            sample_seed=args.seed,
            minimum_target_length=args.minimum_target_length,
            maximum_target_length=args.maximum_target_length,
            maximum_structural_alternatives=args.maximum_structural_alternatives,
            maximum_paths_per_target=args.maximum_paths_per_target,
        ),
    )
    print(f"scanned: {result.scanned_count}")
    print(f"samples: {result.sample_count}")
    print(f"paths: {result.path_count}")
    print(f"skipped: {result.skipped_count}")
    print(f"output: {result.output_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
