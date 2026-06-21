from __future__ import annotations

import argparse
import csv
import sqlite3
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

try:
    from yime.utils.backup import create_timestamped_backup
    from yime.utils.char_frequency_policy import (
        BCC_SOURCE,
        DEFAULT_BCC_CHAR_FREQ_PATH,
        DEFAULT_UNIHAN_READINGS_DB,
        load_bcc_char_frequency_map,
        load_unihan_columns_by_hanzi,
        purge_legacy_frequency_metadata,
        resolve_char_frequencies_for_hanzi,
        resolve_phrase_frequencies_for_inventory,
    )
except ImportError:
    from .backup import create_timestamped_backup
    from .char_frequency_policy import (
        BCC_SOURCE,
        DEFAULT_BCC_CHAR_FREQ_PATH,
        DEFAULT_UNIHAN_READINGS_DB,
        load_bcc_char_frequency_map,
        load_unihan_columns_by_hanzi,
        purge_legacy_frequency_metadata,
        resolve_char_frequencies_for_hanzi,
        resolve_phrase_frequencies_for_inventory,
    )


PACKAGE_ROOT = Path(__file__).resolve().parents[1]
PROJECT_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DB_PATH = PACKAGE_ROOT / "pinyin_hanzi.db"
DEFAULT_PHRASE_FREQ_PATH = (
    PROJECT_ROOT / "external_data" / "word_freq" / "merged_word_freq.txt"
)
DEFAULT_CHAR_FREQ_PATH = DEFAULT_BCC_CHAR_FREQ_PATH
DEFAULT_RUNTIME_EXPORT = PACKAGE_ROOT / "export_runtime_candidates_json.py"
DEFAULT_BACKUP_DIR = PACKAGE_ROOT / "backup"
DEFAULT_BACKUP_RETAIN_COUNT = 20
DEFAULT_SOURCE_TAG = BCC_SOURCE
PROTOTYPE_SCHEMA_PATH = PACKAGE_ROOT / "create_prototype_schema_additions.sql"

BCC_CITATION = (
    "荀恩东, 饶高琦, 肖晓悦, 臧娇娇. 大数据背景下 BCC 语料库的研制[J]. "
    "语料库语言学, 2016(1)."
)

# Backward-compatible alias for tests and shims (defined via import above).

@dataclass(frozen=True)
class ImportStats:
    parsed_phrase_rows: int
    parsed_char_rows: int
    matched_phrase_rows: int
    matched_char_rows: int
    synthetic_char_rows: int
    unmatched_phrase_rows: int
    unmatched_char_rows: int
    removed_metadata_keys: tuple[str, ...] = ()
    migrated_phrase_frequency_column: bool = False
    materialized_runtime_rows: int = 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Import Beijing Language University BCC merged word/char frequencies "
            "into the local Yime runtime database. Only entries already present in "
            "phrase_inventory / char_inventory receive frequencies."
        )
    )
    parser.add_argument("--db", default=str(DEFAULT_DB_PATH), help="Yime SQLite database path")
    parser.add_argument(
        "--phrase-freq",
        default=str(DEFAULT_PHRASE_FREQ_PATH),
        help="Merged multi-character word frequency CSV (word,freq)",
    )
    parser.add_argument(
        "--char-freq",
        default=str(DEFAULT_CHAR_FREQ_PATH),
        help="Merged single-character frequency CSV (char,freq)",
    )
    parser.add_argument(
        "--source-tag",
        default=DEFAULT_SOURCE_TAG,
        help="frequency_source tag written to char_inventory",
    )
    parser.add_argument(
        "--unihan-db",
        default=str(DEFAULT_UNIHAN_READINGS_DB),
        help="Unihan readings database used for synthetic char-frequency fallback",
    )
    parser.add_argument(
        "--skip-char-freq",
        action="store_true",
        help="Skip single-character frequency import even if the file exists",
    )
    parser.add_argument(
        "--skip-runtime-export",
        action="store_true",
        help="Do not refresh runtime_candidates JSON after writing the database",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Only report match counts; do not write the database",
    )
    parser.add_argument(
        "--no-backup",
        action="store_true",
        help="Do not create a database backup before writing",
    )
    parser.add_argument(
        "--backup-retain",
        type=int,
        default=DEFAULT_BACKUP_RETAIN_COUNT,
        help="Retain this many recent blcu_word_freq backups; 0 disables pruning",
    )
    return parser.parse_args()


