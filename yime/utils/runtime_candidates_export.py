from __future__ import annotations

import argparse
import json
import sqlite3
from collections import defaultdict
from pathlib import Path
from typing import SupportsFloat, SupportsIndex

from yime.canonical_yime_mapping import convert_legacy_code_to_primary, load_primary_code_map
from yime.asset_paths import generated_runtime_candidates_json_path
from yime.utils.code_modes import YimeCodeMode, lookup_code_column, normalize_code_mode


DB_PATH = Path(__file__).resolve().parents[1] / "pinyin_hanzi.db"
DEFAULT_OUTPUT_PATH = Path(__file__).resolve().parents[1] / "reports" / "runtime_candidates_by_code.json"
DEFAULT_TRUE_OUTPUT_PATH = generated_runtime_candidates_json_path(Path(__file__).resolve().parents[2])
DEFAULT_PLACEHOLDER_OUTPUT_PATH = Path(__file__).resolve().parents[1] / "reports" / "runtime_candidates_placeholder_phrases.json"


RUNTIME_SQL_PRIORITY_ORDER = """
CASE
    WHEN entry_type = 'phrase' AND text_length BETWEEN 2 AND 4 THEN 0
    WHEN entry_type = 'char' THEN 1
    ELSE 2
END,
sort_weight DESC,
text,
pinyin_tone
"""


SORT_WEIGHT_EXPORT_DECIMALS = 4


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="从 runtime_candidates 视图导出输入系统可调用的 JSON")
    parser.add_argument("--db", default=str(DB_PATH), help="SQLite 数据库路径")
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT_PATH), help="JSON 输出路径")
    parser.add_argument("--true-output", default=str(DEFAULT_TRUE_OUTPUT_PATH), help="仅包含真实音元编码键的 JSON 输出路径")
    parser.add_argument("--placeholder-output", default=str(DEFAULT_PLACEHOLDER_OUTPUT_PATH), help="占位词语键的 JSON 输出路径")
    parser.add_argument("--limit-per-code", type=int, default=0, help="每个编码最多导出多少个候选；0 表示不限制")
    return parser.parse_args()


def normalize_sort_weight_for_export(value: SupportsFloat | SupportsIndex | str | bytes | bytearray | None) -> float:
    return round(float(value or 0.0), SORT_WEIGHT_EXPORT_DECIMALS)


def build_candidate_record(row: sqlite3.Row) -> dict[str, object]:
    primary_yime_code = row["primary_yime_code"] if "primary_yime_code" in row.keys() else None
    if not str(primary_yime_code or "").strip():
        pinyin_tone = str(row["pinyin_tone"] or "").strip()
        legacy_code = str(row["yime_code"] or "").strip()
        primary_map = load_primary_code_map(Path(__file__).resolve().parents[2])
        primary_yime_code = primary_map.get(pinyin_tone, "")
        if not primary_yime_code and legacy_code and legacy_code != pinyin_tone:
            primary_yime_code = convert_legacy_code_to_primary(legacy_code)
    full_yime_code = row["full_yime_code"] if "full_yime_code" in row.keys() else row["yime_code"]
    variable_yinyuan_code = (
        row["variable_yinyuan_code"] if "variable_yinyuan_code" in row.keys() else primary_yime_code
    )
    input_shorthand_code = (
        row["input_shorthand_code"] if "input_shorthand_code" in row.keys() else variable_yinyuan_code
    )
    return {
        "text": row["text"],
        "entry_type": row["entry_type"],
        "entry_id": row["entry_id"],
        "pinyin_tone": row["pinyin_tone"],
        "yime_code": row["yime_code"],
        "full_yime_code": full_yime_code,
        "primary_yime_code": primary_yime_code,
        "variable_yinyuan_code": variable_yinyuan_code,
        "input_shorthand_code": input_shorthand_code,
        "sort_weight": normalize_sort_weight_for_export(row["sort_weight"]),
        "is_common": row["is_common"],
        "text_length": row["text_length"],
        "updated_at": row["updated_at"],
    }


