from __future__ import annotations

import csv
import json
import sqlite3
from pathlib import Path


WORKSPACE_ROOT = Path(__file__).resolve().parent.parent
CANONICAL_PATCH_PATH = WORKSPACE_ROOT / "internal_data" / "pinyin_source_db" / "canonical_yime_patch.csv"


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def build_bmp_to_canonical_map(repo_root: Path | None = None) -> dict[str, str]:
    resolved_root = repo_root or WORKSPACE_ROOT
    projection = load_json(resolved_root / "internal_data" / "bmp_pua_trial_projection.json")
    key_to_symbol = load_json(resolved_root / "internal_data" / "key_to_symbol.json")

    bmp_to_canonical: dict[str, str] = {}
    for slot_key, slot_info in projection.get("used_mapping", {}).items():
        bmp_char = str(slot_info.get("char", ""))
        canonical_char = str(key_to_symbol.get(slot_key, ""))
        if bmp_char and canonical_char:
            bmp_to_canonical[bmp_char] = canonical_char
    return bmp_to_canonical


def canonicalize_code(code: str, bmp_to_canonical: dict[str, str]) -> str:
    return "".join(bmp_to_canonical.get(char, char) for char in code)


def load_canonical_code_map(repo_root: Path | None = None) -> dict[str, str]:
    resolved_root = repo_root or WORKSPACE_ROOT
    code_map = load_json(resolved_root / "syllable_codec" / "yinjie_code.json")
    bmp_to_canonical = build_bmp_to_canonical_map(resolved_root)

    canonical_code_map = {
        pinyin: canonicalize_code(code, bmp_to_canonical)
        for pinyin, code in code_map.items()
    }

    for pinyin_tone, (patched_code, _) in load_canonical_patch_map(resolved_root).items():
        canonical_code_map.setdefault(pinyin_tone, patched_code)

    return canonical_code_map


def load_canonical_patch_map(repo_root: Path | None = None) -> dict[str, tuple[str, int | None]]:
    resolved_root = repo_root or WORKSPACE_ROOT
    if not CANONICAL_PATCH_PATH.exists():
        return {}

    bmp_to_canonical = build_bmp_to_canonical_map(resolved_root)
    patch_map: dict[str, tuple[str, int | None]] = {}
    with CANONICAL_PATCH_PATH.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            pinyin_tone = str(row.get("pinyin_tone") or "").strip()
            raw_code = str(row.get("yime_code") or "")
            mapping_id_raw = str(row.get("mapping_id") or "").strip()
            if not pinyin_tone or not raw_code:
                continue
            patch_map[pinyin_tone] = (
                canonicalize_code(raw_code, bmp_to_canonical),
                int(mapping_id_raw) if mapping_id_raw else None,
            )
    return patch_map


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
    for (pinyin_tone_raw,) in rows:
        pinyin_tone = str(pinyin_tone_raw or '').strip()
        if not pinyin_tone:
            continue
        canonical_code = canonical_code_map.get(pinyin_tone, '')
        if not canonical_code:
            continue
        source_name = 'canonical_patch' if pinyin_tone in load_canonical_patch_map(repo_root) else 'yinjie_code'
        pinyin_rows.append((pinyin_tone, canonical_code, source_name))

    return pinyin_rows


def build_canonical_mapping_rows(
    conn: sqlite3.Connection,
    repo_root: Path | None = None,
) -> list[tuple[int, str, str]]:
    from collections import defaultdict

    canonical_code_map = load_canonical_code_map(repo_root)
    canonical_patch_map = load_canonical_patch_map(repo_root)
    rows = conn.execute(
        '''
        SELECT mapping_id, pinyin_tone
        FROM numeric_pinyin_inventory
        WHERE mapping_id IS NOT NULL
        ORDER BY mapping_id, pinyin_tone
        '''
    ).fetchall()

    grouped: dict[int, dict[str, object]] = defaultdict(lambda: {"codes": set(), "tones": []})
    for mapping_id_raw, pinyin_tone_raw in rows:
        mapping_id = int(mapping_id_raw)
        pinyin_tone = str(pinyin_tone_raw or "").strip()
        if not pinyin_tone:
            continue
        canonical_code = canonical_code_map.get(pinyin_tone, "")
        if not canonical_code:
            patch_payload = canonical_patch_map.get(pinyin_tone)
            if patch_payload is not None:
                patched_code, patched_mapping_id = patch_payload
                if patched_mapping_id is None or patched_mapping_id == mapping_id:
                    canonical_code = patched_code
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
    return len(pinyin_rows)
