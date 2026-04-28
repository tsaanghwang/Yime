from __future__ import annotations

import sqlite3
from pathlib import Path


WORKSPACE_ROOT = Path(__file__).resolve().parent.parent
DB_PATH = Path(__file__).resolve().parent / "pinyin_hanzi.db"
SOURCE_DB_PATH = WORKSPACE_ROOT / "internal_data" / "pinyin_source_db" / "source_pinyin.db"
SCHEMA_PATH = Path(__file__).resolve().parent / "create_prototype_schema_additions.sql"


def apply_schema(conn: sqlite3.Connection) -> None:
    conn.executescript(SCHEMA_PATH.read_text(encoding="utf-8"))


def load_source_phrase_rows(path: Path) -> tuple[list[tuple[str, str, str]], list[tuple[int, str, str, str, str, int, str | None, str]]]:
    with sqlite3.connect(path) as source_conn:
        source_cur = source_conn.cursor()
        source_files = source_cur.execute(
            '''
            SELECT source_name, source_kind, source_path
            FROM source_files
            WHERE source_kind = 'phrase'
            ORDER BY source_name
            '''
        ).fetchall()
        rows = source_cur.execute(
            '''
            SELECT id, source_name, phrase, marked_pinyin, numeric_pinyin,
                   reading_rank, comment, raw_line
            FROM phrase_readings
            ORDER BY id
            '''
        ).fetchall()
    return source_files, rows


def parse_numeric_pinyin_parts(pinyin_tone: str) -> tuple[str | None, str | None, int]:
    tone_number = int(pinyin_tone[-1]) if pinyin_tone and pinyin_tone[-1].isdigit() else 5
    final = pinyin_tone[:-1] if pinyin_tone and pinyin_tone[-1].isdigit() else pinyin_tone
    return None, final or None, tone_number


def build_phrase_yime_code(phrase_pinyin: str, numeric_pinyin_by_text: dict[str, tuple[int, int | None]], yime_by_mapping_id: dict[int, str]) -> str | None:
    syllable_codes: list[str] = []
    for syllable in phrase_pinyin.split():
        numeric_row = numeric_pinyin_by_text.get(syllable)
        if numeric_row is None:
            return None

        _, mapping_id = numeric_row
        if mapping_id is None:
            return None

        yime_code = yime_by_mapping_id.get(mapping_id)
        if yime_code is None:
            return None

        syllable_codes.append(yime_code)

    return " ".join(syllable_codes)