def _row_lookup_code(row: sqlite3.Row, mode: YimeCodeMode | str = YimeCodeMode.VARIABLE) -> str:
    normalized_mode = normalize_code_mode(mode)
    column = lookup_code_column(normalized_mode)
    if column in row.keys():
        return str(row[column] or "")
    if normalized_mode == YimeCodeMode.FULL:
        return str(row["yime_code"] or "")
    primary_code = row["primary_yime_code"] if "primary_yime_code" in row.keys() else None
    return str(primary_code or row["yime_code"] or "")


def group_rows(
    rows: list[sqlite3.Row],
    limit_per_code: int,
    mode: YimeCodeMode | str = YimeCodeMode.VARIABLE,
) -> dict[str, list[dict[str, object]]]:
    grouped: dict[str, list[dict[str, object]]] = defaultdict(list)
    for row in rows:
        code = _row_lookup_code(row, mode)
        candidates = grouped[code]
        if limit_per_code and len(candidates) >= limit_per_code:
            continue
        candidates.append(build_candidate_record(row))
    return dict(grouped)


def group_rows_by_mode(
    rows: list[sqlite3.Row],
    limit_per_code: int,
) -> dict[str, dict[str, list[dict[str, object]]]]:
    return {
        mode.value: group_rows(rows, limit_per_code, mode)
        for mode in YimeCodeMode
    }


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
        materialized_columns = {
            str(row[1] or "")
            for row in conn.execute("PRAGMA table_info(runtime_candidates_materialized)").fetchall()
        }
        full_code_expr = (
            "COALESCE(full_yime_code, yime_code)"
            if "full_yime_code" in materialized_columns
            else "yime_code"
        )
        primary_code_expr = (
            "COALESCE(primary_yime_code, '')"
            if "primary_yime_code" in materialized_columns
            else "yime_code"
        )
        variable_code_expr = (
            "COALESCE(variable_yinyuan_code, primary_yime_code, '')"
            if "variable_yinyuan_code" in materialized_columns
            else primary_code_expr
        )
        shorthand_code_expr = (
            "COALESCE(input_shorthand_code, variable_yinyuan_code, primary_yime_code, '')"
            if "input_shorthand_code" in materialized_columns
            else variable_code_expr
        )
        rows = conn.execute(
            f'''
            SELECT
                entry_type,
                entry_id,
                text,
                pinyin_tone,
                yime_code,
                {full_code_expr} AS full_yime_code,
                CASE
                    WHEN entry_type = 'phrase' AND yime_code = pinyin_tone THEN ''
                    ELSE {primary_code_expr}
                END AS primary_yime_code,
                CASE
                    WHEN entry_type = 'phrase' AND yime_code = pinyin_tone THEN ''
                    ELSE {variable_code_expr}
                END AS variable_yinyuan_code,
                CASE
                    WHEN entry_type = 'phrase' AND yime_code = pinyin_tone THEN ''
                    ELSE {shorthand_code_expr}
                END AS input_shorthand_code,
                sort_weight,
                is_common,
                text_length,
                updated_at,
                CASE
                    WHEN entry_type = 'phrase' AND yime_code = pinyin_tone THEN 1
                    ELSE 0
                END AS is_placeholder_code
                        FROM runtime_candidates_materialized
            WHERE yime_code IS NOT NULL
              AND TRIM(yime_code) <> ''
            ORDER BY yime_code, {RUNTIME_SQL_PRIORITY_ORDER}
            '''
        ).fetchall()
    finally:
        conn.close()

    real_rows = [row for row in rows if not row["is_placeholder_code"]]
    placeholder_rows = [row for row in rows if row["is_placeholder_code"]]

    grouped_all = group_rows(rows, args.limit_per_code)
    grouped_real = group_rows(real_rows, args.limit_per_code)
    grouped_placeholder = group_rows(placeholder_rows, args.limit_per_code)
    grouped_real_by_mode = group_rows_by_mode(real_rows, args.limit_per_code)

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
        extra_metadata={
            "default_code_mode": YimeCodeMode.VARIABLE.value,
            "mode_code_counts": {
                mode: len(grouped)
                for mode, grouped in grouped_real_by_mode.items()
            },
        },
    )
    true_payload["by_mode"] = grouped_real_by_mode
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
