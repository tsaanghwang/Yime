#!/usr/bin/env python3
"""Build recursive reachability evidence for unencoded candidate strings."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from yime.input_model import (
    RecursiveCompositionConfig,
    build_recursive_composition_model,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Compose unencoded strings from shorter source-gated readings; "
            "writes evidence only and never creates a whole-string reading."
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
        "--input-model-database",
        type=Path,
        default=(
            ROOT
            / ".generated"
            / "input_candidate_model"
            / "input_model.sqlite3"
        ),
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=ROOT / ".generated" / "recursive_composition",
    )
    parser.add_argument("--minimum-target-length", type=int, default=2)
    parser.add_argument("--maximum-alternatives", type=int, default=4)
    parser.add_argument("--maximum-parts-per-step", type=int, default=6)
    parser.add_argument("--maximum-component-readings", type=int, default=4)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    result = build_recursive_composition_model(
        source_database=args.source_database,
        input_model_database=args.input_model_database,
        output_dir=args.output_dir,
        config=RecursiveCompositionConfig(
            minimum_target_length=args.minimum_target_length,
            maximum_alternatives=args.maximum_alternatives,
            maximum_parts_per_step=args.maximum_parts_per_step,
            maximum_component_readings=args.maximum_component_readings,
        ),
    )
    print(f"targets: {result.target_count}")
    print(f"reachable: {result.reachable_count}")
    print(f"unreachable: {result.unreachable_count}")
    print(
        "structurally_ambiguous: "
        f"{result.structurally_ambiguous_count}"
    )
    print(f"reading_ambiguous: {result.reading_ambiguous_count}")
    print(
        "uses_multichar_component: "
        f"{result.uses_multichar_component_count}"
    )
    print(f"residual_blocks_only: {result.residual_blocks_only_count}")
    print(
        "single_exception_targets: "
        f"{result.single_exception_target_count}"
    )
    print(f"output: {result.output_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
