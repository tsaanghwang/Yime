#!/usr/bin/env python3
"""Build a compact-static-lexicon capacity proposal from the source bundle."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from yime.input_model.static_capacity import (
    StaticCapacityConfig,
    build_static_capacity_model,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Find mandatory static readings and a proxy capacity frontier; "
            "never modifies the source or runtime lexicon."
        )
    )
    parser.add_argument(
        "--source-database",
        type=Path,
        default=(
            ROOT
            / ".generated"
            / "lexicon_source_bundle"
            / "source_lexicon.sqlite3"
        ),
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=ROOT / ".generated" / "static_lexicon_capacity",
    )
    parser.add_argument("--maximum-parts", type=int, default=6)
    parser.add_argument("--maximum-alternatives", type=int, default=4)
    parser.add_argument(
        "--target-direct-frequency-coverage",
        type=float,
        default=0.98,
    )
    parser.add_argument("--target-capacity", type=int)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    result = build_static_capacity_model(
        source_database=args.source_database,
        output_dir=args.output_dir,
        config=StaticCapacityConfig(
            maximum_parts=args.maximum_parts,
            maximum_alternatives=args.maximum_alternatives,
            target_direct_frequency_coverage=(
                args.target_direct_frequency_coverage
            ),
            target_capacity=args.target_capacity,
        ),
    )
    print(f"encoded_texts: {result.encoded_texts}")
    print(f"mandatory_static_texts: {result.mandatory_static_texts}")
    print(
        "dynamically_recoverable_texts: "
        f"{result.dynamically_recoverable_texts}"
    )
    print(
        "recommended_static_capacity: "
        f"{result.recommended_static_capacity}"
    )
    print(f"output: {result.output_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
