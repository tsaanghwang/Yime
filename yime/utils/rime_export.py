from __future__ import annotations

import argparse
import json
import sqlite3
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from typing import Iterable, Mapping

from yime.canonical_yime_mapping import (
    build_canonical_pinyin_rows,
    load_canonical_code_map,
)
from yime.utils.code_modes import YimeCodeMode, code_mode_label, lookup_code_column, normalize_code_mode
from yime.utils.yinyuan_id_chain import (
    layout_projection_digest,
    load_symbol_to_yinyuan_id,
    load_yinyuan_id_to_layout_key,
)


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DB_PATH = REPO_ROOT / "yime" / "pinyin_hanzi.db"
DEFAULT_OUTPUT_DIR = REPO_ROOT / ".generated" / "rime"
DEFAULT_SCHEMA_ID_PREFIX = "yime"

RUNTIME_SQL_PRIORITY_ORDER = """
CASE
    WHEN entry_type = 'phrase' AND text_length BETWEEN 2 AND 4 THEN 0
    WHEN entry_type = 'char' THEN 1
    ELSE 2
END,
sort_weight DESC,
text,
pinyin_tone
"""

@dataclass(frozen=True)
class RimeExportPaths:
    schema_path: Path
    dict_path: Path
    metadata_path: Path


@dataclass(frozen=True)
class RimeExportResult:
    mode: YimeCodeMode
    schema_id: str
    code_form: str
    row_count: int
    code_count: int
    paths: RimeExportPaths


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export Yime runtime candidates as Rime schema/dict files.")
    parser.add_argument("--db", default=str(DEFAULT_DB_PATH), help="SQLite runtime database path.")
    parser.add_argument("--output-dir", default=str(DEFAULT_OUTPUT_DIR), help="Directory for generated Rime files.")
    parser.add_argument(
        "--layout",
        default="",
        help=(
            "Compatibility argument. Only the repository canonical layout is accepted; "
            "alternate layout files are rejected."
        ),
    )
    parser.add_argument(
        "--pinyin-codes-output",
        default="",
        help="Optionally export the numeric-tone-pinyin to fixed-length layout-key TSV.",
    )
    parser.add_argument(
        "--pinyin-codes-inventory",
        default="",
        help="Optional existing TSV whose first column fixes the exported pinyin inventory and order.",
    )
    parser.add_argument(
        "--mode",
        default=YimeCodeMode.VARIABLE.value,
        choices=[mode.value for mode in YimeCodeMode],
        help="Yime code mode to export.",
    )
    parser.add_argument(
        "--code-form",
        default="layout-key",
        choices=["layout-key", "runtime-symbol"],
        help="Export codes as keyboard-layout keys or raw runtime symbols.",
    )
    parser.add_argument("--schema-id", default="", help="Override generated Rime schema id.")
    parser.add_argument("--schema-name", default="", help="Override generated Rime display name.")
    parser.add_argument("--limit", type=int, default=0, help="Limit exported rows for smoke-test data; 0 exports all.")
    return parser.parse_args()


def _json_load(path: Path) -> dict[str, object]:
    return json.loads(path.read_text(encoding="utf-8"))


def load_runtime_symbol_to_layout_key(
    repo_root: Path = REPO_ROOT,
    layout_path: Path | None = None,
) -> dict[str, str]:
    symbol_to_id = load_symbol_to_yinyuan_id(repo_root)
    id_to_key = load_yinyuan_id_to_layout_key(repo_root, layout_path)
    return {symbol: id_to_key[yinyuan_id] for symbol, yinyuan_id in symbol_to_id.items()}


def convert_runtime_code_to_layout_keys(code: str, symbol_to_key: Mapping[str, str]) -> str:
    converted: list[str] = []
    for char in str(code or ""):
        try:
            converted.append(symbol_to_key[char])
        except KeyError as exc:
            raise ValueError(f"Runtime symbol has no Rime layout-key mapping: U+{ord(char):04X}") from exc
    return "".join(converted)


def export_pinyin_codes_tsv(
    output_path: Path,
    *,
    db_path: Path = DEFAULT_DB_PATH,
    repo_root: Path = REPO_ROOT,
    layout_path: Path | None = None,
    inventory_path: Path | None = None,
) -> int:
    symbol_to_key = load_runtime_symbol_to_layout_key(repo_root, layout_path)
    if inventory_path:
        canonical_by_pinyin = load_canonical_code_map(repo_root)
        inventory_lines = inventory_path.read_text(encoding="utf-8-sig").splitlines()
        inventory = [line.split("\t", 1)[0].strip() for line in inventory_lines[1:] if line.strip()]
    else:
        conn = sqlite3.connect(db_path)
        try:
            canonical_rows = build_canonical_pinyin_rows(conn, repo_root)
        finally:
            conn.close()
        canonical_by_pinyin = {
            pinyin_tone: code for pinyin_tone, code, _ in canonical_rows
        }
        inventory = [pinyin_tone for pinyin_tone, _, _ in canonical_rows]

    lines = ["pinyin_tone\tfull"]
    for pinyin_tone in inventory:
        canonical_code = canonical_by_pinyin.get(pinyin_tone)
        if not canonical_code:
            raise ValueError(f"Pinyin inventory entry has no canonical Yime code: {pinyin_tone}")
        code = convert_runtime_code_to_layout_keys(canonical_code, symbol_to_key)
        lines.append(f"{pinyin_tone}\t{code}")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return len(lines) - 1