def load_word_frequency_csv(path: Path, *, min_len: int, max_len: int | None = None) -> tuple[dict[str, int], int]:
    if not path.exists():
        raise FileNotFoundError(f"frequency file not found: {path}")

    by_key: dict[str, int] = {}
    parsed_rows = 0
    with path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames is None:
            return {}, 0

        fieldnames = [name.strip() for name in reader.fieldnames]
        if len(fieldnames) < 2:
            raise ValueError(f"expected at least two CSV columns in {path}")

        key_field = fieldnames[0]
        freq_field = fieldnames[1]
        for row in reader:
            key = str(row.get(key_field) or "").strip()
            freq_text = str(row.get(freq_field) or "").strip()
            if not key or not freq_text:
                continue
            if len(key) < min_len:
                continue
            if max_len is not None and len(key) > max_len:
                continue
            try:
                freq = int(freq_text)
            except ValueError:
                continue
            parsed_rows += 1
            previous = by_key.get(key)
            if previous is None or freq > previous:
                by_key[key] = freq

    return by_key, parsed_rows


def load_phrase_frequency_map(path: Path) -> tuple[dict[str, int], int]:
    by_phrase, parsed_rows = load_word_frequency_csv(path, min_len=2)
    return by_phrase, parsed_rows


def load_char_frequency_map(path: Path) -> tuple[dict[str, int], int]:
    return load_bcc_char_frequency_map(path)


def purge_obsolete_frequency_metadata(conn: sqlite3.Connection) -> list[str]:
    return purge_legacy_frequency_metadata(conn)


def phrase_frequency_column_type(conn: sqlite3.Connection) -> str:
    if not _table_exists(conn, "phrase_inventory"):
        return ""
    row = conn.execute("PRAGMA table_info(phrase_inventory)").fetchall()
    for _cid, name, declared_type, *_rest in row:
        if name == "phrase_frequency":
            return str(declared_type or "").strip().upper()
    return ""


def _table_exists(conn: sqlite3.Connection, table_name: str) -> bool:
    row = conn.execute(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
        (table_name,),
    ).fetchone()
    return row is not None


def _ensure_phrase_inventory_indexes(conn: sqlite3.Connection) -> None:
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_phrase_inventory_phrase ON phrase_inventory(phrase)"
    )
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_phrase_inventory_yime_code "
        "ON phrase_inventory(yime_code)"
    )


def _recover_pending_phrase_inventory(conn: sqlite3.Connection) -> bool:
    if not _table_exists(conn, "phrase_inventory__bcc_freq_migrate"):
        return False
    if _table_exists(conn, "phrase_inventory"):
        conn.execute("DROP TABLE phrase_inventory__bcc_freq_migrate")
        return False
    conn.execute(
        "ALTER TABLE phrase_inventory__bcc_freq_migrate RENAME TO phrase_inventory"
    )
    _ensure_phrase_inventory_indexes(conn)
    return True