def sync_source_phrase_table(
    conn: sqlite3.Connection,
    source_files: list[tuple[str, str, str]],
    source_rows: list[tuple[int, str, str, str, str, int, str | None, str]],
) -> int:
    conn.execute("DELETE FROM phrase_readings")
    conn.execute("DELETE FROM source_files WHERE source_kind = 'phrase'")
    conn.executemany(
        '''
        INSERT INTO source_files (source_name, source_kind, source_path)
        VALUES (?, ?, ?)
        ''',
        source_files,
    )
    conn.executemany(
        '''
        INSERT INTO phrase_readings (
            id, source_name, phrase, marked_pinyin, numeric_pinyin,
            reading_rank, comment, raw_line
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        source_rows,
    )
    return len(source_rows)


def import_phrases_and_mappings(
    conn: sqlite3.Connection,
    source_rows: list[tuple[int, str, str, str, str, int, str | None, str]],
) -> tuple[int, int]:
    numeric_pinyin_rows = conn.execute(
        'SELECT id, pinyin_tone, mapping_id FROM numeric_pinyin_inventory'
    ).fetchall()
    numeric_pinyin_by_text = {row[1]: (row[0], row[2]) for row in numeric_pinyin_rows}

    if not numeric_pinyin_by_text:
        legacy_numeric_rows = conn.execute(
            'SELECT "编号", "全拼", "声母", "韵母", "声调", "映射编号" FROM "数字标调拼音"'
        ).fetchall()
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
            [
                (row[1], row[2], row[3], int(row[4] or 5), row[5], row[0])
                for row in legacy_numeric_rows
            ],
        )
        numeric_pinyin_rows = conn.execute(
            'SELECT id, pinyin_tone, mapping_id FROM numeric_pinyin_inventory'
        ).fetchall()
        numeric_pinyin_by_text = {row[1]: (row[0], row[2]) for row in numeric_pinyin_rows}

    yime_by_mapping_id = {
        row[0]: row[1]
        for row in conn.execute('SELECT "映射编号", "全拼" FROM "音元拼音" WHERE "映射编号" IS NOT NULL')
    }

    legacy_phrase_by_text = {
        row[1]: row[0]
        for row in conn.execute('SELECT "编号", "词语" FROM "词汇"')
    }

    missing_numeric_rows: list[tuple[str, str | None, str | None, int, int | None, int | None]] = []
    seen_missing_numeric: set[str] = set()
    phrase_rows_by_text: dict[str, tuple[str, str | None, float, int, int, int | None]] = {}
    phrase_map_rows: list[tuple[int, str, int, str, str]] = []

    for _, source_name, phrase, _, numeric_pinyin, reading_rank, comment, _ in source_rows:
        for syllable in numeric_pinyin.split():
            if syllable in numeric_pinyin_by_text or syllable in seen_missing_numeric:
                continue
            initial, final, tone_number = parse_numeric_pinyin_parts(syllable)
            missing_numeric_rows.append((syllable, initial, final, tone_number, None, None))
            seen_missing_numeric.add(syllable)
        if phrase not in phrase_rows_by_text:
            primary_yime_code = build_phrase_yime_code(numeric_pinyin, numeric_pinyin_by_text, yime_by_mapping_id)
            stored_phrase_code = primary_yime_code or numeric_pinyin
            phrase_rows_by_text[phrase] = (phrase, stored_phrase_code, 1.0, len(phrase), 1, legacy_phrase_by_text.get(phrase))

    if missing_numeric_rows:
        conn.executemany(
            '''
            INSERT OR IGNORE INTO numeric_pinyin_inventory (
                pinyin_tone,
                initial,
                final,
                tone_number,
                mapping_id,
                legacy_numeric_pinyin_id,
                updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
            ''',
            missing_numeric_rows,
        )
        numeric_pinyin_rows = conn.execute(
            'SELECT id, pinyin_tone, mapping_id FROM numeric_pinyin_inventory'
        ).fetchall()
        numeric_pinyin_by_text = {row[1]: (row[0], row[2]) for row in numeric_pinyin_rows}

    phrase_rows = list(phrase_rows_by_text.values())

    conn.execute('DELETE FROM phrase_inventory')
    conn.executemany(
        '''
        INSERT INTO phrase_inventory (
            phrase,
            yime_code,
            phrase_frequency,
            phrase_length,
            is_common_phrase,
            legacy_phrase_id,
            updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
        ''',
        phrase_rows,
    )

    phrase_id_by_text = {
        row[1]: row[0]
        for row in conn.execute('SELECT id, phrase FROM phrase_inventory')
    }

    conn.execute('DELETE FROM phrase_pinyin_map')

    for _, source_name, phrase, _, numeric_pinyin, reading_rank, comment, _ in source_rows:
        phrase_id = phrase_id_by_text[phrase]
        phrase_map_rows.append((
            phrase_id,
            numeric_pinyin,
            reading_rank,
            source_name,
            comment or 'source_pinyin.db.phrase_readings',
        ))

    conn.executemany(
        '''
        INSERT OR REPLACE INTO phrase_pinyin_map (phrase_id, pinyin_tone, reading_rank, source_file, source_note)
        VALUES (?, ?, ?, ?, ?)
        ''',
        phrase_map_rows,
    )

    return len(phrase_rows), len(phrase_map_rows)


def write_import_metadata(conn: sqlite3.Connection, phrase_count: int, phrase_map_count: int) -> None:
    rows = [
        ("prototype_duozi_import_source", str(SOURCE_DB_PATH), "词语拼音来源数据库（phrase_readings）"),
        ("prototype_duozi_phrase_rows", str(phrase_count), "本次导入覆盖的词语读音行数"),
        ("prototype_duozi_phrase_map_rows", str(phrase_map_count), "本次导入的 phrase_pinyin_map 行数"),
    ]
    conn.executemany(
        '''
        INSERT OR REPLACE INTO prototype_metadata (key, value, note, updated_at)
        VALUES (?, ?, ?, CURRENT_TIMESTAMP)
        ''',
        rows,
    )


def main() -> None:
    source_files, source_rows = load_source_phrase_rows(SOURCE_DB_PATH)
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute('PRAGMA foreign_keys = ON')
        conn.execute('DROP TABLE IF EXISTS phrase_pinyin_map')
        conn.execute('DROP TABLE IF EXISTS phrase_inventory')
        apply_schema(conn)
        copied_rows = sync_source_phrase_table(conn, source_files, source_rows)
        phrase_count, phrase_map_count = import_phrases_and_mappings(conn, source_rows)
        write_import_metadata(conn, phrase_count, phrase_map_count)
        conn.commit()
    finally:
        conn.close()

    print(f"copied phrase_readings rows: {copied_rows}")
    print(f"imported phrases: {phrase_count}")
    print(f"phrase pinyin mappings: {phrase_map_count}")


if __name__ == "__main__":
    main()
