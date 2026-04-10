from __future__ import annotations

import argparse
import json
import sqlite3
from collections import defaultdict
from pathlib import Path


DB_PATH = Path(__file__).resolve().parent / "pinyin_hanzi.db"
DEFAULT_OUTPUT_PATH = Path(__file__).resolve().parent / "reports" / "runtime_candidates_by_code.json"
DEFAULT_TRUE_OUTPUT_PATH = Path(__file__).resolve().parent / "reports" / "runtime_candidates_by_code_true.json"
DEFAULT_PLACEHOLDER_OUTPUT_PATH = Path(__file__).resolve().parent / "reports" / "runtime_candidates_placeholder_phrases.json"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="从 runtime_candidates 视图导出输入系统可调用的 JSON")
    parser.add_argument("--db", default=str(DB_PATH), help="SQLite 数据库路径")
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT_PATH), help="JSON 输出路径")
    parser.add_argument("--true-output", default=str(DEFAULT_TRUE_OUTPUT_PATH), help="仅包含真实音元编码键的 JSON 输出路径")
    parser.add_argument("--placeholder-output", default=str(DEFAULT_PLACEHOLDER_OUTPUT_PATH), help="占位词语键的 JSON 输出路径")
    parser.add_argument("--limit-per-code", type=int, default=0, help="每个编码最多导出多少个候选；0 表示不限制")
    return parser.parse_args()


def build_candidate_record(row: sqlite3.Row) -> dict[str, object]:
    return {
        "text": row["text"],
        "entry_type": row["entry_type"],
        "entry_id": row["entry_id"],
        "pinyin_tone": row["pinyin_tone"],
        "sort_weight": row["sort_weight"],
        "is_common": row["is_common"],
        "text_length": row["text_length"],
        "updated_at": row["updated_at"],
    }


def group_rows(rows: list[sqlite3.Row], limit_per_code: int) -> dict[str, list[dict[str, object]]]:
    grouped: dict[str, list[dict[str, object]]] = defaultdict(list)
    for row in rows:
        code = row["yime_code"]
        candidates = grouped[code]
        if limit_per_code and len(candidates) >= limit_per_code:
            continue
        candidates.append(build_candidate_record(row))
    return dict(grouped)


def build_payload(
    *,
    db_path: Path,
    grouped: dict[str, list[dict[str, object]]],
    description: str,
    limit_per_code: int,
    extra_metadata: dict[str, object] | None = None,
) -> dict[str, object]:
    metadata: dict[str, object] = {
        "db_path": str(db_path),
        "code_count": len(grouped),
        "candidate_row_count": sum(len(items) for items in grouped.values()),
        "description": description,
        "limit_per_code": limit_per_code,
    }
    if extra_metadata:
        metadata.update(extra_metadata)
    return {
        "metadata": metadata,
        "by_code": grouped,
    }


def main() -> None:
    args = parse_args()
    db_path = Path(args.db)
    output_path = Path(args.output)
    true_output_path = Path(args.true_output)
    placeholder_output_path = Path(args.placeholder_output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    true_output_path.parent.mkdir(parents=True, exist_ok=True)
    placeholder_output_path.parent.mkdir(parents=True, exist_ok=True)

    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    try:
        rows = conn.execute(
            '''
            SELECT
                entry_type,
                entry_id,
                text,
                pinyin_tone,
                yime_code,
                sort_weight,
                is_common,
                text_length,
                updated_at,
                CASE
                    WHEN entry_type = 'phrase' AND yime_code = pinyin_tone THEN 1
                    ELSE 0
                END AS is_placeholder_code
            FROM runtime_candidates
            WHERE yime_code IS NOT NULL
              AND TRIM(yime_code) <> ''
            ORDER BY yime_code, entry_type, sort_weight DESC, text
            '''
        ).fetchall()
    finally:
        conn.close()

    real_rows = [row for row in rows if not row["is_placeholder_code"]]
    placeholder_rows = [row for row in rows if row["is_placeholder_code"]]

    grouped_all = group_rows(rows, args.limit_per_code)
    grouped_real = group_rows(real_rows, args.limit_per_code)
    grouped_placeholder = group_rows(placeholder_rows, args.limit_per_code)

    all_payload = build_payload(
        db_path=db_path,
        grouped=grouped_all,
        description="按音元拼音编码分组的候选数据，可直接供输入系统加载。包含真实编码与占位词语键。",
        limit_per_code=args.limit_per_code,
        extra_metadata={
            "real_code_count": len(grouped_real),
            "real_candidate_row_count": sum(len(items) for items in grouped_real.values()),
            "placeholder_code_count": len(grouped_placeholder),
            "placeholder_candidate_row_count": sum(len(items) for items in grouped_placeholder.values()),
        },
    )
    true_payload = build_payload(
        db_path=db_path,
        grouped=grouped_real,
        description="仅包含真实音元编码键的候选数据，适合直接供候选框或输入系统加载。",
        limit_per_code=args.limit_per_code,
    )
    placeholder_payload = build_payload(
        db_path=db_path,
        grouped=grouped_placeholder,
        description="仍使用数字标调拼音占位键的词语候选数据，供后续回填编码使用。",
        limit_per_code=args.limit_per_code,
    )

    output_path.write_text(json.dumps(all_payload, ensure_ascii=False, indent=2), encoding="utf-8")
    true_output_path.write_text(json.dumps(true_payload, ensure_ascii=False, indent=2), encoding="utf-8")
    placeholder_output_path.write_text(json.dumps(placeholder_payload, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"exported all codes: {len(grouped_all)}")
    print(f"exported all candidate rows: {sum(len(items) for items in grouped_all.values())}")
    print(f"exported true codes: {len(grouped_real)}")
    print(f"exported true candidate rows: {sum(len(items) for items in grouped_real.values())}")
    print(f"exported placeholder codes: {len(grouped_placeholder)}")
    print(f"exported placeholder candidate rows: {sum(len(items) for items in grouped_placeholder.values())}")
    print(f"all output: {output_path}")
    print(f"true-code output: {true_output_path}")
    print(f"placeholder output: {placeholder_output_path}")


if __name__ == "__main__":
    main()
