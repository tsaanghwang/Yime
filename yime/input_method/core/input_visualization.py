from __future__ import annotations

import json
from pathlib import Path
from typing import Dict, List, cast


def format_codepoints(text: str) -> str:
    if not text:
        return ""
    return " ".join(
        f"U+{ord(char):06X}" if ord(char) > 0xFFFF else f"U+{ord(char):04X}"
        for char in text
    )


def build_code_display(raw_text: str, canonical_code: str, active_code: str) -> str:
    if not active_code:
        return ""

    active_display = format_codepoints(active_code)
    if len(active_code) > 4 and len(active_code) % 4 == 0:
        active_label = f"当前{len(active_code) // 4}音节码"
    else:
        active_label = "当前4码"

    if not canonical_code:
        return active_display

    if raw_text and raw_text != canonical_code:
        return (
            f"{active_label} {active_display} | 输入 {format_codepoints(raw_text)}"
            f" | 规范化后共 {len(canonical_code)} 码"
        )

    if active_code != canonical_code:
        return f"{active_label} {active_display} | 累计输入 {len(canonical_code)} 码"

    return active_display


def _load_visual_json(path: Path) -> Dict[str, object]:
    with path.open("r", encoding="utf-8") as handle:
        return cast(Dict[str, object], json.load(handle))


def build_input_visual_map(repo_root: Path) -> Dict[str, str]:
    projection = _load_visual_json(
        repo_root / "internal_data" / "bmp_pua_trial_projection.json"
    )
    key_to_symbol = cast(
        Dict[str, str],
        _load_visual_json(repo_root / "internal_data" / "key_to_symbol.json"),
    )
    shouyin_payload = cast(
        Dict[str, Dict[str, object]],
        _load_visual_json(repo_root / "syllable" / "yinyuan" / "shouyin_codepoint.json"),
    )
    yinyuan_payload = cast(
        Dict[str, Dict[str, object]],
        _load_visual_json(repo_root / "syllable" / "yinyuan" / "yinyuan_codepoint.json"),
    )

    label_by_bmp: Dict[str, str] = {}
    for label, char in shouyin_payload.get("首音", {}).items():
        label_by_bmp[str(char)] = str(label)
    for namespace in ("zaoyin", "yueyin"):
        for label, char in yinyuan_payload.get(namespace, {}).items():
            label_by_bmp[str(char)] = str(label)

    typed_projection = projection
    used_mapping = cast(
        Dict[str, Dict[str, object]], typed_projection.get("used_mapping", {})
    )

    visual_map: Dict[str, str] = {}
    for raw_slot_key, slot_info in used_mapping.items():
        slot_key = str(raw_slot_key)
        bmp_char = str(slot_info.get("char", ""))
        canonical_char = str(key_to_symbol.get(slot_key, ""))
        label = label_by_bmp.get(bmp_char) or slot_key
        token = f"[{slot_key} {label}]"
        if bmp_char:
            visual_map[bmp_char] = token
        if canonical_char:
            visual_map[canonical_char] = token

    for reserved in cast(List[Dict[str, object]], typed_projection.get("reserved_slots", [])):
        bmp_char = str(reserved.get("char", ""))
        label = reserved.get("label")
        slot_key = str(label if label is not None else "reserved").split("_", 1)[0]
        if bmp_char:
            visual_map[bmp_char] = f"[{slot_key}]"

    return visual_map


def build_input_outline(text: str, visual_map: Dict[str, str]) -> str:
    if not text:
        return ""

    tokens: List[str] = []
    for char in text:
        token = visual_map.get(char)
        if token:
            tokens.append(token)
            continue

        codepoint = ord(char)
        fallback = f"U+{codepoint:06X}" if codepoint > 0xFFFF else f"U+{codepoint:04X}"
        tokens.append(f"[{fallback}]")

    return " ".join(tokens)


def _strip_slot_from_visual_token(token: str) -> str:
    body = token.strip()
    if body.startswith("[") and body.endswith("]"):
        body = body[1:-1].strip()

    slot, separator, label = body.partition(" ")
    if (
        separator
        and len(slot) == 3
        and slot[0] in {"N", "M"}
        and slot[1:].isdigit()
    ):
        return label.strip()
    if len(body) == 3 and body[0] in {"N", "M"} and body[1:].isdigit():
        return ""
    return body


def build_input_sound_notes(text: str, visual_map: Dict[str, str]) -> str:
    if not text:
        return ""

    notes: List[str] = []
    for char in text:
        token = visual_map.get(char)
        if token:
            notes.append(_strip_slot_from_visual_token(token))
            continue

        codepoint = ord(char)
        notes.append(f"U+{codepoint:06X}" if codepoint > 0xFFFF else f"U+{codepoint:04X}")

    return "".join(note for note in notes if note)


