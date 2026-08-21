#!/usr/bin/env python3
"""Initialize the candidate decision overlay and seed its review queue."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from yime.input_model import build_input_model


DEFAULT_SOURCE = ROOT / ".generated" / "lexicon_source_bundle" / "source_lexicon.sqlite3"
DEFAULT_OUTPUT = ROOT / ".generated" / "input_candidate_model" / "input_model.sqlite3"
DEFAULT_POLICY = ROOT / "internal_data" / "input_candidate_model_policy.json"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build the reviewable input-candidate decision overlay.",
    )
    parser.add_argument("--source-database", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--output-database", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--policy", type=Path, default=DEFAULT_POLICY)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    result = build_input_model(
        source_database=args.source_database,
        output_database=args.output_database,
        policy_path=args.policy,
    )
    print(f"input_model_database: {result.database}")
    print(f"candidate_universe: {result.universe_count}")
    print(f"review_queue: {result.review_queue_count}")
    print(f"decision_overlays: {result.decision_overlays}")
    print(f"overlay_status_counts: {result.overlay_status_counts}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
