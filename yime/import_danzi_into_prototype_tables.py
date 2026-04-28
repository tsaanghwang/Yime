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


def parse_numeric_pinyin_parts(pinyin_tone: str) -> tuple[str | None, str | None, int]:
    tone_number = int(pinyin_tone[-1]) if pinyin_tone and pinyin_tone[-1].isdigit() else 5
    final = pinyin_tone[:-1] if pinyin_tone and pinyin_tone[-1].isdigit() else pinyin_tone
    return None, final or None, tone_number


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
    legacy_char_rows = conn.execute(
        'SELECT "编号", "字符", "画数", "部首", "是否常用" FROM "汉字"'
    ).fetchall()
    legacy_char_by_hanzi = {
        row[1]: {
            "legacy_char_id": row[0],
            "stroke_count": row[2],
            "radical": row[3],
            "is_common_char": row[4],
        }
        for row in legacy_char_rows
    }

    legacy_numeric_rows = conn.execute(
        'SELECT "编号", "全拼", "声母", "韵母", "声调", "映射编号" FROM "数字标调拼音"'
    ).fetchall()
    legacy_numeric_by_text = {
        row[1]: {
            "legacy_numeric_pinyin_id": row[0],
            "initial": row[2],
            "final": row[3],
            "tone_number": row[4],
            "mapping_id": row[5],
        }
        for row in legacy_numeric_rows
    }

    yime_by_mapping_id = {
        row[0]: row[1]
        for row in conn.execute('SELECT "映射编号", "编号" FROM "音元拼音" WHERE "映射编号" IS NOT NULL')
    }

    char_rows: list[tuple[str, int | None, str | None, int, int | None]] = []
    numeric_rows: list[tuple[str, str | None, str | None, int, int | None, int | None]] = []
    char_map_rows: list[tuple[str, str, float, int, str, str | None]] = []
    inserted_frequency_rows = 0
    seen_chars: set[int] = set()
    seen_numeric_pinyin: set[str] = set()

    conn.execute('DELETE FROM char_pinyin_map')
    conn.execute('DELETE FROM char_inventory')
    conn.execute('DELETE FROM numeric_pinyin_inventory')

    for _, source_name, codepoint, hanzi, _, numeric_pinyin, reading_rank, is_primary, comment, _ in source_rows:
        char_id = ord(hanzi)
        if char_id not in seen_chars:
            legacy_char = legacy_char_by_hanzi.get(hanzi, {})
            char_rows.append((
                hanzi,
                legacy_char.get("stroke_count"),
                legacy_char.get("radical"),
                int(legacy_char.get("is_common_char", 1) or 0),
                legacy_char.get("legacy_char_id"),
            ))
            seen_chars.add(char_id)

        if numeric_pinyin not in seen_numeric_pinyin:
            legacy_numeric = legacy_numeric_by_text.get(numeric_pinyin)
            if legacy_numeric is None:
                initial, final, tone_number = parse_numeric_pinyin_parts(numeric_pinyin)
                numeric_rows.append((numeric_pinyin, initial, final, tone_number, None, None))
            else:
                numeric_rows.append((
                    numeric_pinyin,
                    legacy_numeric.get("initial"),
                    legacy_numeric.get("final"),
                    int(legacy_numeric.get("tone_number") or 5),
                    legacy_numeric.get("mapping_id"),
                    legacy_numeric.get("legacy_numeric_pinyin_id"),
                ))
            seen_numeric_pinyin.add(numeric_pinyin)

        common_flag = int(is_primary or reading_rank == 1)
        char_map_rows.append((hanzi, numeric_pinyin, 1.0, common_flag, source_name, comment))

    conn.executemany(
        '''
        INSERT INTO char_inventory (
            hanzi,
            stroke_count,
            radical,
            is_common_char,
            legacy_char_id,
            updated_at
        ) VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
        ''',
        char_rows,
    )

    conn.executemany(
        '''
        INSERT INTO numeric_pinyin_inventory (
            pinyin_tone,
            initial,
            final,
            tone_number,
            mapping_id,
            legacy_numeric_pinyin_id,
            updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
        ''',
        numeric_rows,
    )

    char_inventory_id_by_hanzi = {
        row[1]: row[0]
        for row in conn.execute('SELECT id, hanzi FROM char_inventory')
    }
    numeric_inventory_by_text = {
        row[1]: (row[0], row[2])
        for row in conn.execute('SELECT id, pinyin_tone, mapping_id FROM numeric_pinyin_inventory')
    }

    resolved_yime_rows = 0
    resolved_char_map_rows: list[tuple[int, int, float, int, str, str | None]] = []
    for hanzi, numeric_pinyin, reading_weight, common_flag, source_name, comment in char_map_rows:
        char_inventory_id = char_inventory_id_by_hanzi.get(hanzi)
        numeric_inventory = numeric_inventory_by_text.get(numeric_pinyin)
        if char_inventory_id is None or numeric_inventory is None:
            continue
        resolved_char_map_rows.append((
            char_inventory_id,
            numeric_inventory[0],
            reading_weight,
            common_flag,
            source_name,
            comment,
        ))
        mapping_id = numeric_inventory[1]
        if mapping_id is not None and yime_by_mapping_id.get(mapping_id) is not None:
            resolved_yime_rows += 1

    conn.executemany(
        '''
        INSERT OR REPLACE INTO char_pinyin_map (
            char_id,
            numeric_pinyin_id,
            reading_weight,
            is_common_reading,
            source_file,
            source_note,
            updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
        ''',
        resolved_char_map_rows,
    )

    return len(char_rows), len(resolved_char_map_rows), resolved_yime_rows, inserted_frequency_rows


