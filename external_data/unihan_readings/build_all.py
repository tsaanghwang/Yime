#!/usr/bin/env python3
"""Run the full unihan_readings.db build pipeline."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent


def run(script_name: str, *args: str) -> None:
    script_path = SCRIPT_DIR / script_name
    cmd = [sys.executable, str(script_path), *args]
    print(f"\n{'=' * 60}")
    print(f"  执行: {script_name} {' '.join(args)}".rstrip())
    print(f"{'=' * 60}")
    result = subprocess.run(cmd, cwd=str(SCRIPT_DIR))
    if result.returncode != 0:
        raise SystemExit(result.returncode)


def main() -> int:
    run("build_hanzi.py")
    run("import_unihan_readings.py")
    run("import_hanzi_frequency.py")
    run("build_mandarin_readings_merged.py")
    run("sync_mandarin_readings_corrections.py", "--all")
    run("cleanup_unihan.py")
    run("export_hanzi_pinyin_txt.py")
    print(f"\n{'=' * 60}")
    print("  全部完成")
    print(f"{'=' * 60}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
