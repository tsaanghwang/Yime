"""Rule-driven surface-class normalization for the research-only erhua draft."""

from __future__ import annotations

import copy
import json
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Mapping

from syllable.analysis.erhua_final_review import (
    SEGMENT_NAMES,
    SPLIT_REVIEW_VARIANTS,
    build_psc_result_group_index,
    review_variant_source_annotations,
    normalize_surface_segment,
    render_surface_segments,
)


def _read_json(path: Path) -> dict[str, Any]:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def _write_json(path: Path, payload: Mapping[str, Any]) -> None:
    rendered = json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
    temporary = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    temporary.write_text(rendered, encoding="utf-8", newline="\n")
    os.replace(temporary, path)


def _entries(payload: Mapping[str, Any]) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    for group in payload["finals"].values():
        for final, entry in group.items():
            if final in result:
                raise ValueError(f"草稿中的韵母键不唯一：{final}")
            result[str(final)] = entry
    return result


def _normalize_feature_template(value: object) -> dict[str, dict[str, bool]]:
    if not isinstance(value, Mapping) or set(value) != set(SEGMENT_NAMES):
        raise ValueError("儿化特征模板必须且只能包含呼音、主音、末音。")
    return {
        name: {
            "rhotic": bool((value[name] or {}).get("rhotic")),
            "nasalized": bool((value[name] or {}).get("nasalized")),
        }
        for name in SEGMENT_NAMES
    }


def load_surface_quality_profiles(path: Path) -> dict[str, Any]:
    payload = _read_json(path)
    if payload.get("runtime_enabled") is not False:
        raise ValueError("儿化音质附表必须保持 runtime_enabled=false。")
    profiles = payload.get("profiles")
    if not isinstance(profiles, dict) or not profiles:
        raise ValueError("儿化音质附表缺少 profiles。")
    for final, profile in profiles.items():
        expected = profile.get("expected_base_segments") or {}
        qualities = profile.get("surface_qualities") or {}
        if set(expected) != set(SEGMENT_NAMES) or set(qualities) != set(SEGMENT_NAMES):
            raise ValueError(f"{final} 的音质附表必须保持固定三段。")
        if any(not str(qualities[name]).strip() for name in SEGMENT_NAMES):
            raise ValueError(f"{final} 的儿化后三段音质不能留空。")
    return payload


def _surface_segments_for_member(
    rule: Mapping[str, Any],
    member: str,
    entry: Mapping[str, Any],
    quality_profiles: Mapping[str, Any],
) -> dict[str, dict[str, object]]:
    profile = quality_profiles.get(member)
    if not isinstance(profile, Mapping):
        raise ValueError(f"儿化音质附表缺少韵母：{member}")
    review = entry.get("three_segment_review") or {}
    actual_base = review.get("base_segments") or {}
    expected_base = profile.get("expected_base_segments") or {}
    if actual_base != expected_base:
        raise ValueError(
            f"{member} 的基础三段已变化：当前 {actual_base}，附表预期 {expected_base}；"
            "请先复核并更新音质附表。"
        )
    qualities = profile["surface_qualities"]
    features = rule["feature_template"]
    return {
        name: normalize_surface_segment(
            {"quality": str(qualities[name]), "features": features[name]}
        )
        for name in SEGMENT_NAMES
    }


def _source_results(entry: Mapping[str, Any]) -> set[str]:
    return {
        str(source.get("source_erhua_final"))
        for source in entry.get("erhua_final") or []
        if source.get("source_erhua_final")
    }


def _sync_split_review_variants(
    entry: dict[str, Any], parent_review: Mapping[str, Any]
) -> list[str]:
    """Materialize two independently editable apical-i review records."""

    variants = entry.setdefault("three_segment_review_variants", {})
    manual: list[str] = []
    for record_id, config in SPLIT_REVIEW_VARIANTS.items():
        existing = variants.get(config["variant_id"]) or {}
        if (existing.get("surface_generation") or {}).get("method") == "manual_override":
            manual.append(record_id)
            continue
        review = copy.deepcopy(parent_review)
        for field in ("decision", "note", "revision", "updated_utc"):
            if field in existing:
                review[field] = existing[field]
        review["base_segments"] = {
            name: str(config["base_quality"]) for name in SEGMENT_NAMES
        }
        source_annotations = review_variant_source_annotations(
            entry.get("erhua_final") or [], config
        )
        if len(source_annotations) != 1:
            raise ValueError(
                f"{record_id} 需要且只能匹配一条 PSC {config['source_base_final']} 记录。"
            )
        review["review_variant"] = {
            "variant_id": config["variant_id"],
            "record_id": record_id,
            "display_final": config["display_final"],
            "source_index": source_annotations[0].get("source_index"),
            "source_base_final": config["source_base_final"],
            "derivation": "按 PSC source_base_final 把规范韵母 _i 的舌尖前、舌尖后记录分列",
        }
        variants[config["variant_id"]] = review
    return manual