def _table_columns(conn: sqlite3.Connection, table_name: str) -> set[str]:
    return {str(row[1] or "") for row in conn.execute(f"PRAGMA table_info({table_name})").fetchall()}


def _select_export_rows(
    conn: sqlite3.Connection,
    *,
    mode: YimeCodeMode,
    limit: int = 0,
) -> list[sqlite3.Row]:
    columns = _table_columns(conn, "runtime_candidates_materialized")
    preferred_column = lookup_code_column(mode)
    if preferred_column in columns:
        code_expr = preferred_column
    elif mode == YimeCodeMode.FULL and "yime_code" in columns:
        code_expr = "yime_code"
    elif "primary_yime_code" in columns:
        code_expr = "primary_yime_code"
    else:
        code_expr = "yime_code"

    limit_clause = "LIMIT ?" if limit > 0 else ""
    params: tuple[int, ...] = (limit,) if limit > 0 else ()
    return conn.execute(
        f"""
        SELECT
            text,
            {code_expr} AS lookup_code,
            pinyin_tone,
            entry_type,
            sort_weight,
            text_length
        FROM runtime_candidates_materialized
        WHERE COALESCE({code_expr}, '') <> ''
        ORDER BY lookup_code, {RUNTIME_SQL_PRIORITY_ORDER}
        {limit_clause}
        """,
        params,
    ).fetchall()


def _rime_quote(value: str) -> str:
    escaped = str(value).replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def _rime_weight(value: object) -> int:
    try:
        weight = int(round(float(value or 0)))
    except (TypeError, ValueError):
        return 0
    return max(weight, 0)


def _schema_id_for(mode: YimeCodeMode, schema_id: str = "") -> str:
    override = str(schema_id or "").strip()
    if override:
        return override
    return f"{DEFAULT_SCHEMA_ID_PREFIX}_{mode.value}"


def _schema_name_for(mode: YimeCodeMode, schema_name: str = "") -> str:
    override = str(schema_name or "").strip()
    if override:
        return override
    return f"Yime {code_mode_label(mode)}"


def _alphabet_from_codes(codes: Iterable[str]) -> str:
    seen: set[str] = set()
    chars: list[str] = []
    for code in codes:
        for char in code:
            if char not in seen:
                seen.add(char)
                chars.append(char)
    return "".join(chars)


def build_rime_dict_text(
    *,
    schema_id: str,
    mode: YimeCodeMode,
    code_form: str,
    entries: list[tuple[str, str, int]],
) -> str:
    today = date.today().isoformat()
    lines = [
        "# Rime dictionary",
        "# encoding: utf-8",
        "# Generated from Yime runtime_candidates_materialized.",
        "---",
        f"name: {schema_id}",
        f'version: "{today}"',
        "sort: by_weight",
        "use_preset_vocabulary: false",
        "...",
    ]
    for text, code, weight in entries:
        lines.append(f"{text}\t{code}\t{weight}")
    lines.append("")
    return "\n".join(lines)


def build_rime_schema_text(
    *,
    schema_id: str,
    schema_name: str,
    dictionary_name: str,
    user_dict_name: str,
    alphabet: str,
) -> str:
    today = date.today().isoformat()
    return "\n".join(
        [
            "# Rime schema",
            "# encoding: utf-8",
            "# Generated from Yime runtime_candidates_materialized.",
            "",
            "schema:",
            f"  schema_id: {schema_id}",
            f"  name: {_rime_quote(schema_name)}",
            f'  version: "{today}"',
            "",
            "engine:",
            "  processors:",
            "    - ascii_composer",
            "    - recognizer",
            "    - key_binder",
            "    - speller",
            "    - punctuator",
            "    - selector",
            "    - navigator",
            "    - express_editor",
            "  segmentors:",
            "    - ascii_segmentor",
            "    - matcher",
            "    - abc_segmentor",
            "    - punct_segmentor",
            "    - fallback_segmentor",
            "  translators:",
            "    - table_translator",
            "    - punct_translator",
            "",
            "speller:",
            f"  alphabet: {_rime_quote(alphabet)}",
            '  delimiter: " "',
            "",
            "translator:",
            f"  dictionary: {dictionary_name}",
            f"  user_dict: {user_dict_name}",
            "  enable_user_dict: true",
            "  enable_sentence: false",
            "  enable_completion: true",
            "",
            "menu:",
            "  page_size: 9",
            "",
            "punctuator:",
            "  import_preset: default",
            "",
            "key_binder:",
            "  import_preset: default",
            "",
            "",
        ]
    )


