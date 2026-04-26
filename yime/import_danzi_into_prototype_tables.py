from __future__ import annotations

import json
import sqlite3
from pathlib import Path


WORKSPACE_ROOT = Path(__file__).resolve().parent.parent
DB_PATH = Path(__file__).resolve().parent / "pinyin_hanzi.db"
DANZI_JSON_PATH = WORKSPACE_ROOT / "pinyin" / "hanzi_pinyin" / "danzi_pinyin.json"
SOURCE_DB_PATH = WORKSPACE_ROOT / "internal_data" / "pinyin_source_db" / "source_pinyin.db"
SCHEMA_PATH = Path(__file__).resolve().parent / "create_prototype_schema_additions.sql"


def load_danzi_data(path: Path) -> dict[str, list[str]]:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def apply_schema(conn: sqlite3.Connection) -> None:
    conn.executescript(SCHEMA_PATH.read_text(encoding="utf-8"))


def load_source_single_char_rows(path: Path) -> tuple[list[tuple[str, str, str]], list[tuple[int, str, str, str, str, str, int, int, str | None, str]]]:
    with sqlite3.connect(path) as source_conn:
        source_cur = source_conn.cursor()
        source_files = source_cur.execute(
            '''
            SELECT source_name, source_kind, source_path
            FROM source_files
            WHERE source_kind = 'single_char'
            ORDER BY source_name
            '''
        ).fetchall()
        rows = source_cur.execute(
            '''
            SELECT id, source_name, codepoint, hanzi, marked_pinyin, numeric_pinyin,
                   reading_rank, is_primary, comment, raw_line
            FROM single_char_readings
            ORDER BY id
            '''
        ).fetchall()
    return source_files, rows


def ensure_numeric_pinyin_rows_from_source(conn: sqlite3.Connection, source_rows: list[tuple[int, str, str, str, str, str, int, int, str | None, str]]) -> None:
    existing = {
        row[0]
        for row in conn.execute('SELECT "全拼" FROM "数字标调拼音"')
    }

    missing_rows: list[tuple[str, str, str, int]] = []
    for row in source_rows:
        pinyin_tone = row[5]
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


def sync_source_single_char_table(
    conn: sqlite3.Connection,
    source_files: list[tuple[str, str, str]],
    source_rows: list[tuple[int, str, str, str, str, str, int, int, str | None, str]],
) -> int:
    conn.execute("DELETE FROM single_char_readings")
    conn.execute("DELETE FROM source_files WHERE source_kind = 'single_char'")
    conn.executemany(
        '''
        INSERT INTO source_files (source_name, source_kind, source_path)
        VALUES (?, ?, ?)
        ''',
        source_files,
    )
    conn.executemany(
        '''
        INSERT INTO single_char_readings (
            id, source_name, codepoint, hanzi, marked_pinyin, numeric_pinyin,
            reading_rank, is_primary, comment, raw_line
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        source_rows,
    )
    return len(source_rows)


def codepoint_to_int(codepoint: str) -> int:
    return int(codepoint[2:], 16)


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


def import_hanzi_and_mappings(conn: sqlite3.Connection, source_rows: list[tuple[int, str, str, str, str, str, int, int, str | None, str]]) -> tuple[int, int, int, int]:
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
    seen_chars: set[int] = set()

    conn.execute('DELETE FROM "汉字数字标调拼音映射"')
    conn.execute('DELETE FROM "汉字音元拼音映射"')

    for _, _, codepoint, hanzi, _, numeric_pinyin, reading_rank, is_primary, _, _ in source_rows:
        char_id = ord(hanzi)
        if char_id not in seen_chars:
            char_rows.append((char_id, hanzi, codepoint_to_int(codepoint), 1))
            seen_chars.add(char_id)

        numeric_row = numeric_pinyin_by_text.get(numeric_pinyin)
        if numeric_row is None:
            continue

        numeric_id, mapping_id = numeric_row
        common_flag = int(is_primary or reading_rank == 1)
        char_map_rows.append((char_id, numeric_id, 1.0, common_flag))

        yime_id = yime_by_mapping_id.get(mapping_id)
        if yime_id is not None:
            yime_map_rows.append((char_id, yime_id, 1.0, common_flag))

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
        ("prototype_danzi_import_source", str(SOURCE_DB_PATH), "单字拼音来源数据库（single_char_readings）"),
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
    source_files, source_rows = load_source_single_char_rows(SOURCE_DB_PATH)
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute('PRAGMA foreign_keys = ON')
        apply_schema(conn)
        ensure_numeric_pinyin_rows_from_source(conn, source_rows)
        copied_rows = sync_source_single_char_table(conn, source_files, source_rows)
        char_count, numeric_map_count, yime_map_count, _ = import_hanzi_and_mappings(conn, source_rows)
        write_import_metadata(conn, char_count, numeric_map_count, yime_map_count)
        conn.commit()
    finally:
        conn.close()

    print(f"copied single_char_readings rows: {copied_rows}")
    print(f"imported chars: {char_count}")
    print(f"numeric mappings: {numeric_map_count}")
    print(f"yime mappings: {yime_map_count}")


if __name__ == "__main__":
    main()