def load_surface_class_rules(path: Path) -> dict[str, Any]:
    payload = _read_json(path)
    if payload.get("runtime_enabled") is not False:
        raise ValueError("儿化表层类规则必须保持 runtime_enabled=false。")
    classes = payload.get("classes")
    if not isinstance(classes, dict) or not classes:
        raise ValueError("儿化表层类规则缺少 classes。")
    seen_members: dict[str, str] = {}
    for class_id, rule in classes.items():
        rule["feature_template"] = _normalize_feature_template(
            rule.get("feature_template")
        )
        members = [str(value) for value in rule.get("members") or []]
        if not members:
            raise ValueError(f"{class_id} 没有成员。")
        for member in members:
            if member in seen_members:
                raise ValueError(
                    f"韵母 {member} 同时属于 {seen_members[member]} 和 {class_id}。"
                )
            seen_members[member] = str(class_id)
    return payload


def apply_surface_class_rules(
    draft_path: Path,
    rules_path: Path,
    quality_profiles_path: Path,
    *,
    now: datetime | None = None,
) -> dict[str, Any]:
    draft_path = Path(draft_path)
    rules_path = Path(rules_path)
    draft = _read_json(draft_path)
    if draft.get("runtime_enabled") is not False:
        raise ValueError("儿化草稿必须保持 runtime_enabled=false。")
    rules = load_surface_class_rules(rules_path)
    quality_payload = load_surface_quality_profiles(quality_profiles_path)
    quality_profiles = quality_payload["profiles"]
    entries = _entries(draft)
    timestamp = (now or datetime.now(timezone.utc)).astimezone(timezone.utc)
    surface_changed: list[str] = []
    metadata_changed: list[str] = []
    stale_classifications_cleared: list[str] = []
    manual_overrides: list[str] = []
    rule_generated_members: list[str] = []
    unchanged: list[str] = []

    active_members = {
        str(member)
        for rule in rules["classes"].values()
        for member in rule["members"]
    }
    for final, entry in entries.items():
        if final in active_members:
            continue
        review = entry.get("three_segment_review") or {}
        cleared = entry.pop("erhua_surface_class", None) is not None
        for field in ("surface_class", "surface_class_rule_version"):
            if field in review:
                review.pop(field)
                cleared = True
        if cleared:
            stale_classifications_cleared.append(final)

    for class_id, rule in rules["classes"].items():
        expected_by_member = rule.get("source_results_by_member") or {}
        expected = {str(value) for value in rule.get("source_results") or []}
        aliases = rule.get("technical_aliases") or {}
        for member in rule["members"]:
            if member not in entries:
                raise ValueError(f"{class_id} 的成员不存在：{member}")
            entry = entries[member]
            member_expected = {
                str(value) for value in expected_by_member.get(member, expected)
            }
            actual = _source_results(entry)
            expected_nasalized = any(
                bool(features["nasalized"])
                for features in rule["feature_template"].values()
            )
            actual_nasalized = {
                bool(source.get("nasalized"))
                for source in entry.get("erhua_final") or []
                if source.get("source_erhua_final")
            }
            if actual != member_expected:
                raise ValueError(
                    f"{class_id}/{member} 的来源儿化结果为 {sorted(actual)}，"
                    f"与规则 {sorted(member_expected)} 不一致。"
                )
            if actual_nasalized != {expected_nasalized}:
                raise ValueError(
                    f"{class_id}/{member} 的 PSC 鼻化类别为 {sorted(actual_nasalized)}，"
                    f"与规则 {expected_nasalized} 不一致。"
                )
            review = entry.get("three_segment_review") or {}
            if int(review.get("schema_version") or 0) != 2:
                raise ValueError(f"{member} 尚未迁移到 structured segment schema。")
            aliases = rule.get("technical_aliases") or {}
            desired_entry_class = {
                "class_id": class_id,
                "rule_version": int(rules["schema_version"]),
                "basis": str(rule.get("basis") or ""),
                "technical_alias_of": str(aliases.get(member) or ""),
                "runtime_enabled": False,
            }
            if (review.get("surface_generation") or {}).get("method") == "manual_override":
                entry["erhua_surface_class"] = {
                    **desired_entry_class,
                    "manual_override": True,
                }
                manual_overrides.append(member)
                continue
            normalized = _surface_segments_for_member(
                rule, member, entry, quality_profiles
            )
            desired_ipa = render_surface_segments(normalized)
            desired_fields = {
                "surface_segments": normalized,
                "surface_ipa": desired_ipa,
                "surface_class": class_id,
                "surface_class_rule_version": int(rules["schema_version"]),
                "surface_generation": {
                    "method": "rule_generated",
                    "class_id": class_id,
                    "rule_version": int(rules["schema_version"]),
                    "quality_profile_version": int(quality_payload["schema_version"]),
                    "quality_profile_source": "external_data/tmp/erhua_surface_quality_profiles.json",
                    "runtime_enabled": False,
                },
            }
            surface_differs = any(
                review.get(key) != value
                for key, value in desired_fields.items()
                if key in {"surface_segments", "surface_ipa"}
            )
            metadata_differs = any(
                review.get(key) != value
                for key, value in desired_fields.items()
                if key in {"surface_class", "surface_class_rule_version", "surface_generation"}
            )
            entry_metadata_differs = entry.get("erhua_surface_class") != desired_entry_class
            review.update(desired_fields)
            entry["erhua_surface_class"] = desired_entry_class
            if member == "_i":
                manual_overrides.extend(
                    _sync_split_review_variants(entry, review)
                )
            rule_generated_members.append(member)
            if surface_differs:
                review["revision"] = int(review.get("revision") or 0) + 1
                review["updated_utc"] = timestamp.isoformat().replace("+00:00", "Z")
                surface_changed.append(member)
            elif metadata_differs or entry_metadata_differs:
                metadata_changed.append(member)
            else:
                unchanged.append(member)

    draft["erhua_surface_class_model"] = {
        "schema_version": int(rules["schema_version"]),
        "status": "research_draft_only",
        "rules_source": "external_data/tmp/erhua_surface_class_rules.json",
        "quality_profiles_source": "external_data/tmp/erhua_surface_quality_profiles.json",
        "class_count": len(rules["classes"]),
        "member_count": sum(len(rule["members"]) for rule in rules["classes"].values()),
        "policy": str(rules.get("policy") or ""),
        "runtime_enabled": False,
    }
    draft["psc_result_group_index"] = {
        "schema_version": 1,
        "derivation": "由 PSC source_erhua_final、nasalized 与既有韵母对齐结果派生；外部表仅作事后核对，不参与生成",
        "groups": build_psc_result_group_index(draft),
        "runtime_enabled": False,
    }
    foundation_sync = draft.get("draft_foundation_sync") or {}
    required = list(foundation_sync.get("surface_review_required") or [])
    if required:
        foundation_sync["surface_review_required"] = [
            final for final in required if final not in rule_generated_members
        ]
        draft["draft_foundation_sync"] = foundation_sync
    refresh = draft.setdefault("draft_refresh", {})
    refresh.update(
        {
            "updated_utc": timestamp.isoformat().replace("+00:00", "Z"),
            "surface_class_rules_applied": True,
            "review_decisions_changed": False,
            "formal_final_styles_changed": False,
            "runtime_artifacts_changed": False,
        }
    )
    _write_json(draft_path, draft)
    return {
        "class_count": len(rules["classes"]),
        "changed_members": surface_changed + metadata_changed,
        "surface_changed_members": surface_changed,
        "metadata_changed_members": metadata_changed,
        "stale_classifications_cleared": stale_classifications_cleared,
        "unchanged_members": unchanged,
        "manual_overrides": manual_overrides,
    }


