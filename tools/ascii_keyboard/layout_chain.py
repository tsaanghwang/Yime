"""Canonical bridge from numeric-tone Pinyin to Yinyuan IDs and layout keys.

Keyboard layout code must consume this module instead of inventing a direct
Pinyin-to-key mapping.  The semantic chain ends at Yinyuan IDs; physical keys
are a separate, final projection.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any, Iterable, cast

from yime.utils.yinyuan_id_chain import (
    expected_yinyuan_ids, load_semantic_yinyuan_registry,
    load_symbol_to_yinyuan_id, symbol_code_to_yinyuan_ids,
    encode_numeric_pinyin_to_yinyuan_ids,
)


REPO_ROOT = Path(__file__).resolve().parents[2]
CANONICAL_LAYOUT_SOURCE = Path("prototypes/touch-terminal/encoding/manual_key_layout.json")
CONTROLLED_SHARED_LAYOUT_GROUPS: set[frozenset[str]] = set()
ERHUA_SOUND_SOURCE = Path("docs/project/connected_speech/erhua_sound_key_projection.json")


def load_erhua_input_registry(repo_root: Path = REPO_ROOT) -> dict[str, dict[str, Any]]:
    """Existing reviewed derived units, not additions to the canonical 60 IDs."""
    payload = _load_json(repo_root / ERHUA_SOUND_SOURCE)
    registry = {str(unit["sound_unit_id"]): unit for unit in payload["sound_units"]
                if str(unit["sound_unit_id"]).startswith("R")}
    if set(registry) != {f"R{index:02d}" for index in range(4, 19)}:
        raise ValueError("Reviewed derived Erhua registry must cover R04-R18")
    return registry


def load_shared_layout_groups(layout: dict[str, Any]) -> dict[str, tuple[str, ...]]:
    """Return owner -> members for the reviewed many-ID-to-one-key groups."""
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
        raise ValueError("canonical layout must declare the reviewed shared-key groups")
    return groups


class DisabledYinyuanError(ValueError):
    """A complete semantic input contains an explicitly disabled layout ID."""


def load_disabled_yinyuan_ids(repo_root: Path = REPO_ROOT) -> frozenset[str]:
    layout = _load_json(repo_root / CANONICAL_LAYOUT_SOURCE)
    raw = layout.get("disabled_yinyuan_ids", [])
    if not isinstance(raw, list) or any(not isinstance(item, str) for item in raw):
        raise ValueError("disabled_yinyuan_ids must be an array of stable IDs")
    if len(set(raw)) != len(raw) or set(raw) - expected_yinyuan_ids():
        raise ValueError("disabled_yinyuan_ids contains duplicate or unknown IDs")
    disabled = frozenset(raw)
    for owner in load_shared_layout_groups(layout):
        if owner in disabled:
            raise ValueError(f"shared-key owner cannot be disabled: {owner}")
    return disabled


def require_enabled_yinyuan_ids(
    yinyuan_ids: Iterable[str], *, repo_root: Path = REPO_ROOT,
) -> tuple[str, ...]:
    """Gate a FULL semantic tuple before any variable/shorthand shortening."""
    ids = tuple(yinyuan_ids)
    unknown = set(ids) - expected_yinyuan_ids()
    if unknown:
        raise ValueError(f"Unknown Yinyuan IDs: {sorted(unknown)}")
    disabled = set(ids) & load_disabled_yinyuan_ids(repo_root)
    if disabled:
        raise DisabledYinyuanError(f"Disabled Yinyuan IDs: {sorted(disabled)}")
    return ids


def load_active_yinyuan_id_to_layout_key(repo_root: Path = REPO_ROOT) -> dict[str, str]:
    disabled = load_disabled_yinyuan_ids(repo_root)
    return {key: value for key, value in load_yinyuan_id_to_layout_key(repo_root).items()
            if key not in disabled}


def _load_json(path: Path) -> dict[str, Any]:
    return cast(dict[str, Any], json.loads(path.read_text(encoding="utf-8")))


def load_input_id_to_layout_key(
    repo_root: Path = REPO_ROOT,
    layout_path: Path | None = None,
) -> dict[str, str]:
    """Load all 75 input carriers from the sole editable layout projection."""
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
    if layout.get("input_id_aliases") != {"R01": "M22", "R02": "M23", "R03": "M24"}:
        raise ValueError("R01-R03 must remain display aliases of M22-M24, not independent sound units")

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
        if len(key) != 1 or not (0x21 <= ord(key) <= 0x7e):
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

    expected = expected_yinyuan_ids() | set(load_erhua_input_registry(repo_root))
    if set(mapping) != expected:
        missing = sorted(expected - set(mapping))
        extra = sorted(set(mapping) - expected)
        raise ValueError(f"Canonical layout coverage mismatch: missing={missing}, extra={extra}")
    return mapping


def load_yinyuan_id_to_layout_key(
    repo_root: Path = REPO_ROOT, layout_path: Path | None = None,
) -> dict[str, str]:
    """Project only the unchanged 60-ID canonical syllable inventory."""
    return {identifier: key for identifier, key in
            load_input_id_to_layout_key(repo_root, layout_path).items()
            if identifier in expected_yinyuan_ids()}


def load_erhua_id_to_layout_key(repo_root: Path = REPO_ROOT) -> dict[str, str]:
    registry = load_erhua_input_registry(repo_root)
    return {identifier: key for identifier, key in load_input_id_to_layout_key(repo_root).items()
            if identifier in registry}


def load_erhua_key_class_to_layout_key(repo_root: Path = REPO_ROOT) -> dict[str, str]:
    """All 18 reviewed classes, including the existing M22-M24 carriers."""
    mapping = load_input_id_to_layout_key(repo_root)
    units = _load_json(repo_root / ERHUA_SOUND_SOURCE)["sound_units"]
    return {str(unit["key_class_id"]): mapping[str(unit["sound_unit_id"])] for unit in units}


def layout_projection_digest(repo_root: Path = REPO_ROOT) -> str:
    """Identify one physical layout without a hand-maintained version name."""
    mapping = load_input_id_to_layout_key(repo_root)
    serialized = json.dumps(
        {"mapping": sorted(mapping.items()),
         "disabled_yinyuan_ids": sorted(load_disabled_yinyuan_ids(repo_root))},
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
    for yinyuan_id in require_enabled_yinyuan_ids(yinyuan_ids, repo_root=repo_root):
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
