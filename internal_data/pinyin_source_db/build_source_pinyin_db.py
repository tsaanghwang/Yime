from __future__ import annotations

import argparse
import csv
import re
import shutil
import sqlite3
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
WORKSPACE_ROOT = SCRIPT_DIR.parent.parent
if str(WORKSPACE_ROOT) not in sys.path:
    sys.path.insert(0, str(WORKSPACE_ROOT))

from yime.utils.dictionary_pinyin_compliance import canonicalize_reading, load_policy, review_syllable
from yime.utils.marked_pinyin import marked_syllable_to_numeric as _marked_syllable_to_numeric
DEFAULT_DB_PATH = WORKSPACE_ROOT / ".generated" / "source_pinyin.db"
LEGACY_DB_PATH = WORKSPACE_ROOT / "internal_data" / "pinyin_source_db" / "source_pinyin.db"
DEFAULT_SCHEMA_PATH = SCRIPT_DIR / "schema.sql"
DEFAULT_CHAR_SOURCE = WORKSPACE_ROOT / "internal_data" / "hanzi_pinyin" / "pinyin.txt"
DEFAULT_PHRASE_SOURCE = WORKSPACE_ROOT / "internal_data" / "phrase_pinyin" / "phrase_pinyin.txt"
NUMERIC_SYLLABLE_RE = re.compile(r"^[a-zêü]+[1-5]$")

# 成音节辅音「儿化 r」在编码前归并为完整音节 er5（与 legacy merge_json 口径一致）。
SYLLABIC_ERHUA_MARKED_TO_NUMERIC = {
    "r": "er5",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build source_pinyin.db from internal_data hanzi/phrase pinyin TSV exports.",
    )
    parser.add_argument("--db", default=str(DEFAULT_DB_PATH), help="Output SQLite database path")
    parser.add_argument("--schema", default=str(DEFAULT_SCHEMA_PATH), help="Schema SQL file path")
    parser.add_argument(
        "--char-source",
        default=str(DEFAULT_CHAR_SOURCE),
        help="Hanzi pinyin TSV (internal_data/hanzi_pinyin/pinyin.txt)",
    )
    parser.add_argument(
        "--phrase-source",
        default=str(DEFAULT_PHRASE_SOURCE),
        help="Phrase pinyin TSV (internal_data/phrase_pinyin/phrase_pinyin.txt)",
    )
    parser.add_argument(
        "--keep-existing",
        action="store_true",
        help="Keep existing imported rows instead of replacing them",
    )
    return parser.parse_args()


def apply_schema(conn: sqlite3.Connection, schema_path: Path) -> None:
    conn.execute("DROP INDEX IF EXISTS idx_single_char_hanzi")
    conn.execute("DROP INDEX IF EXISTS idx_single_char_numeric")
    conn.execute("DROP INDEX IF EXISTS idx_single_char_codepoint")
    conn.execute("DROP TABLE IF EXISTS single_char_readings")
    conn.execute("DROP TABLE IF EXISTS char_readings")
    conn.execute("DROP TABLE IF EXISTS phrase_readings")
    conn.execute("DROP TABLE IF EXISTS source_files")
    conn.execute("DROP TABLE IF EXISTS metadata")
    conn.executescript(schema_path.read_text(encoding="utf-8"))


def reset_import_tables(conn: sqlite3.Connection) -> None:
    conn.execute("DELETE FROM char_readings")
    conn.execute("DELETE FROM phrase_readings")
    conn.execute("DELETE FROM source_files")
    conn.execute("DELETE FROM metadata")
    conn.execute("DELETE FROM sqlite_sequence WHERE name IN ('char_readings', 'phrase_readings')")


def marked_syllable_to_numeric(marked: str) -> str:
    if marked in SYLLABIC_ERHUA_MARKED_TO_NUMERIC:
        return SYLLABIC_ERHUA_MARKED_TO_NUMERIC[marked]
    return _marked_syllable_to_numeric(marked)


def marked_phrase_to_numeric(marked_phrase: str) -> str:
    return " ".join(marked_syllable_to_numeric(syllable) for syllable in marked_phrase.split())


def split_char_readings(readings: str) -> list[str]:
    seen: set[str] = set()
    ordered: list[str] = []
    for part in readings.split(","):
        candidate = part.strip()
        if candidate and candidate not in seen:
            seen.add(candidate)
            ordered.append(candidate)
    return ordered


