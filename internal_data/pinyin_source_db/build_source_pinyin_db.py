from __future__ import annotations

import argparse
import sqlite3
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_DB_PATH = SCRIPT_DIR / "source_pinyin.db"
DEFAULT_SCHEMA_PATH = SCRIPT_DIR / "schema.sql"
DEFAULT_CHAR_SOURCE = Path("C:/dev/pinyin-data/pinyin.txt")
DEFAULT_PHRASE_SOURCE = Path("C:/dev/pinyin-data/tools/phrase-pinyin-data/pinyin.txt")

TONE_CHAR_MAP = {
    "ā": "a1",
    "á": "a2",
    "ǎ": "a3",
    "à": "a4",
    "ē": "e1",
    "é": "e2",
    "ě": "e3",
    "è": "e4",
    "ế": "ê2",
    "ề": "ê4",
    "ī": "i1",
    "í": "i2",
    "ǐ": "i3",
    "ì": "i4",
    "ō": "o1",
    "ó": "o2",
    "ǒ": "o3",
    "ò": "o4",
    "ū": "u1",
    "ú": "u2",
    "ǔ": "u3",
    "ù": "u4",
    "ǖ": "ü1",
    "ǘ": "ü2",
    "ǚ": "ü3",
    "ǜ": "ü4",
    "ń": "n2",
    "ň": "n3",
    "ǹ": "n4",
    "ḿ": "m2",
}


def make_source_name(source_kind: str, source_path: Path) -> str:
    return f"{source_kind}:{source_path.name}"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build the source pinyin SQLite database from upstream text files.")
    parser.add_argument("--db", default=str(DEFAULT_DB_PATH), help="Output SQLite database path")
    parser.add_argument("--schema", default=str(DEFAULT_SCHEMA_PATH), help="Schema SQL file path")
    parser.add_argument("--char-source", default=str(DEFAULT_CHAR_SOURCE), help="Upstream single-character pinyin.txt path")
    parser.add_argument("--phrase-source", default=str(DEFAULT_PHRASE_SOURCE), help="Optional upstream phrase pinyin.txt path")
    parser.add_argument("--keep-existing", action="store_true", help="Keep existing imported rows instead of replacing them")
    return parser.parse_args()


def apply_schema(conn: sqlite3.Connection, schema_path: Path) -> None:
    conn.executescript(schema_path.read_text(encoding="utf-8"))


def reset_import_tables(conn: sqlite3.Connection) -> None:
    conn.execute("DELETE FROM single_char_readings")
    conn.execute("DELETE FROM phrase_readings")
    conn.execute("DELETE FROM source_files")
    conn.execute("DELETE FROM metadata")
    conn.execute("DELETE FROM sqlite_sequence WHERE name IN ('single_char_readings', 'phrase_readings')")


def marked_syllable_to_numeric(marked: str) -> str:
    special_combining = {
        "ê̄": "ê1",
        "ê̌": "ê3",
        "ề": "ê4",
        "m̄": "m1",
        "m̌": "m3",
        "m̀": "m4",
        "n̄": "n1",
        "ň": "n3",
        "ǹ": "n4",
        "n̄g": "ng1",
        "ňg": "ng3",
        "ǹg": "ng4",
        "hm̄": "hm1",
        "hm̌": "hm3",
        "hm̀": "hm4",
        "hn̄": "hn1",
        "hň": "hn3",
        "hǹ": "hn4",
        "hn̄g": "hng1",
        "hňg": "hng3",
        "hǹg": "hng4",
    }
    if marked in special_combining:
        return special_combining[marked]

    numeric = marked + "5"
    for char in marked:
        if char in TONE_CHAR_MAP:
            replacement = TONE_CHAR_MAP[char]
            numeric = marked.replace(char, replacement[0]) + replacement[1]
            break
    return numeric


def marked_phrase_to_numeric(marked_phrase: str) -> str:
    return " ".join(marked_syllable_to_numeric(syllable) for syllable in marked_phrase.split())


def split_comment(raw_line: str) -> tuple[str, str | None]:
    if "#" not in raw_line:
        return raw_line.rstrip(), None
    content, comment = raw_line.split("#", 1)
    return content.rstrip(), comment.strip() or None


