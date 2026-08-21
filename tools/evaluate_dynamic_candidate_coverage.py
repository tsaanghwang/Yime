#!/usr/bin/env python3
"""Generate the canonical R0-R5 dynamic candidate coverage report."""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import asdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from yime.input_model.dynamic_coverage import (  # noqa: E402
    DEFAULT_POLICY_PATH,
    evaluate_dynamic_candidate_coverage,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "以完整候选池反向验证动态核心，输出 R0-R5 覆盖层、残差和核心提升建议。"
        )
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
            / "dynamic_candidate_coverage"
            / "report.json"
        ),
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    result = evaluate_dynamic_candidate_coverage(
        capacity_database=args.capacity_database,
        input_model_database=args.input_model_database,
        selection_path=args.selection,
        policy_path=args.policy,
    )
    payload = {
        "schema_version": 1,
        "tool": "evaluate_dynamic_candidate_coverage",
        "inputs": {
            "capacity_database": str(args.capacity_database.resolve()),
            "input_model_database": str(
                args.input_model_database.resolve()
            ),
            "selection": str(args.selection.resolve()),
            "policy": str(args.policy.resolve()),
        },
        "result": asdict(result),
        "recommendations": {
            "R0": "修复或隔离确定性数据错误，不参与核心优化。",
            "R1": "寻找最小可复用部件或构式规则；修复前保留必要静态覆盖。",
            "R2": "补齐缺失读音的组件覆盖，不按整个字串批量晋升。",
            "R3": "评估中间部件、搜索宽度或有界缓存，完成排序回放。",
            "R4": "由动态核心服务，可从静态核心迁出。",
            "R5": "作为基础字符、受保护类别或有证据缓存静态保留。",
        },
        "safeguards": {
            "source_mutation": False,
            "writes_assessments": False,
            "frequency_is_not_invalidity": True,
            "candidate_pool_is_evaluation_inventory": True,
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
    print(f"encoded_texts: {result.encoded_texts}")
    print(f"classified_texts: {result.classified_texts}")
    print(f"level_counts: {result.level_counts}")
    print(f"selected_counts: {result.selected_counts}")
    print(f"decision: {payload['decision']}")
    return 0 if result.completion_passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
