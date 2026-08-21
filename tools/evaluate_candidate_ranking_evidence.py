#!/usr/bin/env python3
"""Generate the canonical source-separated ranking evidence report."""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import asdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from yime.input_model.ranking_evidence import (  # noqa: E402
    DEFAULT_POLICY_PATH,
    audit_runtime_ranking_evidence,
)


def main() -> int:
    parser = argparse.ArgumentParser()
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
        "--capacity-database",
        type=Path,
        default=(
            ROOT
            / ".generated"
            / "static_lexicon_capacity"
            / "static_capacity.sqlite3"
        ),
    )
    parser.add_argument(
        "--selection",
        type=Path,
        default=(
            ROOT
            / ".generated"
            / "two_level_runtime_trial"
            / "selection.tsv"
        ),
    )
    parser.add_argument("--policy", type=Path, default=DEFAULT_POLICY_PATH)
    parser.add_argument(
        "--output",
        type=Path,
        default=(
            ROOT
            / ".generated"
            / "candidate_ranking_evidence"
            / "report.json"
        ),
    )
    args = parser.parse_args()
    result = audit_runtime_ranking_evidence(
        source_database=args.source_database,
        selection_path=args.selection,
        capacity_database=args.capacity_database,
        policy_path=args.policy,
    )
    payload = {
        "schema_version": 1,
        "tool": "evaluate_candidate_ranking_evidence",
        "inputs": {
            "source_database": str(args.source_database.resolve()),
            "capacity_database": str(args.capacity_database.resolve()),
            "selection": str(args.selection.resolve()),
            "policy": str(args.policy.resolve()),
        },
        "result": asdict(result),
        "semantics": {
            "direct_bcc": "BCC integer count is the primary verified evidence.",
            "provisional_rime_lmdg": (
                "RIME-LMDG percentile is used only when direct BCC is absent."
            ),
            "provisional_structural_floor": (
                "Static utility breaks ties only when both corpora are absent; "
                "it is not frequency evidence."
            ),
            "awaiting_corpus": (
                "No quantified source; keep a marked, replaceable floor."
            ),
            "raw_values_are_added": False,
            "writes_bcc_frequency": False,
        },
        "decision": (
            "complete"
            if result.completion_passed
            else "incomplete_gate_failed"
        ),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"report: {args.output.resolve()}")
    print(f"full_inventory_counts: {result.full_inventory_counts}")
    print(f"selected_counts: {result.selected_counts}")
    print(f"decision: {payload['decision']}")
    return 0 if result.completion_passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
