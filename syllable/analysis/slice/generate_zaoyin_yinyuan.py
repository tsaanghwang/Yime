"""
噪音类音元数据生成模块

根据 zaoyin_yinyuan.py 中的 ClearNoise 和 VoicedNoise 类，
直接生成噪音类音元(Noise Yinyuan)的 JSON 数据文件。
"""

import json
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent))

from zaoyin_yinyuan import ClearNoise, VoicedNoise


def generate_zaoyin_yinyuan():
    """
    读取 yinyuan/pianyin_initial.json，生成噪音类音元 JSON 文件。
    """
    base_dir = Path(__file__).parent
    input_path = base_dir / 'yinyuan' / 'pianyin_initial.json'
    output_path = base_dir / 'yinyuan' / 'zaoyin_yinyuan_enhanced.json'
    simplified_output_path = base_dir / 'yinyuan' / 'zaoyin_yinyuan.json'

    if not input_path.exists():
        raise FileNotFoundError(f"找不到输入文件: {input_path}")

    with open(input_path, 'r', encoding='utf-8') as f:
        pianyin_data = json.load(f)

    # 检查数据结构是否包含所需字段
    if 'indeterminate_pitch_pianyin' not in pianyin_data:
        raise KeyError("输入文件中缺少 'indeterminate_pitch_pianyin' 字段")

    # 合并所有声母
    merged_mapping = {}
    for yinyuan_type, NoiseClass in [('unpitched_pianyin', ClearNoise), ('unstable_pitch_pianyin', VoicedNoise)]:
        if yinyuan_type not in pianyin_data['indeterminate_pitch_pianyin']:
            continue

        for initial, ipas in pianyin_data['indeterminate_pitch_pianyin'][yinyuan_type].items():
            if initial not in merged_mapping:
                merged_mapping[initial] = {
                    "ipa": [],
                    "type": yinyuan_type,
                    "code": ""
                }
            merged_mapping[initial]["ipa"].extend(ipas)
            merged_mapping[initial]["type"] = yinyuan_type
            merged_mapping[initial]["code"] = NoiseClass.get_yinyuan_code(initial)

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

    # 组织输出结构
    result = {
        "name": {"Indeterminate Pitch Yinyuan": "不定调音元或噪音类音元"},
        "description": "由 ClearNoise和VoicedNoise 两类音元组成",
        "indeterminate_pitch_yinyuan": {
            "unpitched_yinyuan": {},
            "unstable_pitch_yinyuan": {}
        },
        "codes": {}
    }

    # 创建简化版数据结构
    simplified_result = {}

    for initial in sorted_initials:
        entry = merged_mapping[initial]
        if entry["type"] == "unpitched_pianyin":
            result["indeterminate_pitch_yinyuan"]["unpitched_yinyuan"][initial] = entry["ipa"]
        else:
            result["indeterminate_pitch_yinyuan"]["unstable_pitch_yinyuan"][initial] = entry["ipa"]
        result["codes"][initial] = entry["code"]

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
    print(f"无调音元: {len(result['indeterminate_pitch_yinyuan']['unpitched_yinyuan'])} 个，"
        f"不稳定音高音元: {len(result['indeterminate_pitch_yinyuan']['unstable_pitch_yinyuan'])} 个")

if __name__ == "__main__":
    generate_zaoyin_yinyuan()