def migrate_phrase_frequency_column_to_integer(conn: sqlite3.Connection) -> bool:
    if _recover_pending_phrase_inventory(conn):
        return True
    if not _table_exists(conn, "phrase_inventory"):
        return False
    if phrase_frequency_column_type(conn) == "INTEGER":
        return False

    source_columns = {
        row[1]
        for row in conn.execute("PRAGMA table_info(phrase_inventory)").fetchall()
    }
    if "phrase_frequency" not in source_columns:
        return False

    target_columns = (
        "id",
        "phrase",
        "yime_code",
        "phrase_frequency",
        "phrase_length",
        "is_common_phrase",
        "legacy_phrase_id",
        "updated_at",
    )

    def select_expr(column: str) -> str:
        if column == "phrase_frequency":
            return "CAST(phrase_frequency AS INTEGER)"
        if column in source_columns:
            return column
        if column == "phrase_length":
            return "LENGTH(phrase)"
        if column == "is_common_phrase":
            return "1"
        if column == "updated_at":
            if column in source_columns:
                return "COALESCE(updated_at, CURRENT_TIMESTAMP)"
            return "CURRENT_TIMESTAMP"
        return "NULL"

    insert_columns = ", ".join(target_columns)
    select_columns = ", ".join(select_expr(column) for column in target_columns)
    conn.execute("DROP VIEW IF EXISTS runtime_candidates")
    conn.execute("DROP VIEW IF EXISTS phrase_lexicon_view")
    conn.executescript(
        f"""
        PRAGMA foreign_keys = OFF;
        CREATE TABLE phrase_inventory__bcc_freq_migrate (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            phrase TEXT NOT NULL UNIQUE,
            yime_code TEXT,
            phrase_frequency INTEGER,
            phrase_length INTEGER NOT NULL,
            is_common_phrase INTEGER NOT NULL DEFAULT 1 CHECK (is_common_phrase IN (0, 1)),
            legacy_phrase_id INTEGER,
            updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        );
        INSERT INTO phrase_inventory__bcc_freq_migrate ({insert_columns})
        SELECT {select_columns}
        FROM phrase_inventory;
        DROP TABLE phrase_inventory;
        ALTER TABLE phrase_inventory__bcc_freq_migrate RENAME TO phrase_inventory;
        PRAGMA foreign_keys = ON;
        """
    )
    _ensure_phrase_inventory_indexes(conn)
    return True


def rebuild_materialized_runtime_candidates(conn: sqlite3.Connection) -> int:
    conn.execute("DELETE FROM runtime_candidates_materialized")
    conn.execute(
        """
        INSERT INTO runtime_candidates_materialized (
            entry_type,
            entry_id,
            text,
            pinyin_tone,
            yime_code,
            sort_weight,
            is_common,
            text_length,
            updated_at
        )
        SELECT
            entry_type,
            entry_id,
            text,
            pinyin_tone,
            yime_code,
            sort_weight,
            is_common,
            text_length,
            updated_at
        FROM runtime_candidates
        WHERE yime_code IS NOT NULL
          AND TRIM(yime_code) <> ''
        """
    )
    row = conn.execute("SELECT COUNT(*) FROM runtime_candidates_materialized").fetchone()
    return int(row[0] or 0)


def backup_database(db_path: Path, *, retain_count: int) -> tuple[Path, list[Path]]:
    return create_timestamped_backup(
        db_path,
        backup_dir=DEFAULT_BACKUP_DIR,
        backup_tag="blcu_word_freq",
        retain_count=retain_count,
    )


