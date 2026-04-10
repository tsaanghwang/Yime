from __future__ import annotations

import json
import sqlite3
from pathlib import Path


WORKSPACE_ROOT = Path(__file__).resolve().parent.parent
DB_PATH = Path(__file__).resolve().parent / "pinyin_hanzi.db"
DANZI_JSON_PATH = WORKSPACE_ROOT / "pinyin" / "hanzi_pinyin" / "danzi_pinyin.json"


def load_danzi_data(path: Path) -> dict[str, list[str]]:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def ensure_numeric_pinyin_rows(conn: sqlite3.Connection, danzi_data: dict[str, list[str]]) -> None:
    existing = {
        row[0]
        for row in conn.execute('SELECT "全拼" FROM "数字标调拼音"')
    }

    missing_rows: list[tuple[str, str, str, int]] = []
    for pinyin_list in danzi_data.values():
        for pinyin_tone in pinyin_list:
            if pinyin_tone in existing:
                continue

            tone_number = int(pinyin_tone[-1]) if pinyin_tone and pinyin_tone[-1].isdigit() else 5
            base_pinyin = pinyin_tone[:-1] if pinyin_tone and pinyin_tone[-1].isdigit() else pinyin_tone
            missing_rows.append((pinyin_tone, None, base_pinyin, tone_number))
            existing.add(pinyin_tone)

    if missing_rows:
        conn.executemany(
            '''
            INSERT OR IGNORE INTO "数字标调拼音" ("全拼", "声母", "韵母", "声调")
            VALUES (?, ?, ?, ?)
            ''',
            missing_rows,
        )


def import_hanzi_and_mappings(conn: sqlite3.Connection, danzi_data: dict[str, list[str]]) -> tuple[int, int, int, int]:
    numeric_pinyin_rows = conn.execute(
        'SELECT "编号", "全拼", "映射编号" FROM "数字标调拼音"'
    ).fetchall()
    numeric_pinyin_by_text = {row[1]: (row[0], row[2]) for row in numeric_pinyin_rows}

    yime_by_mapping_id = {
        row[0]: row[1]
        for row in conn.execute('SELECT "映射编号", "编号" FROM "音元拼音" WHERE "映射编号" IS NOT NULL')
    }

    char_rows: list[tuple[int, str, int, int]] = []
    char_map_rows: list[tuple[int, int, float, int]] = []
    yime_map_rows: list[tuple[int, int, float, int]] = []
    inserted_frequency_rows = 0

    for hanzi, pinyin_list in danzi_data.items():
        char_id = ord(hanzi)
        char_rows.append((char_id, hanzi, char_id, 1))

        for index, pinyin_tone in enumerate(pinyin_list):
            numeric_row = numeric_pinyin_by_text.get(pinyin_tone)
            if numeric_row is None:
                continue

            numeric_id, mapping_id = numeric_row
            is_common = 1 if index == 0 else 0
            char_map_rows.append((char_id, numeric_id, 1.0, is_common))

            yime_id = yime_by_mapping_id.get(mapping_id)
            if yime_id is not None:
                yime_map_rows.append((char_id, yime_id, 1.0, is_common))

    conn.executemany(
        '''
        INSERT OR IGNORE INTO "汉字" ("编号", "字符", "Unicode码点", "是否常用")
        VALUES (?, ?, ?, ?)
        ''',
        char_rows,
    )

    conn.executemany(
        '''
        INSERT OR REPLACE INTO "汉字数字标调拼音映射" ("汉字编号", "数字标调拼音编号", "频率", "常用读音")
        VALUES (?, ?, ?, ?)
        ''',
        char_map_rows,
    )

    conn.executemany(
        '''
        INSERT OR REPLACE INTO "汉字音元拼音映射" ("汉字编号", "音元拼音编号", "频率", "常用读音")
        VALUES (?, ?, ?, ?)
        ''',
        yime_map_rows,
    )

    return len(char_rows), len(char_map_rows), len(yime_map_rows), inserted_frequency_rows


def write_import_metadata(conn: sqlite3.Connection, char_count: int, numeric_map_count: int, yime_map_count: int) -> None:
    rows = [
        ("prototype_danzi_import_source", str(DANZI_JSON_PATH), "单字拼音 JSON 导入来源"),
        ("prototype_danzi_char_rows", str(char_count), "本次导入覆盖的单字行数"),
        ("prototype_danzi_numeric_map_rows", str(numeric_map_count), "本次导入的汉字到数字标调拼音映射行数"),
        ("prototype_danzi_yime_map_rows", str(yime_map_count), "本次导入的汉字到音元拼音映射行数"),
    ]
    conn.executemany(
        '''
        INSERT OR REPLACE INTO prototype_metadata (key, value, note, updated_at)
        VALUES (?, ?, ?, CURRENT_TIMESTAMP)
        ''',
        rows,
    )


def main() -> None:
    danzi_data = load_danzi_data(DANZI_JSON_PATH)
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute('PRAGMA foreign_keys = ON')
        ensure_numeric_pinyin_rows(conn, danzi_data)
        char_count, numeric_map_count, yime_map_count, _ = import_hanzi_and_mappings(conn, danzi_data)
        write_import_metadata(conn, char_count, numeric_map_count, yime_map_count)
        conn.commit()
    finally:
        conn.close()

    print(f"imported chars: {char_count}")
    print(f"numeric mappings: {numeric_map_count}")
    print(f"yime mappings: {yime_map_count}")


if __name__ == "__main__":
    main()
