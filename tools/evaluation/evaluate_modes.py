#!/usr/bin/env python3
"""Measure the three approved Windows dictionaries without a prototype DB."""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Iterator

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.evaluation.context import load_evaluation_context


SHIFT_TOKENS = set('~!@#$%^&*()_+{}|:"<>?ABCDEFGHIJKLMNOPQRSTUVWXYZ')


@dataclass(frozen=True)
class DictionaryEntry:
    text: str
    code: str
    weight: float


def iter_dictionary(path: Path) -> Iterator[DictionaryEntry]:
    in_body = False
    with path.open(encoding="utf-8") as stream:
        for line_number, raw_line in enumerate(stream, start=1):
            line = raw_line.rstrip("\r\n")
            if not in_body:
                if line == "...":
                    in_body = True
                continue
            if not line or line.startswith("#"):
                continue
            fields = line.split("\t")
            if len(fields) < 2 or not fields[0] or not fields[1]:
                raise ValueError(f"invalid Rime dictionary row {path}:{line_number}")
            try:
                weight = float(fields[2]) if len(fields) >= 3 else 1.0
            except ValueError as exc:
                raise ValueError(
                    f"invalid Rime dictionary weight {path}:{line_number}"
                ) from exc
            yield DictionaryEntry(fields[0], fields[1], max(weight, 0.0))
    if not in_body:
        raise ValueError(f"Rime dictionary has no body delimiter: {path}")


def summarize_dictionary(path: Path) -> dict[str, object]:
    buckets: Counter[str] = Counter()
    entry_count = 0
    code_units = 0
    modifier_units = 0
    weight_sum = 0.0
    weighted_code_units = 0.0
    weighted_modifier_units = 0.0
    minimum_length: int | None = None
    maximum_length = 0
    for entry in iter_dictionary(path):
        length = len(entry.code)
        modifier_count = sum(token in SHIFT_TOKENS for token in entry.code)
        adjusted = length + modifier_count
        entry_count += 1
        code_units += length
        modifier_units += adjusted
        weight_sum += entry.weight
        weighted_code_units += entry.weight * length
        weighted_modifier_units += entry.weight * adjusted
        minimum_length = length if minimum_length is None else min(minimum_length, length)
        maximum_length = max(maximum_length, length)
        buckets[entry.code] += 1

    collision_buckets = sum(size > 1 for size in buckets.values())
    entries_in_collision = sum(size for size in buckets.values() if size > 1)
    return {
        "entry_count": entry_count,
        "distinct_codes": len(buckets),
        "minimum_code_length": minimum_length or 0,
        "maximum_code_length": maximum_length,
        "mean_code_length": code_units / entry_count if entry_count else 0.0,
        "mean_modifier_adjusted_presses": (
            modifier_units / entry_count if entry_count else 0.0
        ),
        "weight_sum": weight_sum,
        "weighted_mean_code_length": (
            weighted_code_units / weight_sum if weight_sum else 0.0
        ),
        "weighted_mean_modifier_adjusted_presses": (
            weighted_modifier_units / weight_sum if weight_sum else 0.0
        ),
        "collision_bucket_count": collision_buckets,
        "entries_in_collision_buckets": entries_in_collision,
        "maximum_candidates_per_code": max(buckets.values(), default=0),
        "mean_candidates_per_code": (
            entry_count / len(buckets) if buckets else 0.0
        ),
    }


def evaluate_modes() -> dict[str, object]:
    context = load_evaluation_context()
    mode_roles = {
        "full": "full_mode_dictionary",
        "variable": "variable_mode_dictionary",
        "shorthand": "shorthand_mode_dictionary",
    }
    modes = {
        mode: summarize_dictionary(context.artifacts[role])
        for mode, role in mode_roles.items()
    }
    for mode, summary in modes.items():
        if int(summary["entry_count"]) != context.entry_count:
            raise ValueError(
                f"{mode} dictionary entry count left the approved target: "
                f"{summary['entry_count']} != {context.entry_count}"
            )
    return {
        "schema_version": "yime-target-locked-mode-efficiency-v1",
        "evaluation_identity": context.identity(),
        "metric_scope": {
            "code_length": "Rime key tokens in the packaged dictionary",
            "modifier_adjusted_presses": (
                "code tokens plus one cost for each shifted printable token"
            ),
            "weighting": "dictionary weight, reported separately from unweighted means",
            "candidate_window": "static collision buckets; real librime replay remains a separate gate",
        },
        "modes": modes,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=Path,
        default=REPO_ROOT / ".generated" / "evaluation" / "mode_efficiency.json",
    )
    args = parser.parse_args()
    report = evaluate_modes()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
