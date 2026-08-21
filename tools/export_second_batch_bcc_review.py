#!/usr/bin/env python3
"""Export the explainable review queue for the second BCC frequency batch."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from yime.input_model.second_batch_review import export_second_batch_review  # noqa: E402


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Export a read-only BCC 1000-9999 review queue."
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
        "--output-directory",
        type=Path,
        default=ROOT / ".generated" / "second_batch_bcc_review",
    )
    parser.add_argument("--minimum-frequency", type=int, default=1000)
    parser.add_argument("--maximum-frequency", type=int, default=9999)
    parser.add_argument("--summary-limit", type=int, default=20)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    result = export_second_batch_review(
        source_database=args.source_database,
        input_model_database=args.input_model_database,
        output_directory=args.output_directory,
        minimum_frequency=args.minimum_frequency,
        maximum_frequency=args.maximum_frequency,
        summary_limit=args.summary_limit,
    )
    print(
        json.dumps(
            {
                "total": result.total_count,
                "conflict_or_scoped_review": result.conflict_count,
                "by_lane": result.lane_counts,
                "manifest": str(result.manifest_path),
            },
            ensure_ascii=False,
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())