def build_physical_input_map(repo_root: Path) -> Dict[str, str]:
    manual_layout = _load_visual_json(
        repo_root / "internal_data" / "manual_key_layout.json"
    )
    slot_to_bmp = cast(
        Dict[str, str],
        _load_visual_json(repo_root / "syllable" / "codec" / "key_to_code.json"),
    )
    slot_to_symbol = cast(
        Dict[str, str],
        _load_visual_json(repo_root / "internal_data" / "key_to_symbol.json"),
    )

    physical_map: Dict[str, str] = {}
    for row in cast(List[Dict[str, object]], manual_layout.get("layers", [])):
        symbol_key = row.get("symbol_key")
        if not symbol_key:
            continue

        input_token = str(row.get("display_label") or row.get("physical_key") or "")
        bmp_char = slot_to_bmp.get(str(symbol_key))
        symbol_char = slot_to_symbol.get(str(symbol_key))
        if bmp_char and input_token and len(input_token) == 1:
            physical_map[input_token] = str(bmp_char)
        if bmp_char and symbol_char:
            physical_map[str(symbol_char)] = str(bmp_char)

    return physical_map


def build_manual_key_output_map(repo_root: Path) -> Dict[tuple[str, str], str]:
    manual_layout = _load_visual_json(
        repo_root / "internal_data" / "manual_key_layout.resolved.json"
    )

    output_map: Dict[tuple[str, str], str] = {}
    for row in cast(List[Dict[str, object]], manual_layout.get("layers", [])):
        physical_key = str(row.get("physical_key") or "").strip().lower()
        output_layer = str(row.get("output_layer") or "").strip().lower()
        resolved_char = str(row.get("resolved_char") or "")
        if not physical_key or not output_layer or not resolved_char:
            continue
        output_map[(physical_key, output_layer)] = resolved_char

    return output_map


def build_non_base_literal_output_chars(repo_root: Path) -> set[str]:
    manual_layout = _load_visual_json(
        repo_root / "internal_data" / "manual_key_layout.resolved.json"
    )

    passthrough_chars: set[str] = set()
    for row in cast(List[Dict[str, object]], manual_layout.get("layers", [])):
        output_layer = str(row.get("output_layer") or "").strip().lower()
        resolved_category = str(row.get("resolved_category") or "").strip().lower()
        resolved_char = str(row.get("resolved_char") or "")
        if output_layer == "base" or resolved_category != "literal" or len(resolved_char) != 1:
            continue
        passthrough_chars.add(resolved_char)

    return passthrough_chars


def project_physical_input(text: str, physical_map: Dict[str, str]) -> str:
    if not text:
        return ""

    projected_chars: List[str] = []
    for char in text:
        projected_chars.append(physical_map.get(char, char))
    return "".join(projected_chars)


def build_projected_to_physical_map(
    physical_map: Dict[str, str]
) -> Dict[str, str]:
    return {projected: physical for physical, projected in physical_map.items()}


def build_projected_to_keycap_map(repo_root: Path) -> Dict[str, str]:
    manual_layout = _load_visual_json(repo_root / "internal_data" / "manual_key_layout.json")
    slot_to_bmp = cast(
        Dict[str, str],
        _load_visual_json(repo_root / "syllable" / "codec" / "key_to_code.json"),
    )
    slot_to_symbol = cast(
        Dict[str, str],
        _load_visual_json(repo_root / "internal_data" / "key_to_symbol.json"),
    )

    projected_to_keycap: Dict[str, str] = {}
    for row in cast(List[Dict[str, object]], manual_layout.get("layers", [])):
        symbol_key = row.get("symbol_key")
        symbol_key_text = str(symbol_key) if symbol_key else ""
        physical_key_value = row.get("physical_key")
        physical_key = str(physical_key_value) if physical_key_value else ""
        bmp_char = slot_to_bmp.get(symbol_key_text) if symbol_key_text else None
        symbol_char = slot_to_symbol.get(symbol_key_text) if symbol_key_text else None
        if len(physical_key) != 1:
            continue

        keycap = physical_key.lower()
        if bmp_char:
            projected_to_keycap.setdefault(str(cast(object, bmp_char)), keycap)
        if symbol_char:
            projected_to_keycap.setdefault(str(cast(object, symbol_char)), keycap)

    return projected_to_keycap


def unproject_physical_input(
    text: str, projected_to_physical_map: Dict[str, str]
) -> str:
    if not text:
        return ""

    physical_chars: List[str] = []
    for char in text:
        physical_chars.append(projected_to_physical_map.get(char, char))
    return "".join(physical_chars)
