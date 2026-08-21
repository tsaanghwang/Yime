"""Synchronize the attested final inventory with its canonical IPA registry."""

from __future__ import annotations

from dataclasses import dataclass
import json
import os
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_GANYIN_PATH = ROOT / "syllable" / "yinyuan" / "ganyin.json"
DEFAULT_REGISTRY_PATH = ROOT / "external_data" / "finals_IPA_mapping.json"
DEFAULT_FINAL_STYLES_PATH = ROOT / "syllable" / "yinyuan" / "final_styles.json"

SCHEMA_VERSION = 2
PLACEHOLDER_IPA = "__TODO_IPA__"

CATEGORY_TO_STYLE = {
    "single quality ganyin": "single quality finals",
    "front long ganyin": "front long finals",
    "back long ganyin": "back long finals",
    "triple quality ganyin": "triple quality finals",
}


@dataclass(frozen=True)
class FinalIpaSyncResult:
    actual_count: int
    added: tuple[str, ...]
    removed: tuple[str, ...]
    placeholders: tuple[str, ...]
    migrated_legacy_schema: bool
    registry_changed: bool
    final_styles_changed: bool

    @property
    def synchronized(self) -> bool:
        return not self.added and not self.removed and not self.placeholders


def _read_json(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError(f"JSON 根节点必须是对象：{path}")
    return payload


def _write_json_atomic(path: Path, payload: dict[str, Any]) -> bool:
    text = json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
    if path.exists() and path.read_text(encoding="utf-8") == text:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    temporary.write_text(text, encoding="utf-8")
    os.replace(temporary, path)
    return True


def collect_attested_finals(
    ganyin_path: Path = DEFAULT_GANYIN_PATH,
) -> dict[str, list[str]]:
    """Return actual final bases grouped by the current ganyin categories."""
    payload = _read_json(ganyin_path)
    groups = payload.get("ganyin", payload)
    if not isinstance(groups, dict):
        raise ValueError(f"干音清单缺少 ganyin 对象：{ganyin_path}")

    result: dict[str, list[str]] = {}
    seen: set[str] = set()
    for category, entries in groups.items():
        if category not in CATEGORY_TO_STYLE or not isinstance(entries, dict):
            continue
        finals: list[str] = []
        for ganyin in entries:
            final = ganyin[:-1] if ganyin and ganyin[-1].isdigit() else ganyin
            if final and final not in seen:
                seen.add(final)
                finals.append(final)
        result[category] = finals

    missing_categories = set(CATEGORY_TO_STYLE) - set(result)
    if missing_categories:
        raise ValueError(f"干音清单缺少分类：{sorted(missing_categories)}")
    return result


def _normalize_legacy_final(ipa: str, legacy_final: str) -> str:
    normalized = legacy_final.replace("ɑ", "a").replace("ɡ", "g")
    if normalized == "i" and ipa in {"ɿ", "ʅ"}:
        return "_i"
    return {"iu": "iou", "ui": "uei", "un": "uen"}.get(normalized, normalized)


def _load_legacy_mapping(payload: dict[str, Any]) -> dict[str, str]:
    collected: dict[str, list[str]] = {}
    for ipa, legacy_final in payload.items():
        if not isinstance(ipa, str) or not isinstance(legacy_final, str):
            raise ValueError("旧版韵母 IPA 表必须是 IPA 到韵母的字符串映射")
        final = _normalize_legacy_final(ipa, legacy_final)
        collected.setdefault(final, []).append(ipa)

    mapping: dict[str, str] = {}
    for final, values in collected.items():
        unique = list(dict.fromkeys(values))
        if final == "_i" and set(unique) == {"ɿ", "ʅ"}:
            mapping[final] = "ɿ/ʅ"
        elif len(unique) == 1:
            mapping[final] = unique[0]
        else:
            raise ValueError(f"旧版 IPA 表中韵母 {final!r} 对应多个不兼容值：{unique}")
    return mapping


def load_final_ipa_mapping(
    registry_path: Path = DEFAULT_REGISTRY_PATH,
) -> tuple[dict[str, str], bool]:
    """Load final -> IPA data; legacy IPA -> final files are migrated in memory."""
    payload = _read_json(registry_path)
    if payload.get("mapping_direction") == "final_to_ipa":
        finals = payload.get("finals")
        if not isinstance(finals, dict):
            raise ValueError(f"韵母 IPA 主表缺少 finals 对象：{registry_path}")
        mapping: dict[str, str] = {}
        for final, ipa in finals.items():
            if not isinstance(final, str) or not isinstance(ipa, str) or not ipa:
                raise ValueError(f"韵母 IPA 主表存在无效记录：{final!r} -> {ipa!r}")
            mapping[final] = ipa
        return mapping, False
    return _load_legacy_mapping(payload), True


def _registry_payload(mapping: dict[str, str]) -> dict[str, Any]:
    return {
        "schema_version": SCHEMA_VERSION,
        "mapping_direction": "final_to_ipa",
        "description": "当前实例化韵母到无调 IPA 音质基形的唯一人工维护主表。",
        "placeholder_ipa": PLACEHOLDER_IPA,
        "finals": mapping,
    }


def _final_styles_payload(
    categorized_finals: dict[str, list[str]],
    mapping: dict[str, str],
) -> dict[str, Any]:
    return {
        "generated_from": "external_data/finals_IPA_mapping.json",
        "finals": {
            CATEGORY_TO_STYLE[category]: {
                final: {"ipa": mapping[final]}
                for final in finals
            }
            for category, finals in categorized_finals.items()
        },
    }


def sync_final_ipa_registry(
    *,
    ganyin_path: Path = DEFAULT_GANYIN_PATH,
    registry_path: Path = DEFAULT_REGISTRY_PATH,
    final_styles_path: Path = DEFAULT_FINAL_STYLES_PATH,
    write: bool = True,
) -> FinalIpaSyncResult:
    """Reconcile the editable IPA registry with the current attested finals."""
    categorized = collect_attested_finals(ganyin_path)
    actual_order = [final for finals in categorized.values() for final in finals]
    actual = set(actual_order)
    existing, migrated = load_final_ipa_mapping(registry_path)

    added = tuple(final for final in actual_order if final not in existing)
    removed = tuple(sorted(set(existing) - actual))
    synchronized_mapping = {
        final: existing.get(final, PLACEHOLDER_IPA)
        for final in actual_order
    }
    placeholders = tuple(
        final for final, ipa in synchronized_mapping.items() if ipa == PLACEHOLDER_IPA
    )

    registry_payload = _registry_payload(synchronized_mapping)
    final_styles_payload = _final_styles_payload(categorized, synchronized_mapping)
    registry_changed = False
    final_styles_changed = False
    if write:
        registry_changed = _write_json_atomic(registry_path, registry_payload)
        final_styles_changed = _write_json_atomic(final_styles_path, final_styles_payload)
    else:
        registry_changed = _read_json(registry_path) != registry_payload
        final_styles_changed = (
            not final_styles_path.exists()
            or _read_json(final_styles_path) != final_styles_payload
        )

    return FinalIpaSyncResult(
        actual_count=len(actual),
        added=added,
        removed=removed,
        placeholders=placeholders,
        migrated_legacy_schema=migrated,
        registry_changed=registry_changed,
        final_styles_changed=final_styles_changed,
    )


def require_complete_final_ipa_registry(result: FinalIpaSyncResult) -> None:
    if result.placeholders:
        joined = "、".join(result.placeholders)
        raise ValueError(
            f"这些新韵母尚未填写 IPA：{joined}；请编辑 external_data/finals_IPA_mapping.json"
        )


__all__ = [
    "DEFAULT_FINAL_STYLES_PATH",
    "DEFAULT_GANYIN_PATH",
    "DEFAULT_REGISTRY_PATH",
    "FinalIpaSyncResult",
    "PLACEHOLDER_IPA",
    "collect_attested_finals",
    "load_final_ipa_mapping",
    "require_complete_final_ipa_registry",
    "sync_final_ipa_registry",
]
