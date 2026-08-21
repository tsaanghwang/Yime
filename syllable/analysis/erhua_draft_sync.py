"""Non-destructively synchronize the research erhua draft foundations."""

from __future__ import annotations

from copy import deepcopy
from dataclasses import dataclass
from datetime import datetime, timezone
import json
import os
from pathlib import Path
from typing import Any, Mapping

from syllable.analysis.erhua_final_review import (
    SEGMENT_NAMES,
    ErhuaFinalDraftStore,
)


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DRAFT_PATH = ROOT / "external_data" / "tmp" / "final_styles_erhua_draft.json"
DEFAULT_FINAL_STYLES_PATH = ROOT / "syllable" / "yinyuan" / "final_styles.json"
DEFAULT_DECOMPOSITION_PATH = (
    ROOT
    / "internal_data"
    / "yinyuan_derived"
    / "ganyin_to_pianyin_sequence.json"
)


@dataclass(frozen=True)
class ErhuaDraftSyncResult:
    actual_count: int
    added: tuple[str, ...]
    archived: tuple[str, ...]
    moved_categories: tuple[str, ...]
    ipa_changed: tuple[str, ...]
    base_segments_changed: tuple[str, ...]
    surface_review_required: tuple[str, ...]
    changed: bool


def _read_json(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError(f"JSON 根节点必须是对象：{path}")
    return payload


def _write_json_atomic(path: Path, payload: Mapping[str, Any]) -> None:
    rendered = json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
    temporary = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    temporary.write_text(rendered, encoding="utf-8", newline="\n")
    os.replace(temporary, path)


def _flatten_entries(payload: Mapping[str, Any]) -> dict[str, tuple[str, dict[str, Any]]]:
    groups = payload.get("finals")
    if not isinstance(groups, Mapping):
        raise ValueError("儿化草稿缺少 finals 对象。")
    flattened: dict[str, tuple[str, dict[str, Any]]] = {}
    for category, group in groups.items():
        if not isinstance(group, Mapping):
            raise ValueError(f"儿化草稿分类 {category!r} 必须是对象。")
        for final, entry in group.items():
            if final in flattened:
                raise ValueError(f"儿化草稿中的韵母键重复：{final}")
            if not isinstance(entry, dict):
                raise ValueError(f"儿化草稿条目 {final!r} 必须是对象。")
            flattened[str(final)] = (str(category), entry)
    return flattened


def _load_final_styles(path: Path) -> list[tuple[str, str, str]]:
    payload = _read_json(path)
    groups = payload.get("finals")
    if not isinstance(groups, Mapping):
        raise ValueError(f"韵母分类视图缺少 finals 对象：{path}")
    rows: list[tuple[str, str, str]] = []
    seen: set[str] = set()
    for category, group in groups.items():
        if not isinstance(group, Mapping):
            raise ValueError(f"韵母分类 {category!r} 必须是对象。")
        for final, value in group.items():
            if final in seen:
                raise ValueError(f"韵母分类视图中的键重复：{final}")
            if not isinstance(value, Mapping) or not str(value.get("ipa") or ""):
                raise ValueError(f"韵母 {final!r} 缺少 IPA。")
            seen.add(str(final))
            rows.append((str(category), str(final), str(value["ipa"])))
    return rows


def _new_entry(final: str, ipa: str) -> dict[str, Any]:
    return {
        "ipa": ipa,
        "erhua_final": [],
        "erhua_review_status": "no_psc_source_pending_review",
        "erhua_note": (
            f"韵母 {final} 由现行韵母主表同步加入；尚无已对齐的 PSC 儿化类别，"
            "等待人工决定是否适用。"
        ),
    }


def _base_foundation(
    final: str,
    ipa: str,
    segment_map: Mapping[str, tuple[str, dict[str, str]]],
) -> dict[str, Any]:
    if final not in segment_map:
        raise ValueError(f"三段分解产物中找不到韵母：{final}")
    ganyin, segments = segment_map[final]
    return {
        "schema_version": 1,
        "ipa_source": "external_data/finals_IPA_mapping.json",
        "segments_source": (
            "internal_data/yinyuan_derived/ganyin_to_pianyin_sequence.json"
        ),
        "final": final,
        "ganyin": ganyin,
        "ipa": ipa,
        "segments": {name: str(segments[name]) for name in SEGMENT_NAMES},
    }


def sync_erhua_draft_foundations(
    *,
    draft_path: Path = DEFAULT_DRAFT_PATH,
    final_styles_path: Path = DEFAULT_FINAL_STYLES_PATH,
    decomposition_path: Path = DEFAULT_DECOMPOSITION_PATH,
    write: bool = True,
    now: datetime | None = None,
) -> ErhuaDraftSyncResult:
    """Refresh only canonical foundations while preserving manual erhua work."""

    original = _read_json(draft_path)
    if original.get("runtime_enabled") is not False:
        raise ValueError("儿化草稿必须保持 runtime_enabled=false。")
    payload = deepcopy(original)
    existing = _flatten_entries(payload)
    rows = _load_final_styles(final_styles_path)
    actual = {final for _category, final, _ipa in rows}

    store = ErhuaFinalDraftStore(draft_path, decomposition_path)
    segment_map = store.segment_map

    added: list[str] = []
    moved: list[str] = []
    ipa_changed: list[str] = []
    base_changed: list[str] = []
    review_required: list[str] = []
    previously_required = set(
        (payload.get("draft_foundation_sync") or {}).get(
            "surface_review_required", []
        )
    )
    rebuilt_groups: dict[str, dict[str, Any]] = {}

    for category, final, ipa in rows:
        old_category, old_entry = existing.get(final, ("", _new_entry(final, ipa)))
        entry = deepcopy(old_entry)
        if not old_category:
            added.append(final)
        elif old_category != category:
            moved.append(final)

        previous_ipa = str(entry.get("ipa") or "")
        if previous_ipa != ipa:
            ipa_changed.append(final)
        entry["ipa"] = ipa

        foundation = _base_foundation(final, ipa, segment_map)
        previous_foundation = entry.get("base_foundation") or {}
        previous_segments = previous_foundation.get("segments")
        review = entry.get("three_segment_review") or {}
        if not previous_segments and review:
            previous_segments = review.get("base_segments")
        if previous_segments != foundation["segments"]:
            base_changed.append(final)

        entry["base_foundation"] = foundation
        if review:
            review["base_segments_source"] = foundation["segments_source"]
            review["base_segments_final"] = final
            review["base_segments_ganyin"] = foundation["ganyin"]
            review["base_segments"] = deepcopy(foundation["segments"])
            if (
                str(review.get("decision") or "") == "reviewed"
                and (previous_ipa != ipa or previous_segments != foundation["segments"])
            ):
                review_required.append(final)

        rebuilt_groups.setdefault(category, {})[final] = entry

    archived = sorted(set(existing) - actual)
    archive_payload = deepcopy(payload.get("archived_final_entries") or {})
    for final in archived:
        category, entry = existing[final]
        archive_payload[final] = {
            "former_category": category,
            "reason": "不再存在于当前 42 韵母主表；为避免数据丢失移出活动草稿。",
            "entry": deepcopy(entry),
        }

    payload["derived_from"] = "external_data/finals_IPA_mapping.json"
    payload["finals"] = rebuilt_groups
    if archive_payload:
        payload["archived_final_entries"] = archive_payload
    payload.setdefault("review_summary", {})["project_final_count"] = len(rows)

    pending_review = [
        final
        for _category, final, _ipa in rows
        if final in previously_required or final in review_required
    ]
    changed = payload != original
    if changed:
        timestamp = (now or datetime.now(timezone.utc)).astimezone(timezone.utc)
        timestamp_text = timestamp.isoformat().replace("+00:00", "Z")
        payload["draft_foundation_sync"] = {
            "schema_version": 1,
            "updated_utc": timestamp_text,
            "ipa_source": "external_data/finals_IPA_mapping.json",
            "classification_source": "syllable/yinyuan/final_styles.json",
            "segments_source": (
                "internal_data/yinyuan_derived/ganyin_to_pianyin_sequence.json"
            ),
            "active_final_count": len(rows),
            "added": added,
            "archived": archived,
            "moved_categories": moved,
            "ipa_changed": ipa_changed,
            "base_segments_changed": base_changed,
            "surface_review_required": pending_review,
            "manual_surface_decisions_changed": False,
            "runtime_artifacts_changed": False,
        }
        refresh = payload.setdefault("draft_refresh", {})
        refresh.update(
            {
                "updated_utc": timestamp_text,
                "base_foundations_synchronized": True,
                "review_decisions_changed": False,
                "runtime_artifacts_changed": False,
            }
        )
        counts: dict[str, int] = {
            "pending": 0,
            "reviewed": 0,
            "deferred": 0,
            "not_applicable": 0,
        }
        for group in rebuilt_groups.values():
            for entry in group.values():
                decision = str(
                    (entry.get("three_segment_review") or {}).get("decision")
                    or "pending"
                )
                counts[decision] = counts.get(decision, 0) + 1
        payload["three_segment_review_progress"] = {
            "schema_version": 1,
            "total": len(rows),
            **counts,
            "runtime_aliases_generated": 0,
            "updated_utc": timestamp_text,
        }
        if write:
            _write_json_atomic(draft_path, payload)

    return ErhuaDraftSyncResult(
        actual_count=len(rows),
        added=tuple(added),
        archived=tuple(archived),
        moved_categories=tuple(moved),
        ipa_changed=tuple(ipa_changed),
        base_segments_changed=tuple(base_changed),
        surface_review_required=tuple(pending_review),
        changed=changed,
    )


__all__ = [
    "DEFAULT_DECOMPOSITION_PATH",
    "DEFAULT_DRAFT_PATH",
    "DEFAULT_FINAL_STYLES_PATH",
    "ErhuaDraftSyncResult",
    "sync_erhua_draft_foundations",
]
