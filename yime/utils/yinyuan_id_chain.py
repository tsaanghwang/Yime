"""Canonical bridge from numeric-tone Pinyin to Yinyuan IDs and layout keys.

Keyboard layout code must consume this module instead of inventing a direct
Pinyin-to-key mapping.  The semantic chain ends at Yinyuan IDs; physical keys
are a separate, final projection.
"""

from __future__ import annotations

import hashlib
import json
from functools import lru_cache
from pathlib import Path
from typing import Any, Iterable, cast

from syllable.codec.yinjie_encoder import YinjieEncoder


REPO_ROOT = Path(__file__).resolve().parents[2]
SHOUYIN_SOURCE = Path("syllable/yinyuan/zaoyin_yinyuan_enhanced.json")
YUEYIN_SOURCE = Path("syllable/yinyuan/yueyin_yinyuan_enhanced.json")
CANONICAL_SYMBOL_SOURCE = Path("internal_data/key_to_symbol.json")
CANONICAL_LAYOUT_SOURCE = Path("internal_data/manual_key_layout.json")
CONTROLLED_SHARED_LAYOUT_GROUPS = {
    frozenset(("N12", "N26")),
    frozenset(("N25", "N27")),
}


def expected_yinyuan_ids() -> set[str]:
    return {
        *(f"N{index:02d}" for index in range(1, 28)),
        *(f"M{index:02d}" for index in range(1, 34)),
    }


def load_shared_layout_groups(layout: dict[str, Any]) -> dict[str, tuple[str, ...]]:
    """Return owner -> members for the two reviewed many-ID-to-one-key groups."""
    raw_groups = layout.get("shared_yinyuan_key_groups", [])
    if not isinstance(raw_groups, list):
        raise ValueError("shared_yinyuan_key_groups must be an array")
    groups: dict[str, tuple[str, ...]] = {}
    actual_sets: set[frozenset[str]] = set()
    seen_members: set[str] = set()
    for raw_group in raw_groups:
        if not isinstance(raw_group, dict):
            raise ValueError("shared Yinyuan key group must be an object")
        owner = str(raw_group.get("owner_yinyuan_id") or "")
        raw_members = raw_group.get("member_yinyuan_ids", [])
        if not isinstance(raw_members, list):
            raise ValueError(f"shared group {owner} members must be an array")
        members = tuple(map(str, raw_members))
        member_set = frozenset(members)
        if not owner or owner not in member_set or len(members) != len(member_set):
            raise ValueError(f"invalid shared Yinyuan key group: {owner} -> {members}")
        if member_set not in CONTROLLED_SHARED_LAYOUT_GROUPS:
            raise ValueError(f"unreviewed shared Yinyuan key group: {sorted(member_set)}")
        overlap = seen_members & member_set
        if overlap:
            raise ValueError(f"Yinyuan IDs occur in multiple shared groups: {sorted(overlap)}")
        seen_members.update(member_set)
        actual_sets.add(member_set)
        groups[owner] = members
    if actual_sets != CONTROLLED_SHARED_LAYOUT_GROUPS:
        raise ValueError("canonical layout must declare both controlled shared-key groups")
    return groups


def _load_json(path: Path) -> dict[str, Any]:
    return cast(dict[str, Any], json.loads(path.read_text(encoding="utf-8")))


