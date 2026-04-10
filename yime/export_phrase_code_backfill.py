from __future__ import annotations

import argparse
import json
import sqlite3
from pathlib import Path


DB_PATH = Path(__file__).resolve().parent / "pinyin_hanzi.db"
DEFAULT_OUTPUT_PATH = Path(__file__).resolve().parent / "reports" / "phrase_code_backfill.json"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="导出词语编码待回填清单")
    parser.add_argument("--db", default=str(DB_PATH), help="SQLite 数据库路径")
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT_PATH), help="JSON 输出路径")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    db_path = Path(args.db)
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    try:
        rows = conn.execute(
            '''
            SELECT
                phrase_id,
                phrase,
                pinyin_tone,
                reading_rank,
                yime_code,
                phrase_frequency,
                phrase_length,
                source_file,
                source_note,
                updated_at
            FROM phrase_lexicon_view
            WHERE yime_code = pinyin_tone
            ORDER BY phrase, reading_rank
            '''
        ).fetchall()
    finally:
        conn.close()

    records = [dict(row) for row in rows]
    payload = {
        "metadata": {
            "db_path": str(db_path),
            "record_count": len(records),
            "description": "词语音元拼音编码待回填清单。当前 yime_code 与 pinyin_tone 相同，表示仍是数字标调拼音占位。",
        },
        "records": records,
    }

    output_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"exported placeholder records: {len(records)}")
    print(f"output: {output_path}")


if __name__ == "__main__":
    main()