def validate_char_inventory_coverage(conn: sqlite3.Connection) -> tuple[int, int, int]:
    missing_count = conn.execute(
        '''
        SELECT COUNT(DISTINCT scr.hanzi)
        FROM single_char_readings scr
        LEFT JOIN char_inventory ci
          ON ci.hanzi = scr.hanzi
        WHERE ci.id IS NULL
        '''
    ).fetchone()[0]
    extra_count = conn.execute(
        '''
        SELECT COUNT(*)
        FROM char_inventory ci
        LEFT JOIN (
            SELECT DISTINCT hanzi
            FROM single_char_readings
        ) scr
          ON scr.hanzi = ci.hanzi
        WHERE scr.hanzi IS NULL
        '''
    ).fetchone()[0]
    source_distinct_count = conn.execute(
        'SELECT COUNT(DISTINCT hanzi) FROM single_char_readings'
    ).fetchone()[0]

    if missing_count or extra_count:
        raise RuntimeError(
            f"char_inventory coverage mismatch: missing={missing_count}, extra={extra_count}"
        )

    return source_distinct_count, missing_count, extra_count


def write_import_metadata(
    conn: sqlite3.Connection,
    char_count: int,
    numeric_map_count: int,
    yime_map_count: int,
    source_distinct_count: int,
) -> None:
    rows = [
        ("prototype_danzi_import_source", str(SOURCE_DB_PATH), "单字拼音来源数据库（single_char_readings）"),
        ("prototype_danzi_char_rows", str(char_count), "本次导入覆盖的单字行数"),
        ("prototype_danzi_numeric_map_rows", str(numeric_map_count), "本次导入的 char_pinyin_map 行数"),
        ("prototype_danzi_yime_map_rows", str(yime_map_count), "本次可解析到音元拼音编码的单字读音行数"),
        ("prototype_danzi_source_distinct_hanzi", str(source_distinct_count), "single_char_readings 中去重后的汉字数"),
        ("prototype_danzi_inventory_coverage", "ok", "char_inventory 与 single_char_readings 汉字集合一致"),
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
        conn.execute('DROP TABLE IF EXISTS char_pinyin_map')
        conn.execute('DROP TABLE IF EXISTS char_inventory')
        conn.execute('DROP TABLE IF EXISTS numeric_pinyin_inventory')
        apply_schema(conn)
        copied_rows = sync_source_single_char_table(conn, source_files, source_rows)
        char_count, numeric_map_count, yime_map_count, _ = import_hanzi_and_mappings(conn, source_rows)
        source_distinct_count, _, _ = validate_char_inventory_coverage(conn)
        write_import_metadata(conn, char_count, numeric_map_count, yime_map_count, source_distinct_count)
        conn.commit()
    finally:
        conn.close()

    print(f"copied single_char_readings rows: {copied_rows}")
    print(f"imported chars: {char_count}")
    print(f"numeric mappings: {numeric_map_count}")
    print(f"yime mappings: {yime_map_count}")


if __name__ == "__main__":
    main()
