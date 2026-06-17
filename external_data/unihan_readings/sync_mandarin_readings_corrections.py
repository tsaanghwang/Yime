#!/usr/bin/env python3
"""Import and apply mandarin_readings_corrections."""

from __future__ import annotations

import argparse
import sqlite3
import sys
from pathlib import Path

from mandarin_readings_corrections_io import (
    DEFAULT_CORRECTIONS_FILE,
    DEFAULT_DB_PATH,
    apply_approved_corrections,
    create_correction_views,
    ensure_corrections_table,
    export_corrections_file,
    import_corrections_file,
)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="同步 mandarin_readings_corrections 表与 txt 文件。",
    )
    parser.add_argument(
        "--db",
        type=Path,
        default=DEFAULT_DB_PATH,
        help=f"数据库路径 (默认: {DEFAULT_DB_PATH.name})",
    )
    parser.add_argument(
        "--corrections-file",
        type=Path,
        default=DEFAULT_CORRECTIONS_FILE,
        help=f"校正 txt 路径 (默认: {DEFAULT_CORRECTIONS_FILE.name})",
    )
    parser.add_argument("--export", action="store_true", help="导出表到 txt")
    parser.add_argument("--import", dest="do_import", action="store_true", help="从 txt 导入表")
    parser.add_argument("--apply", action="store_true", help="将 approved 校正应用到 merged 表")
    parser.add_argument(
        "--all",
        action="store_true",
        help="执行 import → apply（构建流水线默认）",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    if not args.db.exists():
        raise FileNotFoundError(f"未找到数据库: {args.db}")
    if args.all:
        args.do_import = True
        args.apply = True
    if not any((args.export, args.do_import, args.apply)):
        args.all = True
        args.do_import = True
        args.apply = True

    conn = sqlite3.connect(args.db)
    try:
        conn.execute("PRAGMA foreign_keys = ON")
        ensure_corrections_table(conn.cursor())

        if args.export:
            exported = export_corrections_file(conn, args.corrections_file)
            print(f"export: {exported:,} 条 -> {args.corrections_file}")

        if args.do_import:
            if not args.corrections_file.exists():
                raise FileNotFoundError(
                    f"校正文件不存在: {args.corrections_file}"
                )
            imported = import_corrections_file(conn, args.corrections_file)
            print(f"import: {imported:,} 条 <- {args.corrections_file}")

        if args.apply:
            applied = apply_approved_corrections(conn)
            print(f"apply approved: {applied:,} 条 -> mandarin_readings_merged")

        create_correction_views(conn.cursor())
        conn.commit()

        cur = conn.cursor()
        counts = cur.execute(
            "SELECT review_status, COUNT(*) FROM mandarin_readings_corrections "
            "GROUP BY review_status ORDER BY review_status"
        ).fetchall()
        for status, count in counts:
            print(f"  corrections[{status}]: {count:,}")
        print(f"数据库: {args.db}")
    finally:
        conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
