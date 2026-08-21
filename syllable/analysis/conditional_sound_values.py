"""Validate the research-only conditional sound-value source model.

This module deliberately stops before runtime encoding.  It proves that the
current stable Yinyuan registries can be explained by their earlier pianyin
inventories and normalization rules, then validates the contract for future
contextual rules.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any


PROJECT_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_MODEL_PATH = (
    PROJECT_ROOT / "syllable" / "pianyin" / "conditional_sound_value_model.json"
)


@dataclass(frozen=True)
class ConditionalSoundValueAudit:
    model_id: str
    source_layer_count: int
    zaoyin_count: int
    zaoyin_registered_count: int
    yueyin_count: int
    zaoyin_realization_count: int
    yueyin_realization_count: int
    conditional_rule_count: int
    runtime_enabled: bool
    issues: tuple[str, ...]

    @property
    def passed(self) -> bool:
        return not self.issues

    def as_dict(self) -> dict[str, Any]:
        return {
            "model_id": self.model_id,
            "source_layer_count": self.source_layer_count,
            "zaoyin_count": self.zaoyin_count,
            "zaoyin_registered_count": self.zaoyin_registered_count,
            "yueyin_count": self.yueyin_count,
            "zaoyin_realization_count": self.zaoyin_realization_count,
            "yueyin_realization_count": self.yueyin_realization_count,
            "conditional_rule_count": self.conditional_rule_count,
            "runtime_enabled": self.runtime_enabled,
            "passed": self.passed,
            "issues": list(self.issues),
        }


def _load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        data = json.load(handle)
    if not isinstance(data, dict):
        raise ValueError(f"JSON 顶层必须是对象: {path}")
    return data


def _repo_path(project_root: Path, raw_path: str) -> Path:
    candidate = (project_root / raw_path).resolve()
    root = project_root.resolve()
    if candidate != root and root not in candidate.parents:
        raise ValueError(f"模型路径越出仓库: {raw_path}")
    return candidate


def _collect_zaoyin_realizations(source: dict[str, Any]) -> dict[str, list[str]]:
    entries = source.get("entries", {})
    if isinstance(entries, dict) and entries:
        return {
            str(label): [str(value) for value in entry.get("ipa", [])]
            for label, entry in entries.items()
            if isinstance(entry, dict)
        }

    # Legacy compatibility for external audit fixtures.  The production model
    # no longer uses pianyin_initial.json.
    groups = source.get("uncertain_pitch_pianyin", {})
    result: dict[str, list[str]] = {}
    for group in groups.values():
        if not isinstance(group, dict):
            continue
        for label, values in group.items():
            normalized = "'" if label == "''" else label
            result.setdefault(normalized, []).extend(str(value) for value in values)
    return result


def _normalized_yueyin_key(
    alias: str,
    quality_variables: dict[str, list[str]],
    pitch_variables: dict[str, Any],
) -> str:
    if len(alias) < 2:
        return ""
    quality, pitch = alias[:-1], alias[-1]
    quality_unit = next(
        (unit for unit, values in quality_variables.items() if quality in values),
        "",
    )
    if not quality_unit:
        return ""

    model = pitch_variables.get("mid_high_median_model", {})
    if pitch in model.get("H", []):
        normalized_pitch = pitch
    elif pitch in model.get("M", []):
        normalized_pitch = pitch
    elif pitch in model.get("L", []):
        normalized_pitch = model["L"][-1]
    else:
        return ""

    marks = pitch_variables.get("pitch_marks", {})
    mark_values = marks.get(normalized_pitch, [])
    if not mark_values:
        return ""
    return quality_unit + mark_values[0]


def _validate_rule_contract(
    rules: Any,
    known_ids: set[str],
    dimensions: set[str],
    operation_types: set[str],
) -> list[str]:
    if not isinstance(rules, list):
        return ["conditional_rules 必须是数组"]

    issues: list[str] = []
    seen: set[str] = set()
    for index, rule in enumerate(rules, start=1):
        if not isinstance(rule, dict):
            issues.append(f"条件规则第 {index} 项必须是对象")
            continue
        rule_id = str(rule.get("rule_id", ""))
        if not rule_id:
            issues.append(f"条件规则第 {index} 项缺少 rule_id")
        elif rule_id in seen:
            issues.append(f"重复的条件规则 ID: {rule_id}")
        seen.add(rule_id)

        if rule.get("activation") not in {"research_only", "deferred"}:
            issues.append(f"条件规则 {rule_id or index} 不得启用运行时")
        source_refs = rule.get("source_refs", [])
        if not isinstance(source_refs, list) or not source_refs:
            issues.append(f"条件规则 {rule_id or index} 必须有 source_refs")
        unknown_dimensions = set(rule.get("conditions", {})) - dimensions
        if unknown_dimensions:
            issues.append(
                f"条件规则 {rule_id or index} 使用未知条件维度: "
                + ", ".join(sorted(unknown_dimensions))
            )
        for operation in rule.get("operations", []):
            operation_type = operation.get("type")
            if operation_type not in operation_types:
                issues.append(
                    f"条件规则 {rule_id or index} 使用未知操作: {operation_type}"
                )
            for field in ("source_yinyuan_id", "target_yinyuan_id"):
                value = operation.get(field)
                if value and value not in known_ids:
                    issues.append(
                        f"条件规则 {rule_id or index} 引用未知 {field}: {value}"
                    )
            if operation.get("insert_positions") or operation.get("delete_positions"):
                issues.append(f"条件规则 {rule_id or index} 不得增删音元位置")
    return issues


def audit_conditional_sound_value_model(
    model_path: Path = DEFAULT_MODEL_PATH,
    project_root: Path = PROJECT_ROOT,
) -> ConditionalSoundValueAudit:
    model = _load_json(model_path)
    issues: list[str] = []

    if model.get("schema_version") != 1:
        issues.append("schema_version 必须为 1")
    runtime_enabled = bool(model.get("runtime_enabled"))
    if runtime_enabled:
        issues.append("准备阶段 runtime_enabled 必须为 false")

    sources = model.get("source_layers", {})
    registries = model.get("stable_registries", {})
    loaded_sources: dict[str, dict[str, Any]] = {}
    loaded_registries: dict[str, dict[str, Any]] = {}
    for collection_name, collection, output in (
        ("source_layers", sources, loaded_sources),
        ("stable_registries", registries, loaded_registries),
    ):
        if not isinstance(collection, dict):
            issues.append(f"{collection_name} 必须是对象")
            continue
        for name, record in collection.items():
            try:
                path = _repo_path(project_root, str(record["path"]))
                output[name] = _load_json(path)
            except (KeyError, OSError, ValueError, json.JSONDecodeError) as error:
                issues.append(f"无法读取 {collection_name}.{name}: {error}")

    zaoyin_entries = loaded_registries.get("zaoyin", {}).get("entries", {})
    yueyin_entries = loaded_registries.get("yueyin", {}).get("entries", {})
    zaoyin_source = loaded_sources.get("zaoyin_realizations", {})
    zaoyin_source_entries = zaoyin_source.get("entries", {})
    zaoyin_realizations = _collect_zaoyin_realizations(zaoyin_source)

    if isinstance(zaoyin_source_entries, dict) and zaoyin_source_entries:
        runtime_source_entries = {
            label: entry
            for label, entry in zaoyin_source_entries.items()
            if isinstance(entry, dict) and entry.get("activation") == "runtime_compatible"
        }
        source_runtime_ids = {
            str(entry.get("yinyuan_id", "")) for entry in runtime_source_entries.values()
        }
        registry_ids = {
            str(entry.get("yinyuan_id", "")) for entry in zaoyin_entries.values()
        }
        if source_runtime_ids != registry_ids:
            issues.append("结构化噪音真源的运行投影与稳定登记表 ID 集合不一致")
        registry_label_by_id = {
            str(entry.get("yinyuan_id", "")): label
            for label, entry in zaoyin_entries.items()
        }
        for label, entry in runtime_source_entries.items():
            yinyuan_id = str(entry.get("yinyuan_id", ""))
            if registry_label_by_id.get(yinyuan_id) != label:
                issues.append(f"噪音 {yinyuan_id} 的真源标签与稳定登记标签不一致")
    elif set(zaoyin_realizations) != set(zaoyin_entries):
        issues.append("旧噪音片音来源与稳定噪音登记表的标签集合不一致")

    variables = loaded_sources.get("yueyin_quality_and_pitch_classes", {})
    quality_variables = variables.get("quality_variables", {})
    pitch_variables = variables.get("pitch_variables", {})
    attested = set(loaded_sources.get("attested_yueyin_slices", {}))
    registered_aliases = {
        str(alias)
        for entry in yueyin_entries.values()
        for alias in entry.get("aliases", [])
    }
    if attested != registered_aliases:
        issues.append("pitched_pianyin 与稳定乐音登记表的别名集合不一致")
    for canonical, entry in yueyin_entries.items():
        for alias in entry.get("aliases", []):
            normalized = _normalized_yueyin_key(
                str(alias), quality_variables, pitch_variables
            )
            if normalized != canonical:
                issues.append(
                    f"乐音别名 {alias} 按上游归并规则得到 {normalized or '<无>'}，"
                    f"但登记在 {canonical}"
                )

    all_ids: list[str] = []
    source_yinyuan_ids = [
        str(entry.get("yinyuan_id", ""))
        for entry in zaoyin_source_entries.values()
        if isinstance(entry, dict)
    ] if isinstance(zaoyin_source_entries, dict) else []
    if source_yinyuan_ids:
        if any(not value.startswith("N") for value in source_yinyuan_ids):
            issues.append("结构化噪音真源存在非 N 前缀 Yinyuan ID")
        if len(source_yinyuan_ids) != len(set(source_yinyuan_ids)):
            issues.append("结构化噪音真源存在重复 Yinyuan ID")
        all_ids.extend(source_yinyuan_ids)
    else:
        all_ids.extend(
            str(entry.get("yinyuan_id", "")) for entry in zaoyin_entries.values()
        )

    for prefix, entries in (("N", zaoyin_entries), ("M", yueyin_entries)):
        for label, entry in entries.items():
            yinyuan_id = str(entry.get("yinyuan_id", ""))
            if not yinyuan_id.startswith(prefix):
                issues.append(f"稳定登记项 {label} 的 Yinyuan ID 非 {prefix} 前缀")
            if prefix == "M":
                all_ids.append(yinyuan_id)
    if len(all_ids) != len(set(all_ids)):
        issues.append("稳定登记表存在重复 Yinyuan ID")

    dimensions = set(model.get("condition_dimensions", []))
    operation_types = set(model.get("operation_types", {}))
    rules = model.get("conditional_rules", [])
    issues.extend(
        _validate_rule_contract(rules, set(all_ids), dimensions, operation_types)
    )

    return ConditionalSoundValueAudit(
        model_id=str(model.get("model_id", "")),
        source_layer_count=len(sources) if isinstance(sources, dict) else 0,
        zaoyin_count=len(zaoyin_realizations),
        zaoyin_registered_count=len(zaoyin_entries),
        yueyin_count=len(yueyin_entries),
        zaoyin_realization_count=sum(len(values) for values in zaoyin_realizations.values()),
        yueyin_realization_count=len(registered_aliases),
        conditional_rule_count=len(rules) if isinstance(rules, list) else 0,
        runtime_enabled=runtime_enabled,
        issues=tuple(issues),
    )
