from __future__ import annotations

import argparse
import csv
import shutil
import sqlite3
from dataclasses import dataclass
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
DB_FILE = SCRIPT_DIR / "unicode_hanzi.db"
FREQ_DIR = SCRIPT_DIR / "char_freq"
ARCHIVE_DIR = Path("C:/dev/Word-frequency/char_freq")
DEFAULT_GLOB = "*.txt"
DEFAULT_EXPECTED_FILE_COUNT = 1


@dataclass
class FileStats:
    file_name: str
    parsed_rows: int = 0
    updated_rows: int = 0
    skipped_missing_hanzi: int = 0
    skipped_not_greater: int = 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Import char frequency files into unicode_hanzi.db.hanzi.frequency using max(existing, incoming)."
    )
    parser.add_argument("--db", default=str(DB_FILE), help="Target unicode_hanzi.db path")
    parser.add_argument("--freq-dir", default=str(FREQ_DIR), help="Directory containing char frequency CSV files")
    parser.add_argument(
        "--archive-dir",
        default=str(ARCHIVE_DIR),
        help="Directory to move processed frequency files into after a successful import",
    )
    parser.add_argument("--glob", default=DEFAULT_GLOB, help="Glob for frequency files inside freq-dir")
    parser.add_argument(
        "--expected-file-count",
        type=int,
        default=DEFAULT_EXPECTED_FILE_COUNT,
        help="Minimum number of matching frequency files required before import",
    )
    parser.add_argument(
        "--keep-source-files",
        action="store_true",
        help="Keep matched frequency files after a successful import",
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


def load_current_frequency(cur: sqlite3.Cursor, hanzi: str) -> int | None:
    row = cur.execute("SELECT frequency FROM hanzi WHERE hanzi = ?", (hanzi,)).fetchone()
    if row is None:
        return None
    value = row[0]
    return None if value is None else int(value)


def update_file_frequencies(cur: sqlite3.Cursor, path: Path) -> FileStats:
    stats = FileStats(file_name=path.name)
    for hanzi, incoming_freq in iter_frequency_rows(path):
        stats.parsed_rows += 1
        current_freq = load_current_frequency(cur, hanzi)
        if current_freq is None:
            exists = cur.execute("SELECT 1 FROM hanzi WHERE hanzi = ?", (hanzi,)).fetchone()
            if exists is None:
                stats.skipped_missing_hanzi += 1
                continue
            current_freq = 0

        if incoming_freq <= current_freq:
            stats.skipped_not_greater += 1
            continue

        cur.execute(
            "UPDATE hanzi SET frequency = ? WHERE hanzi = ?",
            (incoming_freq, hanzi),
        )
        stats.updated_rows += 1
    return stats


def move_source_files(paths: list[Path], archive_dir: Path) -> int:
    archive_dir.mkdir(parents=True, exist_ok=True)
    moved = 0
    for path in paths:
        target_path = archive_dir / path.name
        if target_path.exists():
            target_path.unlink()
        shutil.move(str(path), str(target_path))
        moved += 1
    return moved


def main() -> int:
    args = parse_args()
    db_path = Path(args.db)
    freq_dir = Path(args.freq_dir)
    archive_dir = Path(args.archive_dir)

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
        all_stats: list[FileStats] = []
        total_updated_rows = 0

        for path in freq_files:
            stats = update_file_frequencies(cur, path)
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
            print(f"committed updates to: {db_path}")
            if args.keep_source_files:
                print("source_files_cleanup: skipped (--keep-source-files)")
            else:
                moved_source_files = move_source_files(freq_files, archive_dir)
                print(f"source_files_moved: {moved_source_files}")
                print(f"source_files_archive_dir: {archive_dir}")

        print(f"files_processed: {len(all_stats)}")
        print(f"total_updated_rows: {total_updated_rows}")
    finally:
        conn.close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