def load_semantic_yinyuan_registry(repo_root: Path = REPO_ROOT) -> dict[str, dict[str, str]]:
    """Load the authoritative semantic entry for every Yinyuan ID."""
    registry: dict[str, dict[str, str]] = {}
    for category, relative_path in (
        ("initial", SHOUYIN_SOURCE),
        ("musical", YUEYIN_SOURCE),
    ):
        payload = _load_json(repo_root / relative_path)
        entries = payload.get("entries")
        if not isinstance(entries, dict) or not entries:
            raise ValueError(f"Yinyuan semantic source has no entries: {relative_path}")
        for label, raw_entry in entries.items():
            if not isinstance(raw_entry, dict):
                raise ValueError(f"Invalid Yinyuan semantic entry: {relative_path} -> {label}")
            entry = cast(dict[str, Any], raw_entry)
            yinyuan_id = str(entry.get("yinyuan_id") or "")
            semantic_code = str(entry.get("semantic_code") or "")
            runtime_char = str(entry.get("runtime_char") or "")
            if not yinyuan_id or not semantic_code or len(runtime_char) != 1:
                raise ValueError(f"Incomplete Yinyuan semantic entry: {relative_path} -> {label}")
            if yinyuan_id in registry:
                raise ValueError(f"Duplicate Yinyuan ID in semantic sources: {yinyuan_id}")
            registry[yinyuan_id] = {
                "category": category,
                "label": str(label),
                "semantic_code": semantic_code,
                "runtime_char": runtime_char,
            }

    expected = expected_yinyuan_ids()
    if set(registry) != expected:
        missing = sorted(expected - set(registry))
        extra = sorted(set(registry) - expected)
        raise ValueError(f"Semantic Yinyuan registry mismatch: missing={missing}, extra={extra}")
    runtime_chars = [entry["runtime_char"] for entry in registry.values()]
    if len(runtime_chars) != len(set(runtime_chars)):
        raise ValueError("Semantic Yinyuan registry contains duplicate runtime characters")
    return registry


def load_symbol_to_yinyuan_id(repo_root: Path = REPO_ROOT) -> dict[str, str]:
    """Map both runtime BMP and canonical SPUA-B symbols to stable IDs."""
    registry = load_semantic_yinyuan_registry(repo_root)
    canonical_symbols = _load_json(repo_root / CANONICAL_SYMBOL_SOURCE)
    if set(canonical_symbols) != expected_yinyuan_ids():
        raise ValueError("Canonical symbol source does not cover exactly N01-N27 and M01-M33")

    symbol_to_id: dict[str, str] = {}
    for yinyuan_id, entry in registry.items():
        for symbol in (entry["runtime_char"], str(canonical_symbols[yinyuan_id])):
            previous = symbol_to_id.get(symbol)
            if previous is not None and previous != yinyuan_id:
                raise ValueError(f"Symbol is assigned to both {previous} and {yinyuan_id}")
            symbol_to_id[symbol] = yinyuan_id
    return symbol_to_id


def symbol_code_to_yinyuan_ids(
    code: str,
    *,
    repo_root: Path = REPO_ROOT,
) -> tuple[str, ...]:
    """Convert a runtime/canonical symbol code into stable Yinyuan IDs."""
    symbol_to_id = load_symbol_to_yinyuan_id(repo_root)
    result: list[str] = []
    for symbol in str(code or ""):
        try:
            result.append(symbol_to_id[symbol])
        except KeyError as exc:
            raise ValueError(f"Unknown Yinyuan symbol: U+{ord(symbol):04X}") from exc
    return tuple(result)


@lru_cache(maxsize=1)
def _default_encoder() -> YinjieEncoder:
    return YinjieEncoder()


def encode_numeric_pinyin_to_yinyuan_ids(
    pinyin_tone: str,
    *,
    repo_root: Path = REPO_ROOT,
    encoder: YinjieEncoder | None = None,
) -> tuple[str, str, str, str]:
    """Encode one numeric-tone syllable through the semantic chain."""
    resolved_encoder = encoder or (_default_encoder() if repo_root == REPO_ROOT else YinjieEncoder())
    code = resolved_encoder.encode_single_yinjie(pinyin_tone)
    ids = symbol_code_to_yinyuan_ids(code, repo_root=repo_root)
    if len(ids) != 4:
        raise ValueError(f"Syllable must resolve to four Yinyuan IDs: {pinyin_tone} -> {ids}")
    return cast(tuple[str, str, str, str], ids)