def export_rime_files(
    *,
    db_path: Path = DEFAULT_DB_PATH,
    output_dir: Path = DEFAULT_OUTPUT_DIR,
    mode: YimeCodeMode | str = YimeCodeMode.VARIABLE,
    code_form: str = "layout-key",
    schema_id: str = "",
    schema_name: str = "",
    limit: int = 0,
    repo_root: Path = REPO_ROOT,
    layout_path: Path | None = None,
) -> RimeExportResult:
    normalized_mode = normalize_code_mode(mode)
    normalized_code_form = str(code_form or "layout-key").strip()
    if normalized_code_form not in {"layout-key", "runtime-symbol"}:
        raise ValueError(f"Unsupported Rime code form: {code_form}")

    resolved_schema_id = _schema_id_for(normalized_mode, schema_id)
    resolved_schema_name = _schema_name_for(normalized_mode, schema_name)
    output_dir.mkdir(parents=True, exist_ok=True)

    symbol_to_key = (
        load_runtime_symbol_to_layout_key(repo_root, layout_path)
        if normalized_code_form == "layout-key"
        else {}
    )

    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    try:
        rows = _select_export_rows(conn, mode=normalized_mode, limit=limit)
    finally:
        conn.close()

    entries: list[tuple[str, str, int]] = []
    for row in rows:
        raw_code = str(row["lookup_code"] or "").strip()
        if not raw_code:
            continue
        code = (
            convert_runtime_code_to_layout_keys(raw_code, symbol_to_key)
            if normalized_code_form == "layout-key"
            else raw_code
        )
        text = str(row["text"] or "").strip()
        if not text:
            continue
        entries.append((text, code, _rime_weight(row["sort_weight"])))

    alphabet = _alphabet_from_codes(code for _, code, _ in entries)
    layout_digest = layout_projection_digest(repo_root)
    user_dict_name = f"{resolved_schema_id}_layout_{layout_digest[:12]}"
    paths = RimeExportPaths(
        schema_path=output_dir / f"{resolved_schema_id}.schema.yaml",
        dict_path=output_dir / f"{resolved_schema_id}.dict.yaml",
        metadata_path=output_dir / f"{resolved_schema_id}.metadata.json",
    )
    paths.dict_path.write_text(
        build_rime_dict_text(
            schema_id=resolved_schema_id,
            mode=normalized_mode,
            code_form=normalized_code_form,
            entries=entries,
        ),
        encoding="utf-8",
    )
    paths.schema_path.write_text(
        build_rime_schema_text(
            schema_id=resolved_schema_id,
            schema_name=resolved_schema_name,
            dictionary_name=resolved_schema_id,
            user_dict_name=user_dict_name,
            alphabet=alphabet,
        ),
        encoding="utf-8",
    )
    metadata = {
        "mode": normalized_mode.value,
        "mode_label": code_mode_label(normalized_mode),
        "code_form": normalized_code_form,
        "db_path": str(db_path),
        "schema_id": resolved_schema_id,
        "row_count": len(entries),
        "code_count": len({code for _, code, _ in entries}),
        "alphabet": alphabet,
        "layout_projection_sha256": layout_digest,
        "user_dict_name": user_dict_name,
        "limit": limit,
        "layout_path": str(layout_path) if layout_path else "",
    }
    paths.metadata_path.write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8")

    return RimeExportResult(
        mode=normalized_mode,
        schema_id=resolved_schema_id,
        code_form=normalized_code_form,
        row_count=len(entries),
        code_count=int(metadata["code_count"]),
        paths=paths,
    )


def main() -> None:
    args = parse_args()
    result = export_rime_files(
        db_path=Path(args.db),
        output_dir=Path(args.output_dir),
        mode=args.mode,
        code_form=args.code_form,
        schema_id=args.schema_id,
        schema_name=args.schema_name,
        limit=args.limit,
        layout_path=Path(args.layout) if args.layout else None,
    )
    print(f"Exported {result.row_count} rows / {result.code_count} codes")
    print(f"schema: {result.paths.schema_path}")
    print(f"dict: {result.paths.dict_path}")
    print(f"metadata: {result.paths.metadata_path}")
    if args.pinyin_codes_output:
        output_path = Path(args.pinyin_codes_output)
        row_count = export_pinyin_codes_tsv(
            output_path,
            db_path=Path(args.db),
            layout_path=Path(args.layout) if args.layout else None,
            inventory_path=Path(args.pinyin_codes_inventory) if args.pinyin_codes_inventory else None,
        )
        print(f"pinyin codes: {output_path} ({row_count} rows)")


if __name__ == "__main__":
    main()
