from __future__ import annotations

import argparse
import json
import sqlite3
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
WORKSPACE_ROOT = SCRIPT_DIR.parent.parent
DEFAULT_DB_PATH = SCRIPT_DIR / "source_pinyin.db"
DEFAULT_CHAR_SOURCE = Path("C:/dev/pinyin-data/pinyin.txt")
DEFAULT_PHRASE_SOURCE = Path("C:/dev/pinyin-data/tools/phrase-pinyin-data/pinyin.txt")
DEFAULT_NORMALIZED_OUTPUT = WORKSPACE_ROOT / "pinyin" / "hanzi_pinyin" / "pinyin_normalized.json"
DEFAULT_YINJIE_OUTPUT = WORKSPACE_ROOT / "syllable_codec" / "yinjie_code.json"
DEFAULT_SUMMARY_OUTPUT = SCRIPT_DIR / "rebuild_summary.json"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Rebuild source pinyin assets: import -> validate -> export -> regenerate yinjie_code.json"
    )
    parser.add_argument("--db", default=str(DEFAULT_DB_PATH), help="SQLite database path")
    parser.add_argument("--char-source", default=str(DEFAULT_CHAR_SOURCE), help="Single-character source pinyin.txt")
    parser.add_argument("--phrase-source", default=str(DEFAULT_PHRASE_SOURCE), help="Optional phrase pinyin.txt")
    parser.add_argument(
        "--normalized-output",
        default=str(DEFAULT_NORMALIZED_OUTPUT),
        help="Output path for pinyin_normalized.json",
    )
    parser.add_argument(
        "--skip-yinjie",
        action="store_true",
        help="Skip regenerating yinjie_code.json after exporting pinyin_normalized.json",
    )
    parser.add_argument(
        "--summary-output",
        default=str(DEFAULT_SUMMARY_OUTPUT),
        help="Output path for rebuild summary JSON",
    )
    return parser.parse_args()


def run_step(step_name: str, command: list[str]) -> None:
    print(f"[{step_name}] {' '.join(command)}")
    subprocess.run(command, check=True, cwd=WORKSPACE_ROOT)


def load_json_count(path: Path) -> int:
    with path.open("r", encoding="utf-8") as handle:
        return len(json.load(handle))


def load_db_metadata(db_path: Path) -> dict[str, str]:
    conn = sqlite3.connect(db_path)
    try:
        return dict(conn.execute("SELECT key, value FROM metadata ORDER BY key"))
    finally:
        conn.close()


def build_summary(
    db_path: Path,
    normalized_output: Path,
    yinjie_output: Path,
    skip_yinjie: bool,
) -> dict[str, object]:
    metadata = load_db_metadata(db_path)
    summary: dict[str, object] = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "db_path": str(db_path),
        "normalized_output": str(normalized_output),
        "yinjie_output": str(yinjie_output),
        "skip_yinjie": skip_yinjie,
        "db_metadata": metadata,
        "counts": {
            "single_char_rows": int(metadata.get("single_char_rows", "0")),
            "phrase_rows": int(metadata.get("phrase_rows", "0")),
            "normalized_rows": load_json_count(normalized_output),
        },
    }
    if yinjie_output.exists():
        summary["counts"]["yinjie_rows"] = load_json_count(yinjie_output)
    else:
        summary["counts"]["yinjie_rows"] = 0
    return summary


def main() -> int:
    args = parse_args()
    db_path = Path(args.db)
    normalized_output = Path(args.normalized_output)
    summary_output = Path(args.summary_output)

    build_command = [
        sys.executable,
        str(SCRIPT_DIR / "build_source_pinyin_db.py"),
        "--db",
        str(db_path),
        "--char-source",
        args.char_source,
        "--phrase-source",
        args.phrase_source,
    ]
    run_step("import", build_command)

    validate_command = [
        sys.executable,
        str(SCRIPT_DIR / "validate_source_pinyin_db.py"),
        "--db",
        str(db_path),
    ]
    run_step("validate", validate_command)

    export_command = [
        sys.executable,
        str(SCRIPT_DIR / "export_pinyin_normalized.py"),
        "--db",
        str(db_path),
        "--output",
        str(normalized_output),
    ]
    run_step("export", export_command)

    if not args.skip_yinjie:
        yinjie_command = [
            sys.executable,
            str(WORKSPACE_ROOT / "syllable_codec" / "yinjie_encoder.py"),
        ]
        run_step("encode", yinjie_command)

    validate_yinyuan_command = [
        sys.executable,
        str(WORKSPACE_ROOT / "tools" / "validate_yinyuan_source_consistency.py"),
    ]
    run_step("validate-yinyuan", validate_yinyuan_command)

    summary_output.parent.mkdir(parents=True, exist_ok=True)
    summary = build_summary(
        db_path=db_path,
        normalized_output=normalized_output,
        yinjie_output=DEFAULT_YINJIE_OUTPUT,
        skip_yinjie=args.skip_yinjie,
    )
    summary_output.write_text(
        json.dumps(summary, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

    print(f"normalized_output: {normalized_output}")
    print(f"yinjie_output: {DEFAULT_YINJIE_OUTPUT}")
    print(f"summary_output: {summary_output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