def load_yinyuan_id_to_layout_key(
    repo_root: Path = REPO_ROOT,
    layout_path: Path | None = None,
) -> dict[str, str]:
    """Load the sole canonical final projection from Yinyuan ID to key token."""
    canonical_path = (repo_root / CANONICAL_LAYOUT_SOURCE).resolve()
    resolved_path = (layout_path or canonical_path).resolve()
    if resolved_path != canonical_path:
        raise ValueError(
            "Independent keyboard-layout sources are locked. "
            f"Edit {CANONICAL_LAYOUT_SOURCE.as_posix()} and regenerate artifacts."
        )

    layout = _load_json(canonical_path)
    if "yinyuan_id_to_key" in layout:
        raise ValueError("Compact Yinyuan-ID maps are forbidden in the canonical layout source")

    mapping: dict[str, str] = {}
    occupied: dict[str, str] = {}
    layers = layout.get("layers")
    if not isinstance(layers, list):
        raise ValueError("Canonical layout source has no layers array")
    for raw_entry in layers:
        if not isinstance(raw_entry, dict):
            continue
        entry = cast(dict[str, Any], raw_entry)
        yinyuan_id = str(entry.get("yinyuan_id") or "")
        if not yinyuan_id:
            continue
        layer = str(entry.get("output_layer") or "")
        key = str(entry.get("display_label") or "")
        if layer not in {"base", "shift"}:
            raise ValueError(f"Yinyuan ID must use base/shift, got {layer}: {yinyuan_id}")
        if len(key) != 1:
            raise ValueError(f"Yinyuan ID has no single printable key token: {yinyuan_id}")
        if yinyuan_id in mapping:
            raise ValueError(f"Duplicate Yinyuan ID assignment: {yinyuan_id}")
        if key in occupied:
            raise ValueError(f"Duplicate layout key token {key!r}: {occupied[key]} and {yinyuan_id}")
        mapping[yinyuan_id] = key
        occupied[key] = yinyuan_id

    for owner, members in load_shared_layout_groups(layout).items():
        if owner not in mapping:
            raise ValueError(f"shared-key owner has no physical assignment: {owner}")
        key = mapping[owner]
        for member in members:
            if member == owner:
                continue
            if member in mapping:
                raise ValueError(f"shared-key member also has an independent slot: {member}")
            mapping[member] = key

    expected = expected_yinyuan_ids()
    if set(mapping) != expected:
        missing = sorted(expected - set(mapping))
        extra = sorted(set(mapping) - expected)
        raise ValueError(f"Canonical layout coverage mismatch: missing={missing}, extra={extra}")
    return mapping


def layout_projection_digest(repo_root: Path = REPO_ROOT) -> str:
    """Identify one physical layout without a hand-maintained version name."""
    mapping = load_yinyuan_id_to_layout_key(repo_root)
    serialized = json.dumps(
        sorted(mapping.items()),
        ensure_ascii=False,
        separators=(",", ":"),
    ).encode("utf-8")
    return hashlib.sha256(serialized).hexdigest()


def yinyuan_ids_to_layout_keys(
    yinyuan_ids: Iterable[str],
    *,
    repo_root: Path = REPO_ROOT,
    layout_path: Path | None = None,
) -> str:
    """Apply the final physical-key projection to an ID sequence."""
    layout = load_yinyuan_id_to_layout_key(repo_root, layout_path)
    result: list[str] = []
    for yinyuan_id in yinyuan_ids:
        try:
            result.append(layout[yinyuan_id])
        except KeyError as exc:
            raise ValueError(f"Yinyuan ID has no canonical layout key: {yinyuan_id}") from exc
    return "".join(result)


def symbol_code_to_layout_keys(
    code: str,
    *,
    repo_root: Path = REPO_ROOT,
    layout_path: Path | None = None,
) -> str:
    """Enforce symbol -> Yinyuan ID -> key; never symbol/Pinyin -> key directly."""
    return yinyuan_ids_to_layout_keys(
        symbol_code_to_yinyuan_ids(code, repo_root=repo_root),
        repo_root=repo_root,
        layout_path=layout_path,
    )