def import_single_char_source(conn: sqlite3.Connection, source_path: Path) -> int:
    source_name = make_source_name("single_char", source_path)
    conn.execute(
        "INSERT OR REPLACE INTO source_files (source_name, source_kind, source_path) VALUES (?, 'single_char', ?)",
        (source_name, str(source_path)),
    )

    inserted = 0
    with source_path.open("r", encoding="utf-8") as handle:
        for line in handle:
            raw_line = line.rstrip("\n")
            stripped = raw_line.strip()
            if not stripped or stripped.startswith("#"):
                continue

            content, comment = split_comment(raw_line)
            codepoint_part, pinyin_part = content.split(":", 1)
            codepoint = codepoint_part.strip()
            pinyins = [value.strip() for value in pinyin_part.split(",") if value.strip()]
            if not pinyins:
                continue

            hanzi = comment.split()[0] if comment else ""
            for index, marked_pinyin in enumerate(pinyins, start=1):
                conn.execute(
                    """
                    INSERT OR REPLACE INTO single_char_readings (
                        source_name,
                        codepoint,
                        hanzi,
                        marked_pinyin,
                        numeric_pinyin,
                        reading_rank,
                        is_primary,
                        comment,
                        raw_line
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        source_name,
                        codepoint,
                        hanzi,
                        marked_pinyin,
                        marked_syllable_to_numeric(marked_pinyin),
                        index,
                        1 if index == 1 else 0,
                        comment,
                        raw_line,
                    ),
                )
                inserted += 1

    return inserted


def import_phrase_source(conn: sqlite3.Connection, source_path: Path) -> int:
    source_name = make_source_name("phrase", source_path)
    conn.execute(
        "INSERT OR REPLACE INTO source_files (source_name, source_kind, source_path) VALUES (?, 'phrase', ?)",
        (source_name, str(source_path)),
    )

    inserted = 0
    with source_path.open("r", encoding="utf-8") as handle:
        for line in handle:
            raw_line = line.rstrip("\n")
            stripped = raw_line.strip()
            if not stripped or stripped.startswith("#"):
                continue

            content, comment = split_comment(raw_line)
            phrase_part, pinyin_part = content.split(":", 1)
            phrase = phrase_part.strip()
            marked_pinyin = pinyin_part.strip()
            if not phrase or not marked_pinyin:
                continue

            conn.execute(
                """
                INSERT OR REPLACE INTO phrase_readings (
                    source_name,
                    phrase,
                    marked_pinyin,
                    numeric_pinyin,
                    reading_rank,
                    comment,
                    raw_line
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    source_name,
                    phrase,
                    marked_pinyin,
                    marked_phrase_to_numeric(marked_pinyin),
                    1,
                    comment,
                    raw_line,
                ),
            )
            inserted += 1

    return inserted


def write_metadata(conn: sqlite3.Connection, key: str, value: str) -> None:
    conn.execute("INSERT OR REPLACE INTO metadata (key, value) VALUES (?, ?)", (key, value))


def main() -> None:
    args = parse_args()
    db_path = Path(args.db)
    schema_path = Path(args.schema)
    char_source = Path(args.char_source)
    phrase_source = Path(args.phrase_source)

    if not char_source.exists():
        raise FileNotFoundError(f"single-character source not found: {char_source}")
    if not schema_path.exists():
        raise FileNotFoundError(f"schema file not found: {schema_path}")

    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(db_path)
    try:
        apply_schema(conn, schema_path)
        if not args.keep_existing:
            reset_import_tables(conn)

        single_rows = import_single_char_source(conn, char_source)
        phrase_rows = 0
        if phrase_source.exists():
            phrase_rows = import_phrase_source(conn, phrase_source)

        write_metadata(conn, "schema_version", "source_pinyin_v1")
        write_metadata(conn, "single_char_source", str(char_source))
        write_metadata(conn, "single_char_rows", str(single_rows))
        write_metadata(conn, "phrase_source", str(phrase_source) if phrase_source.exists() else "")
        write_metadata(conn, "phrase_rows", str(phrase_rows))
        conn.commit()
    finally:
        conn.close()

    print(f"built database: {db_path}")
    print(f"single_char_readings rows: {single_rows}")
    print(f"phrase_readings rows: {phrase_rows}")


if __name__ == "__main__":
    main()
