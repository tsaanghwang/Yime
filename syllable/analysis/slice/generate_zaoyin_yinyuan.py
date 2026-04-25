"""
噪音类音元数据生成模块

根据 zaoyin_yinyuan.py 中的 ClearNoise 和 VoicedNoise 类，
直接生成噪音类音元(Noise Yinyuan)的 JSON 数据文件。
"""

import json
import sys
from pathlib import Path
from typing import TypedDict

sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent))

from zaoyin_yinyuan import ClearNoise, VoicedNoise


class MergedEntry(TypedDict):
    ipa: list[str]
    types: list[str]
    code: str


class SourceEntry(TypedDict):
    ipa: list[str]
    type: str
    semantic_code: str
    runtime_char: str
    layout_slot: str


class SourceDocument(TypedDict):
    name: dict[str, str]
    description: str
    entries: dict[str, SourceEntry]


def load_existing_runtime_chars(output_path: Path) -> dict[str, str]:
    """Preserve manually assigned runtime characters across source regeneration."""
    if not output_path.exists():
        return {}

    with output_path.open('r', encoding='utf-8') as f:
        existing_data = json.load(f)

    entries = existing_data.get('entries', {})
    return {
        initial: entry.get('runtime_char', '')
        for initial, entry in entries.items()
        if entry.get('runtime_char')
    }


def load_existing_layout_slots(output_path: Path) -> dict[str, str]:
    if not output_path.exists():
        return {}

    with output_path.open('r', encoding='utf-8') as f:
        existing_data = json.load(f)

    entries = existing_data.get('entries', {})
    return {
        initial: entry.get('layout_slot', '')
        for initial, entry in entries.items()
        if entry.get('layout_slot')
    }


def normalize_initial(initial: str) -> str:
    """Collapse legacy zero-initial variants back to the runtime label set."""
    if initial == "''":
        return "'"
    return initial


def build_semantic_code(initial: str) -> str:
    return f"UPY_{initial.upper()}"


def load_runtime_fallback(runtime_path: Path) -> dict[str, str]:
    """Fall back to the generated runtime map during one-time schema migration."""
    if not runtime_path.exists():
        return {}

    with runtime_path.open('r', encoding='utf-8') as f:
        runtime_data = json.load(f)

    return runtime_data.get('首音', {})


def generate_zaoyin_yinyuan():
    """
    读取 yinyuan/pianyin_initial.json，生成噪音类音元 JSON 文件。
    """
    base_dir = Path(__file__).parent
    input_path = base_dir / 'yinyuan' / 'pianyin_initial.json'
    output_path = base_dir / 'yinyuan' / 'zaoyin_yinyuan_enhanced.json'
    simplified_output_path = base_dir / 'yinyuan' / 'zaoyin_yinyuan.json'
    runtime_path = base_dir / 'yinyuan' / 'shouyin_codepoint.json'
    existing_runtime_chars = load_existing_runtime_chars(output_path)
    existing_layout_slots = load_existing_layout_slots(output_path)
    runtime_fallback = load_runtime_fallback(runtime_path)

    if not input_path.exists():
        raise FileNotFoundError(f"找不到输入文件: {input_path}")

    with open(input_path, 'r', encoding='utf-8') as f:
        pianyin_data = json.load(f)

    # 检查数据结构是否包含所需字段
    if 'uncertain_pitch_pianyin' not in pianyin_data:
        raise KeyError("输入文件中缺少 'uncertain_pitch_pianyin' 字段")

    # 合并所有声母
    merged_mapping: dict[str, MergedEntry] = {}
    noise_type_pairs: list[tuple[str, type[ClearNoise] | type[VoicedNoise]]] = [
        ('unpitched_pianyin', ClearNoise),
        ('unstable_pitch_pianyin', VoicedNoise),
    ]
    for yinyuan_type, _noise_class in noise_type_pairs:
        if yinyuan_type not in pianyin_data['uncertain_pitch_pianyin']:
            continue

        for initial, ipas in pianyin_data['uncertain_pitch_pianyin'][yinyuan_type].items():
            normalized_initial = normalize_initial(initial)

            if normalized_initial not in merged_mapping:
                merged_mapping[normalized_initial] = {
                    "ipa": [],
                    "types": [],
                    "code": ""
                }
            merged_mapping[normalized_initial]["ipa"].extend(ipas)
            if yinyuan_type not in merged_mapping[normalized_initial]["types"]:
                merged_mapping[normalized_initial]["types"].append(yinyuan_type)
            merged_mapping[normalized_initial]["code"] = build_semantic_code(normalized_initial)

    # 按预定义顺序排序
    initial_order = pianyin_data.get('initial_order', [
        'b', 'p', 'f', 'm',
        'd', 't', 'l', 'n',
        'g', 'k', 'h',
        'z', 'c', 's',
        'zh', 'ch', 'sh', 'r',
        'j', 'q', 'x'
    ])
    sorted_initials = sorted(
        merged_mapping.keys(),
        key=lambda x: (initial_order.index(x) if x in initial_order else len(initial_order), x)
    )

    # 组织唯一真源结构。每个首音在一条记录里保存语义码、IPA、类型和运行时字符。
    result: SourceDocument = {
        "name": {"Uncertain Pitch Yinyuan": "音调不定的音元或噪音类音元"},
        "description": "由 ClearNoise 和 VoicedNoise 两类音元组成",
        "entries": {}
    }
    entries: dict[str, SourceEntry] = result["entries"]

    # 创建简化版数据结构
    simplified_result = {}

    for initial in sorted_initials:
        entry = merged_mapping[initial]
        entry_types = entry["types"]
        if len(entry_types) == 1:
            normalized_type = "unpitched_yinyuan" if entry_types[0] == "unpitched_pianyin" else "unstable_pitch_yinyuan"
        else:
            normalized_type = "mixed_yinyuan"

        entries[initial] = {
            "ipa": entry["ipa"],
            "type": normalized_type,
            "semantic_code": entry["code"],
            "runtime_char": existing_runtime_chars.get(initial, runtime_fallback.get(initial, "")),
            "layout_slot": existing_layout_slots.get(initial, f"N{len(entries) + 1:02d}")
        }

        # 添加到简化版数据结构
        simplified_result[initial] = entry["ipa"]

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(result, f, ensure_ascii=False, indent=2)

    # 保存简化版文件
    with open(simplified_output_path, 'w', encoding='utf-8') as f:
        json.dump({"shouyin": simplified_result}, f, ensure_ascii=False, indent=2)

    print(f"已生成噪音类音元文件: {output_path}")
    print(f"已生成简化版噪音类音元文件: {simplified_output_path}")
    unpitched_count = sum(1 for entry in entries.values() if entry['type'] == 'unpitched_yinyuan')
    unstable_count = sum(1 for entry in entries.values() if entry['type'] == 'unstable_pitch_yinyuan')
    mixed_count = sum(1 for entry in entries.values() if entry['type'] == 'mixed_yinyuan')
    print(f"无调音元: {unpitched_count} 个，不稳定音高音元: {unstable_count} 个，混合零首音: {mixed_count} 个")

if __name__ == "__main__":
    generate_zaoyin_yinyuan()
