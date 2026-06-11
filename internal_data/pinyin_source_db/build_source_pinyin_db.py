from __future__ import annotations

import argparse
import csv
import json
import re
import shutil
import sqlite3
from pathlib import Path
from typing import Any, cast


SCRIPT_DIR = Path(__file__).resolve().parent
WORKSPACE_ROOT = SCRIPT_DIR.parent.parent
DEFAULT_DB_PATH = WORKSPACE_ROOT / ".generated" / "source_pinyin.db"
LEGACY_DB_PATH = WORKSPACE_ROOT / "internal_data" / "pinyin_source_db" / "source_pinyin.db"
DEFAULT_SCHEMA_PATH = SCRIPT_DIR / "schema.sql"
# Default char source now comes from workspace-level external_data
DEFAULT_CHAR_SOURCE = WORKSPACE_ROOT / "external_data" / "unicode_hanzi.txt"
DEFAULT_PHRASE_SOURCE = Path("C:/dev/pinyin-data/tools/phrase-pinyin-data/pinyin.txt")
NUMERIC_SYLLABLE_RE = re.compile(r"^[a-zêü]+[1-5]$")

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
    parser.add_argument("--char-source", default=str(DEFAULT_CHAR_SOURCE), help="Unicode Hanzi TSV source path")
    parser.add_argument("--phrase-source", default=str(DEFAULT_PHRASE_SOURCE), help="Optional upstream phrase pinyin.txt path")
    parser.add_argument("--keep-existing", action="store_true", help="Keep existing imported rows instead of replacing them")
    return parser.parse_args()


def apply_schema(conn: sqlite3.Connection, schema_path: Path) -> None:
    conn.execute("DROP INDEX IF EXISTS idx_single_char_hanzi")
    conn.execute("DROP INDEX IF EXISTS idx_single_char_numeric")
    conn.execute("DROP INDEX IF EXISTS idx_single_char_codepoint")
    conn.execute("DROP TABLE IF EXISTS single_char_readings")
    conn.executescript(schema_path.read_text(encoding="utf-8"))


def reset_import_tables(conn: sqlite3.Connection) -> None:
    conn.execute("DELETE FROM char_readings")
    conn.execute("DELETE FROM phrase_readings")
    conn.execute("DELETE FROM source_files")
    conn.execute("DELETE FROM metadata")
    conn.execute("DELETE FROM sqlite_sequence WHERE name IN ('char_readings', 'phrase_readings')")


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


def parse_phrase_source_content(content: str) -> tuple[str, str] | None:
    if ":" in content:
        phrase_part, pinyin_part = content.split(":", 1)
        phrase = phrase_part.strip()
        marked_pinyin = pinyin_part.strip()
        if phrase and marked_pinyin:
            return phrase, marked_pinyin
        return None

    parts = [part.strip() for part in content.split("\t")]
    if len(parts) < 2:
        return None

    phrase = parts[0]
    marked_pinyin = parts[1]
    if not phrase or not marked_pinyin:
        return None
    return phrase, marked_pinyin


def load_char_candidates(primary: str, candidates_json: str) -> list[str]:
    try:
        parsed_candidates: Any = json.loads(candidates_json) if candidates_json else []
    except json.JSONDecodeError:
        parsed_candidates = []

    raw_candidates = cast(list[Any], parsed_candidates) if isinstance(parsed_candidates, list) else []
    candidates: list[str] = []
    seen: set[str] = set()

    if primary:
        seen.add(primary)
        candidates.append(primary)

    for item in raw_candidates:
        if not isinstance(item, str):
            continue
        candidate = item.strip()
        if not candidate or candidate in seen:
            continue
        seen.add(candidate)
        candidates.append(candidate)

    return candidates


def is_supported_char_reading(marked_pinyin: str) -> bool:
    return bool(NUMERIC_SYLLABLE_RE.match(marked_syllable_to_numeric(marked_pinyin)))


def import_char_source(conn: sqlite3.Connection, source_path: Path) -> int:
    source_name = make_source_name("char", source_path)
    conn.execute(
        "INSERT OR REPLACE INTO source_files (source_name, source_kind, source_path) VALUES (?, 'char', ?)",
        (source_name, str(source_path)),
    )

    inserted = 0
    with source_path.open("r", encoding="utf-8") as handle:
        reader = csv.reader(handle, delimiter="\t")
        for row in reader:
            raw_line = "\t".join(row)
            stripped = raw_line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            if row[0] == "codepoint" or len(row) < 4:
                continue

            codepoint = row[0].strip().upper()
            hanzi = row[1].strip()
            primary = row[2].strip()
            candidates_json = row[3].strip()
            pinyins = load_char_candidates(primary, candidates_json)
            if not codepoint or not hanzi or not pinyins:
                continue

            valid_pinyins = [marked_pinyin for marked_pinyin in pinyins if is_supported_char_reading(marked_pinyin)]

            for index, marked_pinyin in enumerate(valid_pinyins, start=1):
                conn.execute(
                    """
                    INSERT OR REPLACE INTO char_readings (
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
                        None,
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
            parsed = parse_phrase_source_content(content)
            if parsed is None:
                continue
            phrase, marked_pinyin = parsed

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


def sync_legacy_fallback_db(db_path: Path, legacy_db_path: Path = LEGACY_DB_PATH) -> bool:
    db_path = db_path.resolve()
    legacy_db_path = legacy_db_path.resolve()
    if db_path == legacy_db_path:
        return False

    legacy_db_path.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(db_path, legacy_db_path)
    return True


def main() -> None:
    args = parse_args()
    db_path = Path(args.db)
    schema_path = Path(args.schema)
    char_source = Path(args.char_source)
    phrase_source = Path(args.phrase_source)

    if not char_source.exists():
        raise FileNotFoundError(
            f"char source not found: {char_source}\n"
            "需先提供 unicode_hanzi.txt，再运行 source_pinyin 建库脚本。"
        )
    if not schema_path.exists():
        raise FileNotFoundError(f"schema file not found: {schema_path}")

    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(db_path)
    try:
        apply_schema(conn, schema_path)
        if not args.keep_existing:
            reset_import_tables(conn)

        char_rows = import_char_source(conn, char_source)
        phrase_rows = 0
        if phrase_source.exists():
            phrase_rows = import_phrase_source(conn, phrase_source)

        write_metadata(conn, "schema_version", "source_pinyin_v1")
        write_metadata(conn, "char_source", str(char_source))
        write_metadata(conn, "char_rows", str(char_rows))
        write_metadata(conn, "phrase_source", str(phrase_source) if phrase_source.exists() else "")
        write_metadata(conn, "phrase_rows", str(phrase_rows))
        conn.commit()
    finally:
        conn.close()

    synced_legacy = False
    if db_path.resolve() == DEFAULT_DB_PATH.resolve():
        synced_legacy = sync_legacy_fallback_db(db_path)

    print(f"built database: {db_path}")
    print(f"char_readings rows: {char_rows}")
    print(f"phrase_readings rows: {phrase_rows}")
    if synced_legacy:
        print(f"synced legacy fallback database: {LEGACY_DB_PATH}")


if __name__ == "__main__":
    main()
