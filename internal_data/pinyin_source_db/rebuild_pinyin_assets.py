from __future__ import annotations

import argparse
import json
import shutil
import sqlite3
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

from build_source_pinyin_db import DEFAULT_CHAR_SOURCE, DEFAULT_DB_PATH, DEFAULT_PHRASE_SOURCE


SCRIPT_DIR = Path(__file__).resolve().parent
WORKSPACE_ROOT = SCRIPT_DIR.parent.parent
DEFAULT_NORMALIZED_OUTPUT = SCRIPT_DIR / "lexicon_exports" / "pinyin_normalized.json"
DEFAULT_RUNTIME_NORMALIZED_OUTPUT = WORKSPACE_ROOT / "yime" / "pinyin_normalized.json"
DEFAULT_YINJIE_OUTPUT = WORKSPACE_ROOT / "syllable" / "codec" / "yinjie_code.json"
DEFAULT_SUMMARY_OUTPUT = SCRIPT_DIR / "rebuild_summary.json"


class Args(argparse.Namespace):
    db: str
    char_source: str
    phrase_source: str
    normalized_output: str
    runtime_normalized_output: str
    skip_runtime_normalized_sync: bool
    apply_codebook: bool
    skip_yinjie: bool
    summary_output: str


def parse_args() -> Args:
    parser = argparse.ArgumentParser(
        description=(
            "Rebuild source pinyin assets: import -> validate -> export pinyin_normalized.json. "
            "By default the syllable codebook is left unchanged; use --apply-codebook for phase 2."
        )
    )
    parser.add_argument("--db", default=str(DEFAULT_DB_PATH), help="SQLite database path")
    parser.add_argument(
        "--char-source",
        default=str(DEFAULT_CHAR_SOURCE),
        help="Hanzi pinyin TSV (default: internal_data/hanzi_pinyin/pinyin.txt)",
    )
    parser.add_argument(
        "--phrase-source",
        default=str(DEFAULT_PHRASE_SOURCE),
        help="Phrase pinyin TSV (default: internal_data/phrase_pinyin/phrase_pinyin.txt)",
    )
    parser.add_argument(
        "--normalized-output",
        default=str(DEFAULT_NORMALIZED_OUTPUT),
        help="Output path for pinyin_normalized.json",
    )
    parser.add_argument(
        "--runtime-normalized-output",
        default=str(DEFAULT_RUNTIME_NORMALIZED_OUTPUT),
        help="Copy export to this runtime path (default: yime/pinyin_normalized.json for IME/static decoder)",
    )
    parser.add_argument(
        "--skip-runtime-normalized-sync",
        action="store_true",
        help="Do not copy lexicon export to the runtime pinyin_normalized.json path.",
    )
    parser.add_argument(
        "--apply-codebook",
        action="store_true",
        help=(
            "Phase 2: regenerate syllable/codec/yinjie_code.json via tools/rebuild_encoding_assets.py "
            "after export and validation. Default leaves the checked-in codebook untouched."
        ),
    )
    parser.add_argument(
        "--skip-yinjie",
        action="store_true",
        help=argparse.SUPPRESS,
    )
    parser.add_argument(
        "--summary-output",
        default=str(DEFAULT_SUMMARY_OUTPUT),
        help="Output path for rebuild summary JSON",
    )
    return parser.parse_args(namespace=Args())


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


def sync_runtime_normalized_export(source: Path, destination: Path) -> None:
    if not source.is_file():
        raise FileNotFoundError(f"normalized export not found: {source}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)


def build_summary(
    db_path: Path,
    normalized_output: Path,
    runtime_normalized_output: Path | None,
    yinjie_output: Path,
    apply_codebook: bool,
) -> dict[str, object]:
    metadata = load_db_metadata(db_path)
    counts: dict[str, int] = {
        "char_rows": int(metadata.get("char_rows", metadata.get("single_char_rows", "0"))),
        "phrase_rows": int(metadata.get("phrase_rows", "0")),
        "normalized_rows": load_json_count(normalized_output),
    }
    summary: dict[str, object] = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "db_path": str(db_path),
        "normalized_output": str(normalized_output),
        "runtime_normalized_output": str(runtime_normalized_output) if runtime_normalized_output else None,
        "yinjie_output": str(yinjie_output),
        "apply_codebook": apply_codebook,
        "db_metadata": metadata,
        "counts": counts,
    }
    if yinjie_output.exists():
        counts["yinjie_rows"] = load_json_count(yinjie_output)
    else:
        counts["yinjie_rows"] = 0
    return summary


def main() -> int:
    args = parse_args()
    db_path = Path(args.db)
    normalized_output = Path(args.normalized_output)
    runtime_normalized_output = (
        None if args.skip_runtime_normalized_sync else Path(args.runtime_normalized_output)
    )
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

    inventory_command = [
        sys.executable,
        str(WORKSPACE_ROOT / "tools" / "refresh_materialized_syllable_inventory.py"),
        "--db-path",
        str(db_path),
    ]
    run_step("syllable-inventory", inventory_command)

    export_command = [
        sys.executable,
        str(SCRIPT_DIR / "export_pinyin_normalized.py"),
        "--db",
        str(db_path),
        "--output",
        str(normalized_output),
    ]
    run_step("export", export_command)

    if runtime_normalized_output is not None:
        sync_runtime_normalized_export(normalized_output, runtime_normalized_output)
        print(f"runtime_normalized_output: {runtime_normalized_output}")

    apply_codebook = args.apply_codebook and not args.skip_yinjie
    if apply_codebook:
        codebook_command = [
            sys.executable,
            str(WORKSPACE_ROOT / "tools" / "rebuild_encoding_assets.py"),
        ]
        run_step("apply-codebook", codebook_command)

    validate_yinyuan_command = [
        sys.executable,
        str(WORKSPACE_ROOT / "tools" / "validate_yinyuan_source_consistency.py"),
    ]
    run_step("validate-yinyuan", validate_yinyuan_command)

    summary_output.parent.mkdir(parents=True, exist_ok=True)
    summary = build_summary(
        db_path=db_path,
        normalized_output=normalized_output,
        runtime_normalized_output=runtime_normalized_output,
        yinjie_output=DEFAULT_YINJIE_OUTPUT,
        apply_codebook=apply_codebook,
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
