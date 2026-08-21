from __future__ import annotations

import json
import sqlite3
from functools import lru_cache
from pathlib import Path
from typing import Any, TypedDict, cast

from syllable.codec.variable_length_yinyuan import to_variable_length_yinyuan_code
from yime.utils.code_modes import (
    CodeModeRecord,
    build_code_mode_map,
    load_ganyin_symbol_metadata,
)
from yime.utils.numeric_pinyin_standardizer import standardize_numeric_pinyin
from yime.utils.yinjie_slot_decomposition import sync_yinjie_slot_decomposition


WORKSPACE_ROOT = Path(__file__).resolve().parents[2]
def load_json(path: Path) -> dict[str, Any]:
    return cast(dict[str, Any], json.loads(path.read_text(encoding="utf-8")))


def build_bmp_to_canonical_map(repo_root: Path | None = None) -> dict[str, str]:
    resolved_root = repo_root or WORKSPACE_ROOT
    projection = load_json(resolved_root / "internal_data" / "bmp_pua_trial_projection.json")
    key_to_symbol = load_json(resolved_root / "internal_data" / "key_to_symbol.json")

    bmp_to_canonical: dict[str, str] = {}
    for yinyuan_id, projection_info in projection.get("used_mapping", {}).items():
        bmp_char = str(projection_info.get("char", ""))
        canonical_char = str(key_to_symbol.get(yinyuan_id, ""))
        if bmp_char and canonical_char:
            bmp_to_canonical[bmp_char] = canonical_char
    return bmp_to_canonical


@lru_cache(maxsize=None)
def _load_virtual_initial_symbol_cached(repo_root_key: str) -> str:
    resolved_root = Path(repo_root_key)
    mapping = load_json(resolved_root / "internal_data" / "yinjie_runtime_key_symbol_mapping.json")
    runtime_symbol = ""
    for entry in mapping.get("entries", []):
        if entry.get("source_type") == "shouyin" and entry.get("source_name") == "'":
            runtime_symbol = str(entry.get("symbol", ""))
            break
    if not runtime_symbol:
        return ""
    bmp_to_canonical = build_bmp_to_canonical_map(resolved_root)
    return bmp_to_canonical.get(runtime_symbol, runtime_symbol)


def load_virtual_initial_symbol(repo_root: Path | None = None) -> str:
    resolved_root = repo_root or WORKSPACE_ROOT
    return _load_virtual_initial_symbol_cached(str(resolved_root.resolve()))


def canonicalize_code(code: str, bmp_to_canonical: dict[str, str]) -> str:
    return "".join(bmp_to_canonical.get(char, char) for char in code)


