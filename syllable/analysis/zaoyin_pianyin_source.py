"""Load and validate the structured zaoyin-pianyin source.

The source describes phonetic/orthographic analysis.  The enhanced registry
owns stable Yinyuan IDs and runtime characters.  Contextual entries may be
registered without enabling any productive connected-speech rule.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any


PROJECT_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SOURCE_PATH = PROJECT_ROOT / "syllable" / "pianyin" / "zaoyin_pianyin.json"
DEFAULT_REGISTRY_PATH = (
    PROJECT_ROOT / "syllable" / "yinyuan" / "zaoyin_yinyuan_enhanced.json"
)
DEFAULT_PUA_PROJECTION_PATH = PROJECT_ROOT / "internal_data" / "bmp_pua_trial_projection.json"

CANONICAL_INITIALS = {
    "b", "p", "m", "f", "d", "t", "n", "l", "g", "k", "h",
    "j", "q", "x", "zh", "ch", "sh", "r", "z", "c", "s",
}
REQUIRED_DEFERRED_IDS: set[str] = set()
ALLOWED_ACTIVATIONS = {"runtime_compatible", "research_only"}
EXPECTED_MEMORY_GROUPS = (
    ("b", "p", "f", "m"),
    ("d", "t", "l", "n"),
    ("g", "k", "h", "ŋ"),
    ("z", "c", "s", "a_apical"),
    ("zh", "ch", "sh", "r"),
    ("j", "q", "x", "y"),
    ("'", "w", "ɥ"),
)
EXPECTED_A_APICAL_REALIZATIONS = [
    {
        "when": {"left_surface_final": ["ɿ"]},
        "surface_forms": ["ɹa", "za"],
    }
]
EXPECTED_VIRTUAL_INITIAL_DESCRIPTIONS = {
    "'": "舌位为非高的乐音前的虚首音",
    "w": "音质为 [u] 的高乐音前的虚首音",
    "ɥ": "音质为 [y] 的高乐音前的虚首音",
}
EXPECTED_VIRTUAL_INITIAL_LABELS = {"'", "y", "w", "ɥ"}


@dataclass(frozen=True)
class ZaoyinPianyinAudit:
    entry_count: int
    articulatory_group_count: int
    memory_sequence_count: int
    runtime_entry_count: int
    deferred_entry_count: int
    compatibility_alias_count: int
    issues: tuple[str, ...]

    @property
    def passed(self) -> bool:
        return not self.issues

    def as_dict(self) -> dict[str, Any]:
        return {
            "entry_count": self.entry_count,
            "articulatory_group_count": self.articulatory_group_count,
            "memory_sequence_count": self.memory_sequence_count,
            "runtime_entry_count": self.runtime_entry_count,
            "deferred_entry_count": self.deferred_entry_count,
            "compatibility_alias_count": self.compatibility_alias_count,
            "passed": self.passed,
            "issues": list(self.issues),
        }


def _load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        payload = json.load(handle)
    if not isinstance(payload, dict):
        raise ValueError(f"JSON 顶层必须是对象: {path}")
    return payload


def load_zaoyin_pianyin_source(path: Path = DEFAULT_SOURCE_PATH) -> dict[str, Any]:
    return _load_json(path)


def _registry_by_id(registry: dict[str, Any]) -> dict[str, tuple[str, dict[str, Any]]]:
    return {
        str(entry.get("yinyuan_id", "")): (label, entry)
        for label, entry in registry.get("entries", {}).items()
        if isinstance(entry, dict)
    }


def audit_zaoyin_pianyin_source(
    source_path: Path = DEFAULT_SOURCE_PATH,
    registry_path: Path = DEFAULT_REGISTRY_PATH,
) -> ZaoyinPianyinAudit:
    source = _load_json(source_path)
    registry = _load_json(registry_path)
    issues: list[str] = []

    if source.get("schema_version") != 1:
        issues.append("schema_version 必须为 1")
    if source.get("runtime_enabled") is not True:
        issues.append("正式登记阶段 runtime_enabled 必须为 true")

    source_refs = source.get("source_refs", {})
    entries = source.get("entries", {})
    memory_group_record = source.get("articulatory_memory_groups", {})
    projection = source.get("runtime_projection", {})
    if not isinstance(source_refs, dict) or not source_refs:
        issues.append("source_refs 必须是非空对象")
        source_refs = {}
    if not isinstance(entries, dict):
        issues.append("entries 必须是对象")
        entries = {}

    memory_groups: list[Any] = []
    if not isinstance(memory_group_record, dict):
        issues.append("articulatory_memory_groups 必须是对象")
    else:
        raw_groups = memory_group_record.get("groups", [])
        if not isinstance(raw_groups, list):
            issues.append("articulatory_memory_groups.groups 必须是数组")
        else:
            memory_groups = raw_groups

    flattened_memory_labels: list[str] = []
    flattened_memory_numbers: list[int] = []
    for expected_group_no, group in enumerate(memory_groups, start=1):
        if not isinstance(group, dict):
            issues.append(f"发音部位记忆组 {expected_group_no} 必须是对象")
            continue
        if group.get("group_no") != expected_group_no:
            issues.append(f"发音部位记忆组编号必须连续；期望 {expected_group_no}")
        members = group.get("members", [])
        numbers = group.get("memory_numbers", [])
        if not isinstance(members, list) or not all(isinstance(item, str) for item in members):
            issues.append(f"发音部位记忆组 {expected_group_no} 的 members 无效")
            members = []
        if not isinstance(numbers, list) or not all(isinstance(item, int) for item in numbers):
            issues.append(f"发音部位记忆组 {expected_group_no} 的 memory_numbers 无效")
            numbers = []
        if len(members) != len(numbers):
            issues.append(f"发音部位记忆组 {expected_group_no} 的成员数与序号数不一致")
        flattened_memory_labels.extend(members)
        flattened_memory_numbers.extend(numbers)

    actual_memory_groups = tuple(
        tuple(group.get("members", []))
        for group in memory_groups
        if isinstance(group, dict)
    )
    if actual_memory_groups != EXPECTED_MEMORY_GROUPS:
        issues.append("发音部位记忆分组或组内顺序偏离已审定的六组四项加末组三项结构")
    if flattened_memory_numbers != list(range(1, 28)):
        issues.append("memory_no 必须从 1 到 27 连续且不重复")
    if len(flattened_memory_labels) != len(set(flattened_memory_labels)):
        issues.append("发音部位记忆分组含重复成员")
    if len(memory_groups) == 7 and isinstance(memory_groups[6], dict):
        virtual_group = memory_groups[6]
        if virtual_group.get("name") != "后置组三项":
            issues.append("第七记忆组必须命名为‘后置组三项’，避免冒充完整的结构类别")
        if virtual_group.get("group_kind") != "mnemonic_tail":
            issues.append("第七记忆组必须明确标作 mnemonic_tail")
        if virtual_group.get("member_descriptions") != EXPECTED_VIRTUAL_INITIAL_DESCRIPTIONS:
            issues.append("后置组三项必须区分非高舌位、[u] 高乐音和 [y] 高乐音三种后接条件")

    seen_ids: set[str] = set()
    canonical_labels: set[str] = set()
    runtime_ids: set[str] = set()
    deferred_ids: set[str] = set()
    for label, entry in entries.items():
        if not isinstance(entry, dict):
            issues.append(f"首音 {label} 必须是对象")
            continue
        yinyuan_id = str(entry.get("yinyuan_id", ""))
        if not yinyuan_id.startswith("N"):
            issues.append(f"首音 {label} 的 yinyuan_id 必须以 N 开头")
        if yinyuan_id in seen_ids:
            issues.append(f"重复的噪音音元 ID: {yinyuan_id}")
        seen_ids.add(yinyuan_id)

        activation = entry.get("activation")
        if activation not in ALLOWED_ACTIVATIONS:
            issues.append(f"首音 {label} 的 activation 无效: {activation}")
        elif activation == "runtime_compatible":
            runtime_ids.add(yinyuan_id)
        else:
            deferred_ids.add(yinyuan_id)

        if entry.get("role") == "canonical_initial":
            canonical_labels.add(str(entry.get("canonical_pinyin_initial", "")))

        refs = entry.get("source_refs", [])
        if not isinstance(refs, list) or not refs:
            issues.append(f"首音 {label} 缺少 source_refs")
        else:
            unknown_refs = sorted(set(map(str, refs)) - set(source_refs))
            if unknown_refs:
                issues.append(f"首音 {label} 引用未知来源: {', '.join(unknown_refs)}")

        if activation == "research_only" and not entry.get("canonical_restore"):
            issues.append(f"延后首音 {label} 缺少 canonical_restore")

    if len(entries) != 27:
        issues.append(f"噪音片音真源必须登记 27 项，实际 {len(entries)} 项")
    expected_ids = {f"N{index:02d}" for index in range(1, 28)}
    if seen_ids != expected_ids:
        missing = sorted(expected_ids - seen_ids)
        extra = sorted(seen_ids - expected_ids)
        issues.append(f"N01-N27 不完整；缺少={missing}，额外={extra}")
    if canonical_labels != CANONICAL_INITIALS:
        issues.append("二十一规范声母集合不完整或含额外成员")
    if deferred_ids != REQUIRED_DEFERRED_IDS:
        issues.append(f"当前版本不得保留延后登记，实际 {sorted(deferred_ids)}")
    if set(flattened_memory_labels) != set(entries):
        missing = sorted(set(entries) - set(flattened_memory_labels))
        extra = sorted(set(flattened_memory_labels) - set(entries))
        issues.append(f"发音部位记忆分组必须恰好覆盖全部条目；缺少={missing}，额外={extra}")
    virtual_initial_labels = {
        label
        for label, entry in entries.items()
        if isinstance(entry, dict) and entry.get("structural_role") == "virtual_initial"
    }
    if virtual_initial_labels != EXPECTED_VIRTUAL_INITIAL_LABELS:
        issues.append(
            "虚首音结构类别必须跨组包含 '、y[j]、w、ɥ；"
            f"实际={sorted(virtual_initial_labels)}"
        )

    a_apical = entries.get("a_apical", {})
    if isinstance(a_apical, dict):
        if a_apical.get("ipa") != ["ɹ", "z"]:
            issues.append("a_apical 只登记舌尖前 ɹ/z；舌尖后 ɻ/ʐ 由 N19(r) 承担")
        a_conditions = a_apical.get("conditions", {})
        if not isinstance(a_conditions, dict):
            issues.append("a_apical.conditions 必须是对象")
        elif a_conditions.get("conditional_realizations") != EXPECTED_A_APICAL_REALIZATIONS:
            issues.append("a_apical 必须登记 ɿ 后的 ɹa/za")

    retroflex = entries.get("r", {})
    if isinstance(retroflex, dict) and retroflex.get("ipa") != ["ɻ", "ʐ"]:
        issues.append("N19(r) 必须继续登记舌尖后 ɻ/ʐ")

    declared_runtime_ids = set(map(str, projection.get("active_yinyuan_ids", [])))
    declared_deferred_ids = set(map(str, projection.get("deferred_yinyuan_ids", [])))
    if declared_runtime_ids != runtime_ids:
        issues.append("runtime_projection.active_yinyuan_ids 与条目 activation 不一致")
    if declared_deferred_ids != deferred_ids:
        issues.append("runtime_projection.deferred_yinyuan_ids 与条目 activation 不一致")

    registry_by_id = _registry_by_id(registry)
    if set(registry_by_id) != runtime_ids:
        issues.append("现行稳定登记表必须恰好覆盖全部运行音元 N01-N27")
    for label, entry in entries.items():
        if not isinstance(entry, dict) or entry.get("activation") != "runtime_compatible":
            continue
        yinyuan_id = str(entry.get("yinyuan_id", ""))
        registered = registry_by_id.get(yinyuan_id)
        if registered is None:
            continue
        registry_label, _registry_entry = registered
        if registry_label != label:
            issues.append(
                f"{yinyuan_id} 标签不一致：真源={label}，稳定登记={registry_label}"
            )

    aliases = projection.get("compatibility_aliases", {})
    if not isinstance(aliases, dict):
        issues.append("runtime_projection.compatibility_aliases 必须是对象")
        aliases = {}
    for alias, record in aliases.items():
        if alias not in entries:
            issues.append(f"兼容别名 {alias} 不在真源 entries 中")
            continue
        target_id = str(record.get("target_yinyuan_id", ""))
        if target_id not in runtime_ids:
            issues.append(f"兼容别名 {alias} 指向非运行登记 {target_id}")

    return ZaoyinPianyinAudit(
        entry_count=len(entries),
        articulatory_group_count=len(memory_groups),
        memory_sequence_count=len(flattened_memory_labels),
        runtime_entry_count=len(runtime_ids),
        deferred_entry_count=len(deferred_ids),
        compatibility_alias_count=len(aliases),
        issues=tuple(issues),
    )


def runtime_compatibility_aliases(
    source_path: Path = DEFAULT_SOURCE_PATH,
    registry_path: Path = DEFAULT_REGISTRY_PATH,
) -> dict[str, str]:
    """Return analysis-label -> registered runtime-label compatibility aliases."""
    audit = audit_zaoyin_pianyin_source(source_path, registry_path)
    if not audit.passed:
        raise ValueError("噪音片音真源校验失败: " + "; ".join(audit.issues))

    source = _load_json(source_path)
    registry = _load_json(registry_path)
    registry_by_id = _registry_by_id(registry)
    aliases = source["runtime_projection"].get("compatibility_aliases", {})
    return {
        alias: registry_by_id[str(record["target_yinyuan_id"])][0]
        for alias, record in aliases.items()
    }


def build_proposed_registry(
    source_path: Path = DEFAULT_SOURCE_PATH,
    registry_path: Path = DEFAULT_REGISTRY_PATH,
    pua_projection_path: Path = DEFAULT_PUA_PROJECTION_PATH,
) -> dict[str, Any]:
    """Build a normalized 27-entry registry view without overwriting the live registry."""
    audit = audit_zaoyin_pianyin_source(source_path, registry_path)
    if not audit.passed:
        raise ValueError("噪音片音真源校验失败: " + "; ".join(audit.issues))

    source = _load_json(source_path)
    live_registry = _load_json(registry_path)
    pua_projection = _load_json(pua_projection_path)
    live_by_id = _registry_by_id(live_registry)
    reserved_by_id = {
        str(item["label"]).removesuffix("_reserved"): str(item["char"])
        for item in pua_projection.get("reserved_slots", [])
    }

    proposed_entries: dict[str, dict[str, Any]] = {}
    for label, source_entry in source["entries"].items():
        yinyuan_id = str(source_entry["yinyuan_id"])
        if yinyuan_id in live_by_id:
            _old_label, live_entry = live_by_id[yinyuan_id]
            runtime_char = str(live_entry["runtime_char"])
        else:
            runtime_char = reserved_by_id.get(yinyuan_id, "")
        if not runtime_char:
            raise ValueError(f"{yinyuan_id} 没有可用的预留运行字符")

        proposed_entries[label] = {
            "ipa": list(map(str, source_entry.get("ipa", []))),
            "type": "unstable_pitch_yinyuan",
            "semantic_code": f"ZPY_{yinyuan_id}",
            "runtime_char": runtime_char,
            "yinyuan_id": yinyuan_id,
            "activation": source_entry["activation"],
            "canonical_pinyin_initial": source_entry.get("canonical_pinyin_initial", ""),
        }

    return {
        "schema_version": 2,
        "name": {"Zaoyin Yinyuan": "噪音类音元稳定登记提案"},
        "description": "由结构化 zaoyin_pianyin 真源生成；N25-N27 已进入稳定登记，语境规则仍须单独审核。",
        "runtime_enabled": True,
        "entries": proposed_entries,
    }
