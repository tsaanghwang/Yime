from __future__ import annotations

import argparse
import csv

import sqlite3
from dataclasses import dataclass
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
DB_FILE = SCRIPT_DIR / "hanzi_pinyin.db"
# Default frequency files are stored in the workspace-level external_data directory
FREQ_DIR = Path(__file__).resolve().parents[2] / "external_data" / "char_freq"

DEFAULT_GLOB = "*.txt"
DEFAULT_EXPECTED_FILE_COUNT = 6


@dataclass
class FileStats:
    file_name: str
    parsed_rows: int = 0
    updated_rows: int = 0
    skipped_missing_hanzi: int = 0
    skipped_not_greater: int = 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Import char frequency files into hanzi_pinyin.db.hanzi.frequency using max(existing, incoming)."
    )
    parser.add_argument("--db", default=str(DB_FILE), help="Target hanzi_pinyin.db path")
    parser.add_argument("--freq-dir", default=str(FREQ_DIR), help="Directory containing char frequency CSV files")
    parser.add_argument("--glob", default=DEFAULT_GLOB, help="Glob for frequency files inside freq-dir")
    parser.add_argument(
        "--expected-file-count",
        type=int,
        default=DEFAULT_EXPECTED_FILE_COUNT,
        help="Minimum number of matching frequency files required before import",
    )
    parser.add_argument("--dry-run", action="store_true", help="Parse and compare without committing updates")
    return parser.parse_args()


def resolve_frequency_files(freq_dir: Path, glob_pattern: str, expected_file_count: int) -> list[Path]:
    if not freq_dir.exists():
        raise FileNotFoundError(
            f"frequency directory not found: {freq_dir}\n"
            "需先提供字频文件，再运行导入脚本。"
        )

    freq_files = sorted(path for path in freq_dir.glob(glob_pattern) if path.is_file())
    if not freq_files:
        raise FileNotFoundError(
            f"no frequency files matched {glob_pattern!r} in {freq_dir}\n"
            "需先提供字频文件，再运行导入脚本。"
        )

    if expected_file_count > 0 and len(freq_files) < expected_file_count:
        raise FileNotFoundError(
            f"found {len(freq_files)} frequency file(s) in {freq_dir}, expected at least {expected_file_count}\n"
            "需先提供至少一个字频文件，再运行导入脚本。"
        )

    return freq_files


def iter_frequency_rows(path: Path) -> list[tuple[str, int]]:
    rows: list[tuple[str, int]] = []
    with path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        required_columns = {"char", "freq"}
        if reader.fieldnames is None or not required_columns.issubset(set(reader.fieldnames)):
            raise ValueError(f"invalid frequency file columns in {path}: expected char,freq")

        for row in reader:
            hanzi = str(row.get("char") or "").strip()
            raw_freq = str(row.get("freq") or "").strip()
            if not hanzi or not raw_freq:
                continue
            rows.append((hanzi, int(raw_freq)))
    return rows


def build_hanzi_frequency_table(cur: sqlite3.Cursor) -> None:
    cur.execute("DROP TABLE IF EXISTS hanzi_frequency")
    cur.execute("""
        CREATE TABLE hanzi_frequency (
            codepoint   TEXT PRIMARY KEY REFERENCES hanzi(codepoint) ON DELETE RESTRICT,
            frequency   INTEGER NOT NULL DEFAULT 0
        )
    """)
    cur.execute("""
        INSERT INTO hanzi_frequency (codepoint, frequency)
        SELECT codepoint, 0 FROM hanzi
    """)
    cur.execute("CREATE INDEX IF NOT EXISTS idx_hanzi_freq ON hanzi_frequency(frequency DESC)")


def load_frequency_map(cur: sqlite3.Cursor) -> dict[str, int]:
    cur.execute(
        "SELECT h.hanzi, hf.frequency FROM hanzi_frequency hf JOIN hanzi h ON hf.codepoint = h.codepoint"
    )
    return {row[0]: int(row[1]) for row in cur.fetchall()}


def update_file_frequencies(cur: sqlite3.Cursor, path: Path, freq_map: dict[str, int]) -> FileStats:
    stats = FileStats(file_name=path.name)
    updates: list[tuple[int, str]] = []
    for hanzi, incoming_freq in iter_frequency_rows(path):
        stats.parsed_rows += 1
        current_freq = freq_map.get(hanzi)
        if current_freq is None:
            stats.skipped_missing_hanzi += 1
            continue

        if incoming_freq <= current_freq:
            stats.skipped_not_greater += 1
            continue

        updates.append((incoming_freq, hanzi))
        freq_map[hanzi] = incoming_freq
        stats.updated_rows += 1

    if updates:
        cur.executemany(
            "UPDATE hanzi_frequency SET frequency = ? WHERE codepoint = (SELECT codepoint FROM hanzi WHERE hanzi = ?)",
            updates,
        )
    return stats



def create_views(cur: sqlite3.Cursor) -> None:
    cur.execute("DROP VIEW IF EXISTS view_pinyin_by_frequency")
    cur.execute("""
        CREATE VIEW view_pinyin_by_frequency AS
        SELECT h.codepoint, h.hanzi, hr.common_reading AS pinyin, hr.readings AS pinyin_candidates, hf.frequency, h.block
        FROM hanzi h
        LEFT JOIN hanzi_pinyin hr ON h.codepoint = hr.codepoint
        LEFT JOIN hanzi_frequency hf ON h.codepoint = hf.codepoint
        ORDER BY hf.frequency DESC, h.codepoint ASC
    """)


def main() -> int:
    args = parse_args()
    db_path = Path(args.db)
    freq_dir = Path(args.freq_dir)


    if not db_path.exists():
        raise FileNotFoundError(f"database file not found: {db_path}")
    freq_files = resolve_frequency_files(freq_dir, args.glob, args.expected_file_count)

    print(f"frequency_files_found: {len(freq_files)}")
    print(f"frequency_dir: {freq_dir}")
    print(f"frequency_glob: {args.glob}")

    conn = sqlite3.connect(db_path)
    try:
        conn.execute("PRAGMA foreign_keys = ON")
        cur = conn.cursor()
        build_hanzi_frequency_table(cur)
        conn.commit()
        freq_map = load_frequency_map(cur)
        all_stats: list[FileStats] = []
        total_updated_rows = 0

        for path in freq_files:
            stats = update_file_frequencies(cur, path, freq_map)
            all_stats.append(stats)
            total_updated_rows += stats.updated_rows
            print(
                f"[{stats.file_name}] parsed={stats.parsed_rows} updated={stats.updated_rows} "
                f"skipped_not_greater={stats.skipped_not_greater} missing_hanzi={stats.skipped_missing_hanzi}"
            )

        if args.dry_run:
            conn.rollback()
            print("dry-run: rolled back all updates")
        else:
            conn.commit()
            create_views(cur)
            conn.commit()
            print(f"committed updates to: {db_path}")
            print("source_files_cleanup: skipped (files kept)")

        print(f"files_processed: {len(all_stats)}")
        print(f"total_updated_rows: {total_updated_rows}")
    finally:
        conn.close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