def convert_legacy_code_to_primary(code: str, *, virtual_initial: str | None = None) -> str:
    normalized_code = str(code or "").strip()
    if not normalized_code:
        return ""
    _ = virtual_initial  # Compatibility argument; the initial is no longer omitted.
    if len(normalized_code) < 4:
        initial = normalized_code[:1]
        merged_ganyin: list[str] = []
        for symbol in normalized_code[1:]:
            if not merged_ganyin or merged_ganyin[-1] != symbol:
                merged_ganyin.append(symbol)
        return initial + "".join(merged_ganyin)

    if len(normalized_code) == 4:
        return to_variable_length_yinyuan_code(normalized_code)

    complete_length = (len(normalized_code) // 4) * 4
    primary_parts = [
        to_variable_length_yinyuan_code(normalized_code[index:index + 4])
        for index in range(0, complete_length, 4)
    ]
    trailing = normalized_code[complete_length:]
    if trailing:
        primary_parts.append(convert_legacy_code_to_primary(trailing))
    return "".join(primary_parts)


def load_canonical_code_map(repo_root: Path | None = None) -> dict[str, str]:
    resolved_root = repo_root or WORKSPACE_ROOT
    code_map = load_json(resolved_root / "syllable" / "codec" / "yinjie_code.json")
    bmp_to_canonical = build_bmp_to_canonical_map(resolved_root)

    canonical_code_map = {
        standardize_numeric_pinyin(pinyin): canonicalize_code(code, bmp_to_canonical)
        for pinyin, code in code_map.items()
    }

    return canonical_code_map


def load_primary_code_map(repo_root: Path | None = None) -> dict[str, str]:
    primary_code_map: dict[str, str] = {}
    for pinyin_tone, code in load_canonical_code_map(repo_root).items():
        primary_code = convert_legacy_code_to_primary(code)
        if primary_code:
            primary_code_map[pinyin_tone] = primary_code
    return primary_code_map


def load_code_mode_map(repo_root: Path | None = None) -> dict[str, CodeModeRecord]:
    resolved_root = repo_root or WORKSPACE_ROOT
    return build_code_mode_map(
        load_canonical_code_map(resolved_root),
        ganyin_symbol_metadata=load_ganyin_symbol_metadata(resolved_root),
    )


def build_canonical_pinyin_rows(
    conn: sqlite3.Connection,
    repo_root: Path | None = None,
) -> list[tuple[str, str, str]]:
    canonical_code_map = load_canonical_code_map(repo_root)
    rows = conn.execute(
        '''
        SELECT DISTINCT pinyin_tone
        FROM numeric_pinyin_inventory
        WHERE pinyin_tone IS NOT NULL AND TRIM(pinyin_tone) <> ''
        ORDER BY pinyin_tone
        '''
    ).fetchall()

    pinyin_rows: list[tuple[str, str, str]] = []
    seen_pinyin: set[str] = set()
    for (pinyin_tone_raw,) in rows:
        pinyin_tone = standardize_numeric_pinyin(str(pinyin_tone_raw or '').strip())
        if not pinyin_tone:
            continue
        if pinyin_tone in seen_pinyin:
            continue
        canonical_code = canonical_code_map.get(pinyin_tone, '')
        if not canonical_code:
            continue
        pinyin_rows.append((pinyin_tone, canonical_code, 'yinjie_code'))
        seen_pinyin.add(pinyin_tone)

    return pinyin_rows


def build_canonical_mapping_rows(
    conn: sqlite3.Connection,
    repo_root: Path | None = None,
) -> list[tuple[int, str, str]]:
    from collections import defaultdict

    class MappingGroup(TypedDict):
        codes: set[str]
        tones: list[str]

    canonical_code_map = load_canonical_code_map(repo_root)
    rows = conn.execute(
        '''
        SELECT mapping_id, pinyin_tone
        FROM numeric_pinyin_inventory
        WHERE mapping_id IS NOT NULL
        ORDER BY mapping_id, pinyin_tone
        '''
    ).fetchall()

    grouped: dict[int, MappingGroup] = defaultdict(
        lambda: cast(MappingGroup, {"codes": set(), "tones": []})
    )
    for mapping_id_raw, pinyin_tone_raw in rows:
        mapping_id = int(mapping_id_raw)
        pinyin_tone = standardize_numeric_pinyin(str(pinyin_tone_raw or "").strip())
        if not pinyin_tone:
            continue
        canonical_code = canonical_code_map.get(pinyin_tone, "")
        if not canonical_code:
            continue
        grouped[mapping_id]["codes"].add(canonical_code)
        grouped[mapping_id]["tones"].append(pinyin_tone)

    mapping_rows: list[tuple[int, str, str]] = []
    conflicts: list[tuple[int, list[str], list[str]]] = []
    for mapping_id, payload in grouped.items():
        codes = sorted(payload["codes"])
        tones = sorted(set(payload["tones"]))
        if len(codes) > 1:
            conflicts.append((mapping_id, tones, codes))
            continue
        if not codes:
            continue
        mapping_rows.append((mapping_id, codes[0], tones[0]))

    if conflicts:
        preview = "; ".join(
            f"mapping_id={mapping_id}, tones={tones[:3]}, codes={codes[:3]}"
            for mapping_id, tones, codes in conflicts[:5]
        )
        raise RuntimeError(f"canonical mapping conflicts detected: {preview}")

    return mapping_rows


def sync_canonical_mapping_table(
    conn: sqlite3.Connection,
    repo_root: Path | None = None,
) -> int:
    pinyin_rows = build_canonical_pinyin_rows(conn, repo_root)
    conn.execute("DELETE FROM pinyin_yime_code")
    conn.executemany(
        '''
        INSERT INTO pinyin_yime_code (pinyin_tone, yime_code, code_source, updated_at)
        VALUES (?, ?, ?, CURRENT_TIMESTAMP)
        ''',
        pinyin_rows,
    )

    mapping_rows = build_canonical_mapping_rows(conn, repo_root)
    conn.execute("DELETE FROM mapping_yime_code")
    conn.executemany(
        '''
        INSERT INTO mapping_yime_code (mapping_id, yime_code, source_pinyin_tone, updated_at)
        VALUES (?, ?, ?, CURRENT_TIMESTAMP)
        ''',
        mapping_rows,
    )
    sync_yinjie_slot_decomposition(conn)
    return len(pinyin_rows)
