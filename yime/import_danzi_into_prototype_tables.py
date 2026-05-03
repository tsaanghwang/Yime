from __future__ import annotations

import csv
import sqlite3
from pathlib import Path

from yime.canonical_yime_mapping import sync_canonical_mapping_table


WORKSPACE_ROOT = Path(__file__).resolve().parent.parent
DB_PATH = Path(__file__).resolve().parent / "pinyin_hanzi.db"
SOURCE_DB_PATH = WORKSPACE_ROOT / "internal_data" / "pinyin_source_db" / "source_pinyin.db"
SCHEMA_PATH = Path(__file__).resolve().parent / "create_prototype_schema_additions.sql"
NUMERIC_PATCH_PATH = WORKSPACE_ROOT / "internal_data" / "pinyin_source_db" / "numeric_pinyin_patch.csv"


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


def load_numeric_pinyin_patch_rows(path: Path) -> list[tuple[str, str | None, str | None, int, int | None, int | None]]:
    if not path.exists():
        return []

    patch_rows: list[tuple[str, str | None, str | None, int, int | None, int | None]] = []
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            pinyin_tone = str(row.get("pinyin_tone") or "").strip()
            if not pinyin_tone:
                continue

            initial = str(row.get("initial") or "").strip() or None
            final = str(row.get("final") or "").strip() or None
            tone_number_raw = str(row.get("tone_number") or "").strip()
            mapping_id_raw = str(row.get("mapping_id") or "").strip()
            legacy_numeric_raw = str(row.get("legacy_numeric_pinyin_id") or "").strip()

            tone_number = int(tone_number_raw) if tone_number_raw else 5
            mapping_id = int(mapping_id_raw) if mapping_id_raw else None
            legacy_numeric_pinyin_id = int(legacy_numeric_raw) if legacy_numeric_raw else None
            patch_rows.append((
                pinyin_tone,
                initial,
                final,
                tone_number,
                mapping_id,
                legacy_numeric_pinyin_id,
            ))

    return patch_rows


def import_hanzi_and_mappings(conn: sqlite3.Connection, source_rows: list[tuple[int, str, str, str, str, str, int, int, str | None, str]]) -> tuple[int, int, int, int]:
    char_rows: list[tuple[str, int | None, str | None, int, int | None]] = []
    numeric_rows: list[tuple[str, str | None, str | None, int, int | None, int | None]] = []
    char_map_rows: list[tuple[str, str, float, int, str, str | None]] = []
    patched_numeric_rows = 0
    seen_chars: set[int] = set()
    seen_numeric_pinyin: set[str] = set()

    conn.execute('DELETE FROM char_pinyin_map')
    conn.execute('DELETE FROM char_inventory')
    conn.execute('DELETE FROM numeric_pinyin_inventory')

    for _, source_name, codepoint, hanzi, _, numeric_pinyin, reading_rank, is_primary, comment, _ in source_rows:
        char_id = ord(hanzi)
        if char_id not in seen_chars:
            char_rows.append((
                hanzi,
                None,
                None,
                1,
                None,
            ))
            seen_chars.add(char_id)

        if numeric_pinyin not in seen_numeric_pinyin:
            initial, final, tone_number = parse_numeric_pinyin_parts(numeric_pinyin)
            numeric_rows.append((numeric_pinyin, initial, final, tone_number, None, None))
            seen_numeric_pinyin.add(numeric_pinyin)

        common_flag = int(is_primary or reading_rank == 1)
        char_map_rows.append((hanzi, numeric_pinyin, 1.0, common_flag, source_name, comment))

    for patch_row in load_numeric_pinyin_patch_rows(NUMERIC_PATCH_PATH):
        pinyin_tone = patch_row[0]
        if pinyin_tone in seen_numeric_pinyin:
            continue
        numeric_rows.append(patch_row)
        seen_numeric_pinyin.add(pinyin_tone)
        patched_numeric_rows += 1

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

    sync_canonical_mapping_table(conn, WORKSPACE_ROOT)

    yime_by_pinyin = {
        row[0]: row[1]
        for row in conn.execute('SELECT pinyin_tone, yime_code FROM pinyin_yime_code')
    }

    char_inventory_id_by_hanzi = {
        row[1]: row[0]
        for row in conn.execute('SELECT id, hanzi FROM char_inventory')
    }
    numeric_inventory_by_text = {
        row[1]: row[0]
        for row in conn.execute('SELECT id, pinyin_tone FROM numeric_pinyin_inventory')
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
            numeric_inventory,
            reading_weight,
            common_flag,
            source_name,
            comment,
        ))
        if yime_by_pinyin.get(numeric_pinyin) is not None:
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

    return len(char_rows), len(resolved_char_map_rows), resolved_yime_rows, patched_numeric_rows


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
    patched_numeric_count: int,
) -> None:
    rows = [
        ("prototype_danzi_import_source", str(SOURCE_DB_PATH), "单字拼音来源数据库（single_char_readings）"),
        ("prototype_danzi_char_rows", str(char_count), "本次导入覆盖的单字行数"),
        ("prototype_danzi_numeric_map_rows", str(numeric_map_count), "本次导入的 char_pinyin_map 行数"),
        ("prototype_danzi_yime_map_rows", str(yime_map_count), "本次可解析到音元拼音编码的单字读音行数"),
        ("prototype_danzi_yime_source", "pinyin_yime_code", "单字运行时 yime_code 来源改为 canonical 拼音映射面，不再依赖 mapping_id"),
        ("prototype_danzi_source_distinct_hanzi", str(source_distinct_count), "single_char_readings 中去重后的汉字数"),
        ("prototype_danzi_inventory_coverage", "ok", "char_inventory 与 single_char_readings 汉字集合一致"),
        ("prototype_danzi_numeric_patch_source", str(NUMERIC_PATCH_PATH), "单字数字调拼音补丁源；用于补齐上游 pinyin.txt 缺失的 numeric_pinyin_inventory 行"),
        ("prototype_danzi_numeric_patch_rows", str(patched_numeric_count), "本次从 numeric_pinyin_patch.csv 补入的数字调拼音行数"),
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
        conn.execute('DROP TABLE IF EXISTS pinyin_yime_code')
        conn.execute('DROP TABLE IF EXISTS mapping_yime_code')
        apply_schema(conn)
        copied_rows = sync_source_single_char_table(conn, source_files, source_rows)
        char_count, numeric_map_count, yime_map_count, patched_numeric_count = import_hanzi_and_mappings(conn, source_rows)
        source_distinct_count, _, _ = validate_char_inventory_coverage(conn)
        write_import_metadata(conn, char_count, numeric_map_count, yime_map_count, source_distinct_count, patched_numeric_count)
        conn.commit()
    finally:
        conn.close()

    print(f"copied single_char_readings rows: {copied_rows}")
    print(f"imported chars: {char_count}")
    print(f"numeric mappings: {numeric_map_count}")
    print(f"yime mappings: {yime_map_count}")
    print(f"patched numeric rows: {patched_numeric_count}")


if __name__ == "__main__":
    main()
