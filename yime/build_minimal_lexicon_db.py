from __future__ import annotations

import argparse
import json
import sqlite3
from pathlib import Path


WORKSPACE_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_DB_PATH = Path(__file__).resolve().parent / "minimal_lexicon.db"
DEFAULT_SCHEMA_PATH = Path(__file__).resolve().parent / "create_minimal_lexicon_schema.sql"
DEFAULT_DANZI_PATH = WORKSPACE_ROOT / "pinyin" / "hanzi_pinyin" / "danzi_pinyin.json"
DEFAULT_DUOZI_PATH = WORKSPACE_ROOT / "pinyin" / "hanzi_pinyin" / "duozi_pinyin.json"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="从 danzi_pinyin.json 和 duozi_pinyin.json 构建最小 SQLite 词库")
    parser.add_argument("--db", default=str(DEFAULT_DB_PATH), help="输出 SQLite 数据库路径")
    parser.add_argument("--schema", default=str(DEFAULT_SCHEMA_PATH), help="SQLite schema SQL 文件路径")
    parser.add_argument("--danzi", default=str(DEFAULT_DANZI_PATH), help="单字拼音 JSON 路径")
    parser.add_argument("--duozi", default=str(DEFAULT_DUOZI_PATH), help="词语拼音 JSON 路径")
    parser.add_argument("--keep-existing", action="store_true", help="保留现有表数据，默认会清空后重建")
    return parser.parse_args()


def load_json(path: Path) -> dict[str, list[str]]:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def apply_schema(conn: sqlite3.Connection, schema_path: Path) -> None:
    sql = schema_path.read_text(encoding="utf-8")
    conn.executescript(sql)


def reset_tables(conn: sqlite3.Connection) -> None:
    conn.execute("DELETE FROM single_char_lexicon")
    conn.execute("DELETE FROM sqlite_sequence WHERE name='single_char_lexicon'")
    conn.execute("DELETE FROM phrase_lexicon")
    conn.execute("DELETE FROM sqlite_sequence WHERE name='phrase_lexicon'")
    conn.execute("DELETE FROM metadata")


def import_single_chars(conn: sqlite3.Connection, data: dict[str, list[str]], source_file: str) -> int:
    inserted = 0
    for hanzi, pinyin_list in data.items():
        for index, pinyin_tone in enumerate(pinyin_list, start=1):
            conn.execute(
                """
                INSERT OR REPLACE INTO single_char_lexicon (
                    hanzi,
                    pinyin_tone,
                    reading_rank,
                    char_frequency,
                    yime_code,
                    source_file,
                    source_note,
                    enabled
                ) VALUES (?, ?, ?, NULL, NULL, ?, NULL, 1)
                """,
                (hanzi, pinyin_tone, index, source_file),
            )
            inserted += 1
    return inserted


def import_phrases(conn: sqlite3.Connection, data: dict[str, list[str]], source_file: str) -> int:
    inserted = 0
    for phrase, pinyin_list in data.items():
        for index, pinyin_tone in enumerate(pinyin_list, start=1):
            conn.execute(
                """
                INSERT OR REPLACE INTO phrase_lexicon (
                    phrase,
                    pinyin_tone,
                    reading_rank,
                    phrase_frequency,
                    yime_code,
                    source_file,
                    source_note,
                    enabled
                ) VALUES (?, ?, ?, NULL, NULL, ?, NULL, 1)
                """,
                (phrase, pinyin_tone, index, source_file),
            )
            inserted += 1
    return inserted


def write_metadata(conn: sqlite3.Connection, danzi_path: Path, duozi_path: Path, single_rows: int, phrase_rows: int) -> None:
    metadata = {
        "schema": "minimal_lexicon_v1",
        "single_source": str(danzi_path),
        "phrase_source": str(duozi_path),
        "single_rows": str(single_rows),
        "phrase_rows": str(phrase_rows),
    }
    for key, value in metadata.items():
        conn.execute("INSERT OR REPLACE INTO metadata (key, value) VALUES (?, ?)", (key, value))


def main() -> None:
    args = parse_args()
    db_path = Path(args.db)
    schema_path = Path(args.schema)
    danzi_path = Path(args.danzi)
    duozi_path = Path(args.duozi)

    danzi_data = load_json(danzi_path)
    duozi_data = load_json(duozi_path)

    conn = sqlite3.connect(db_path)
    try:
        apply_schema(conn, schema_path)
        if not args.keep_existing:
            reset_tables(conn)
        single_rows = import_single_chars(conn, danzi_data, danzi_path.name)
        phrase_rows = import_phrases(conn, duozi_data, duozi_path.name)
        write_metadata(conn, danzi_path, duozi_path, single_rows, phrase_rows)
        conn.commit()
    finally:
        conn.close()

    print(f"built database: {db_path}")
    print(f"single_char_lexicon rows: {single_rows}")
    print(f"phrase_lexicon rows: {phrase_rows}")


if __name__ == "__main__":
    main()