def audit_surface_classes(
    draft_path: Path, rules_path: Path, quality_profiles_path: Path
) -> dict[str, Any]:
    draft = _read_json(draft_path)
    rules = load_surface_class_rules(rules_path)
    quality_profiles = load_surface_quality_profiles(quality_profiles_path)["profiles"]
    entries = _entries(draft)
    mismatches: list[str] = []
    manual_overrides: list[str] = []
    class_rows: dict[str, dict[str, Any]] = {}
    for class_id, rule in rules["classes"].items():
        members = []
        member_surfaces: dict[str, str] = {}
        for member in rule["members"]:
            template = _surface_segments_for_member(
                rule, member, entries[member], quality_profiles
            )
            expected_ipa = render_surface_segments(template)
            review = entries[member].get("three_segment_review") or {}
            if (review.get("surface_generation") or {}).get("method") == "manual_override":
                manual_overrides.append(member)
                members.append(member)
                member_surfaces[member] = expected_ipa
                continue
            if (
                review.get("surface_class") != class_id
                or review.get("surface_segments") != template
                or review.get("surface_ipa") != expected_ipa
            ):
                mismatches.append(member)
            members.append(member)
            member_surfaces[member] = expected_ipa
        unique_surfaces = list(dict.fromkeys(member_surfaces.values()))
        class_row = {
            "members": members,
            "surface_ipa": unique_surfaces[0] if len(unique_surfaces) == 1 else "按成员基础主音派生",
            "surface_yime": (
                render_surface_segments(template, notation="yime_combining_r")
                if len(unique_surfaces) == 1
                else "按成员基础主音派生"
            ),
        }
        if len(unique_surfaces) != 1:
            class_row["member_surfaces"] = member_surfaces
        class_rows[class_id] = class_row
    return {
        "mismatches": mismatches,
        "manual_overrides": manual_overrides,
        "classes": class_rows,
    }


__all__ = [
    "apply_surface_class_rules",
    "audit_surface_classes",
    "load_surface_class_rules",
    "load_surface_quality_profiles",
]
