#!/usr/bin/env python3
"""Verify that the source bundle preserves Wanxiang phrase syllable order."""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from yime.utils.dictionary_pinyin_compliance import load_policy, review_syllable

DEFAULT_DATABASE = ROOT / ".generated" / "lexicon_source_bundle" / "source_lexicon.sqlite3"
DEFAULT_OUTPUT = ROOT / ".generated" / "wanxiang_pinyin_order_audit" / "summary.json"


def _connect_read_only(database: Path) -> sqlite3.Connection:
    uri = f"file:{database.resolve().as_posix()}?mode=ro"
    return sqlite3.connect(uri, uri=True)


def audit_wanxiang_order(database: Path, *, sample_limit: int = 20) -> dict[str, object]:
    if not database.is_file():
        raise FileNotFoundError(f"source lexicon database not found: {database}")

    policy = load_policy()
    numeric_cache: dict[str, str] = {}
    accepted_rows = 0
    internal_untoned_rows = 0
    syllable_count_mismatches = 0
    numeric_order_mismatches = 0
    permutation_only_mismatches = 0
    mismatch_samples: list[dict[str, object]] = []

    with _connect_read_only(database) as connection:
        rows = connection.execute(
            """
            SELECT text, source_marked, numeric, source_file, source_category
            FROM accepted_readings
            WHERE source = 'wanxiang'
            ORDER BY text, source_file, source_marked
            """
        )
        for text, source_marked, actual_numeric, source_file, source_category in rows:
            accepted_rows += 1
            source_syllables = str(source_marked).split()
            if len(source_syllables) != len(str(text)):
                syllable_count_mismatches += 1

            expected_parts: list[str] = []
            for syllable in source_syllables:
                numeric = numeric_cache.get(syllable)
                if numeric is None:
                    review = review_syllable(syllable, policy)
                    numeric = review.canonical_numeric
                    numeric_cache[syllable] = numeric
                expected_parts.append(numeric)

            if any(
                part.endswith("5")
                and any(not later.endswith("5") for later in expected_parts[index + 1 :])
                for index, part in enumerate(expected_parts)
            ):
                internal_untoned_rows += 1

            expected_numeric = " ".join(expected_parts)
            actual_numeric = str(actual_numeric)
            if actual_numeric == expected_numeric:
                continue

            numeric_order_mismatches += 1
            permutation_only = Counter(actual_numeric.split()) == Counter(expected_parts)
            if permutation_only:
                permutation_only_mismatches += 1
            if len(mismatch_samples) < sample_limit:
                mismatch_samples.append(
                    {
                        "text": text,
                        "source_marked": source_marked,
                        "expected_numeric": expected_numeric,
                        "actual_numeric": actual_numeric,
                        "permutation_only": permutation_only,
                        "source_category": source_category,
                        "source_file": source_file,
                    }
                )

        rejection_reasons = {
            str(reason): int(count)
            for reason, count in connection.execute(
                """
                SELECT reason, COUNT(*)
                FROM rejections
                WHERE source = 'wanxiang'
                GROUP BY reason
                ORDER BY COUNT(*) DESC, reason
                """
            )
        }

    return {
        "schema_version": "wanxiang-pinyin-order-audit-v1",
        "database": str(database.resolve()),
        "accepted_rows": accepted_rows,
        "rows_with_internal_untoned_syllables": internal_untoned_rows,
        "accepted_syllable_count_mismatches": syllable_count_mismatches,
        "numeric_order_mismatches": numeric_order_mismatches,
        "permutation_only_mismatches": permutation_only_mismatches,
        "wanxiang_rejection_reasons": rejection_reasons,
        "mismatch_samples": mismatch_samples,
        "passed": syllable_count_mismatches == 0 and numeric_order_mismatches == 0,
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Audit Wanxiang source-to-production syllable order without modifying source data.",
    )
    parser.add_argument("--database", type=Path, default=DEFAULT_DATABASE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--sample-limit", type=int, default=20)
    args = parser.parse_args()

    report = audit_wanxiang_order(args.database, sample_limit=max(args.sample_limit, 0))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