def apply_frequency_updates(
    db_path: Path,
    *,
    phrase_frequency_by_text: dict[str, int],
    char_frequency_by_char: dict[str, int],
    source_tag: str,
    phrase_source: str,
    char_source: str,
    unihan_db_path: Path = DEFAULT_UNIHAN_READINGS_DB,
    dry_run: bool,
) -> ImportStats:
    conn = sqlite3.connect(db_path)
    try:
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()

        phrase_rows = cursor.execute(
            "SELECT id, phrase FROM phrase_inventory WHERE LENGTH(phrase) > 1"
        ).fetchall()
        phrase_texts = [str(row[1]) for row in phrase_rows if str(row[1] or "")]
        resolved_phrase_frequencies = resolve_phrase_frequencies_for_inventory(
            phrase_texts,
            bcc_by_phrase=phrase_frequency_by_text,
        )
        char_rows = cursor.execute("SELECT hanzi FROM char_inventory").fetchall()
        existing_hanzi = [str(row[0]) for row in char_rows if str(row[0] or "")]
        existing_hanzi_set = set(existing_hanzi)

        matched_phrase_rows = sum(
            1 for row in phrase_rows if str(row[1]) in phrase_frequency_by_text
        )
        matched_char_rows = sum(
            1 for hanzi in existing_hanzi_set if hanzi in char_frequency_by_char
        )
        unihan_by_hanzi = load_unihan_columns_by_hanzi(unihan_db_path)
        resolved_char_frequencies = resolve_char_frequencies_for_hanzi(
            existing_hanzi,
            bcc_by_hanzi=char_frequency_by_char,
            unihan_by_hanzi=unihan_by_hanzi,
            bcc_source=source_tag,
        )
        synthetic_char_rows = sum(
            1
            for item in resolved_char_frequencies.values()
            if item.source != source_tag and item.frequency > 0
        )

        if dry_run:
            return ImportStats(
                parsed_phrase_rows=len(phrase_frequency_by_text),
                parsed_char_rows=len(char_frequency_by_char),
                matched_phrase_rows=matched_phrase_rows,
                matched_char_rows=matched_char_rows,
                synthetic_char_rows=synthetic_char_rows,
                unmatched_phrase_rows=len(phrase_rows) - matched_phrase_rows,
                unmatched_char_rows=len(char_rows) - matched_char_rows,
            )

        cursor.execute("BEGIN")
        migrated_phrase_column = migrate_phrase_frequency_column_to_integer(conn)
        removed_metadata_keys = purge_obsolete_frequency_metadata(conn)
        cursor.execute(
            "UPDATE char_pinyin_map SET reading_weight = NULL, updated_at = CURRENT_TIMESTAMP"
        )
        cursor.execute(
            """
            UPDATE char_inventory
            SET char_frequency_abs = NULL,
                frequency_source = NULL,
                updated_at = CURRENT_TIMESTAMP
            """
        )
        cursor.executemany(
            """
            UPDATE phrase_inventory
            SET phrase_frequency = ?,
                updated_at = CURRENT_TIMESTAMP
            WHERE id = ?
            """,
            [
                (resolved_phrase_frequencies[str(row[1])], int(row[0]))
                for row in phrase_rows
            ],
        )

        cursor.executemany(
            """
            UPDATE char_inventory
            SET char_frequency_abs = ?,
                frequency_source = ?,
                updated_at = CURRENT_TIMESTAMP
            WHERE hanzi = ?
            """,
            [
                (item.frequency, item.source, hanzi)
                for hanzi, item in resolved_char_frequencies.items()
            ],
        )

        cursor.executemany(
            """
            INSERT OR REPLACE INTO prototype_metadata (key, value, note, updated_at)
            VALUES (?, ?, ?, CURRENT_TIMESTAMP)
            """,
            [
                (
                    "prototype_blcu_word_freq_phrase_source",
                    phrase_source,
                    "BCC merged multi-character word frequency source",
                ),
                (
                    "prototype_blcu_word_freq_char_source",
                    char_source,
                    "BCC merged single-character frequency source",
                ),
                (
                    "prototype_blcu_word_freq_phrase_matched",
                    str(matched_phrase_rows),
                    "phrase_inventory rows updated from BCC merged word frequency",
                ),
                (
                    "prototype_blcu_word_freq_char_matched",
                    str(matched_char_rows),
                    "char_inventory rows with BCC merged char frequency",
                ),
                (
                    "prototype_blcu_word_freq_char_synthetic",
                    str(synthetic_char_rows),
                    "char_inventory rows assigned synthetic Unihan fallback frequency",
                ),
                (
                    "prototype_blcu_word_freq_citation",
                    BCC_CITATION,
                    "Required citation when using BCC frequency data",
                ),
            ],
        )

        conn.commit()
        return ImportStats(
            parsed_phrase_rows=len(phrase_frequency_by_text),
            parsed_char_rows=len(char_frequency_by_char),
            matched_phrase_rows=matched_phrase_rows,
            matched_char_rows=matched_char_rows,
            synthetic_char_rows=synthetic_char_rows,
            unmatched_phrase_rows=len(phrase_rows) - matched_phrase_rows,
            unmatched_char_rows=len(char_rows) - matched_char_rows,
            removed_metadata_keys=tuple(removed_metadata_keys),
            migrated_phrase_frequency_column=migrated_phrase_column,
        )
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def refresh_prototype_schema_views(db_path: Path) -> int:
    conn = sqlite3.connect(db_path)
    try:
        conn.executescript(PROTOTYPE_SCHEMA_PATH.read_text(encoding="utf-8"))
        materialized_rows = rebuild_materialized_runtime_candidates(conn)
        conn.commit()
        return materialized_rows
    finally:
        conn.close()