def is_supported_char_reading(marked_pinyin: str) -> bool:
    return bool(NUMERIC_SYLLABLE_RE.match(marked_syllable_to_numeric(marked_pinyin)))


def register_source_file(conn: sqlite3.Connection, source_kind: str, source_path: Path) -> None:
    conn.execute(
        "INSERT OR REPLACE INTO source_files (source_kind, source_path) VALUES (?, ?)",
        (source_kind, str(source_path)),
    )


def import_char_source(conn: sqlite3.Connection, source_path: Path) -> int:
    register_source_file(conn, "char", source_path)
    policy = load_policy()

    inserted = 0
    with source_path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.reader(handle, delimiter="\t")
        for row in reader:
            if not row or row[0].startswith("#"):
                continue
            if row[0] == "codepoint" or len(row) < 4:
                continue

            codepoint = row[0].strip().upper()
            hanzi = row[1].strip()
            readings = row[3].strip()
            if not codepoint or not hanzi or not readings:
                continue

            candidates: list[str] = []
            for item in split_char_readings(readings):
                review = review_syllable(item, policy, codepoint=codepoint)
                if review.known_exclusion:
                    continue
                if not review.accepted:
                    raise ValueError(f"{codepoint} {hanzi} {item}: {review.reason}")
                candidates.append(review.canonical_marked)
            valid_pinyins = [p for p in candidates if is_supported_char_reading(p)]
            if not valid_pinyins:
                continue

            for index, marked_pinyin in enumerate(valid_pinyins, start=1):
                conn.execute(
                    """
                    INSERT OR REPLACE INTO char_readings (
                        codepoint,
                        hanzi,
                        marked_pinyin,
                        numeric_pinyin,
                        reading_rank,
                        is_primary
                    ) VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    (
                        codepoint,
                        hanzi,
                        marked_pinyin,
                        marked_syllable_to_numeric(marked_pinyin),
                        index,
                        1 if index == 1 else 0,
                    ),
                )
                inserted += 1

    return inserted


def import_phrase_source(conn: sqlite3.Connection, source_path: Path) -> int:
    register_source_file(conn, "phrase", source_path)
    policy = load_policy()

    inserted = 0
    with source_path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.reader(handle, delimiter="\t")
        for row in reader:
            if not row or row[0].startswith("#"):
                continue
            if row[0] == "phrase" or len(row) < 4:
                continue

            phrase = row[0].strip()
            try:
                phrase_len = int(row[1].strip())
            except ValueError:
                phrase_len = len(phrase)
            readings = row[3].strip()
            if not phrase or not readings:
                continue

            reading_list: list[str] = []
            seen: set[str] = set()
            for part in readings.split("|"):
                candidate = part.strip()
                if candidate:
                    candidate, _ = canonicalize_reading(candidate, policy)
                if candidate and candidate not in seen:
                    seen.add(candidate)
                    reading_list.append(candidate)

            for index, marked_pinyin in enumerate(reading_list, start=1):
                conn.execute(
                    """
                    INSERT OR REPLACE INTO phrase_readings (
                        phrase,
                        phrase_len,
                        marked_pinyin,
                        numeric_pinyin,
                        reading_rank
                    ) VALUES (?, ?, ?, ?, ?)
                    """,
                    (
                        phrase,
                        phrase_len,
                        marked_pinyin,
                        marked_phrase_to_numeric(marked_pinyin),
                        index,
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
    raise SystemExit(
        "retired: build the canonical source with tools/build_lexicon_source_bundle.py; "
        "legacy source_pinyin.db is not a production input"
    )


def _legacy_main() -> None:
    """Archived implementation retained only for historical format recovery."""
    args = parse_args()
    db_path = Path(args.db)
    schema_path = Path(args.schema)
    char_source = Path(args.char_source)
    phrase_source = Path(args.phrase_source)

    if not char_source.exists():
        raise FileNotFoundError(
            f"char source not found: {char_source}\n"
            "请先运行 internal_data/hanzi_pinyin/build_valid_pinyin.py 生成 pinyin.txt。"
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
        else:
            print(f"phrase source not found, skipping: {phrase_source}")

        write_metadata(conn, "schema_version", "source_pinyin_v2")
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