def refresh_runtime_export(db_path: Path) -> None:
    subprocess.run(
        [
            sys.executable,
            str(DEFAULT_RUNTIME_EXPORT),
            "--db",
            str(db_path),
        ],
        check=True,
    )


def main() -> int:
    args = parse_args()
    db_path = Path(args.db).resolve()
    phrase_freq_path = Path(args.phrase_freq).resolve()
    char_freq_path = Path(args.char_freq).resolve()

    if not db_path.exists():
        print(f"database not found: {db_path}", file=sys.stderr)
        return 1
    if not phrase_freq_path.exists():
        print(f"phrase frequency file not found: {phrase_freq_path}", file=sys.stderr)
        return 1

    phrase_frequency_by_text, parsed_phrase_rows = load_phrase_frequency_map(
        phrase_freq_path
    )
    char_frequency_by_char: dict[str, int] = {}
    parsed_char_rows = 0
    if not args.skip_char_freq and char_freq_path.exists():
        char_frequency_by_char, parsed_char_rows = load_char_frequency_map(char_freq_path)
    elif not args.skip_char_freq:
        print(f"optional char frequency file missing, skipping chars: {char_freq_path}")

    if not args.dry_run and not args.no_backup:
        backup_path, removed_backups = backup_database(
            db_path,
            retain_count=args.backup_retain,
        )
        print(f"database backup created: {backup_path}")
        if removed_backups:
            print(
                f"removed {len(removed_backups)} old backups; "
                f"retaining the latest {args.backup_retain}"
            )

    stats = apply_frequency_updates(
        db_path,
        phrase_frequency_by_text=phrase_frequency_by_text,
        char_frequency_by_char=char_frequency_by_char,
        source_tag=args.source_tag,
        phrase_source=str(phrase_freq_path),
        char_source=str(char_freq_path if char_freq_path.exists() else ""),
        unihan_db_path=Path(args.unihan_db).resolve(),
        dry_run=args.dry_run,
    )

    print(f"parsed phrase frequency keys: {parsed_phrase_rows}")
    print(f"parsed char frequency keys: {parsed_char_rows}")
    print(f"matched phrase_inventory rows: {stats.matched_phrase_rows}")
    print(f"matched char_inventory rows (BCC): {stats.matched_char_rows}")
    print(f"synthetic char_inventory rows: {stats.synthetic_char_rows}")
    print(f"phrase_inventory without BCC freq: {stats.unmatched_phrase_rows}")
    print(f"char_inventory without BCC freq: {stats.unmatched_char_rows}")
    print(f"BCC citation: {BCC_CITATION}")
    print(
        "note: phrase frequencies use BCC when present, otherwise lexicon default 1; "
        "char frequencies use BCC when present otherwise Unihan synthetic ladder (5..1, else 0)."
    )

    if args.dry_run:
        print("dry-run mode: database not modified")
        return 0

    if stats.removed_metadata_keys:
        print(
            "removed obsolete frequency metadata keys: "
            + ", ".join(stats.removed_metadata_keys)
        )

    if stats.migrated_phrase_frequency_column:
        print("migrated phrase_inventory.phrase_frequency column to INTEGER")

    if not args.skip_runtime_export:
        materialized_rows = refresh_prototype_schema_views(db_path)
        refresh_runtime_export(db_path)
        print(
            "refreshed prototype views, materialized runtime candidates "
            f"({materialized_rows} rows), and runtime_candidates export JSON"
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
