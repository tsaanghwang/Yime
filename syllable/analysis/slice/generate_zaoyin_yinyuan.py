"""
噪音类音元数据生成模块

根据 indeterminate_pitch_yinyuan.py 中的 ClearNoise 和 VoicedNoise 类，
直接生成噪音类音元(Noise Yinyuan)的 JSON 数据文件。
"""

import json
from pathlib import Path
from indeterminate_pitch_yinyuan import ClearNoise, VoicedNoise


def generate_noise_yinyuan():
    """
    读取 yinyuan/pianyin_initial.json，生成噪音类音元 JSON 文件。
    """
    base_dir = Path(__file__).parent
    input_path = base_dir / 'yinyuan' / 'pianyin_initial.json'
    output_path = base_dir / 'yinyuan' / 'zaoyin_yinyuan.json'

    if not input_path.exists():
        raise FileNotFoundError(f"找不到输入文件: {input_path}")

    with open(input_path, 'r', encoding='utf-8') as f:
        pianyin_data = json.load(f)

    # 合并所有初始音
    merged_mapping = {}
    for yinyuan_type, NoiseClass in [('unpitched', ClearNoise), ('unstable_pitch', VoicedNoise)]:
        for ipa, initials in pianyin_data['unpitched_pianyin'][yinyuan_type].items():
            for initial in initials:
                if initial not in merged_mapping:
                    merged_mapping[initial] = {
                        "ipa": [], "type": yinyuan_type, "code": ""}
                merged_mapping[initial]["ipa"].append(ipa)
                merged_mapping[initial]["type"] = yinyuan_type
                merged_mapping[initial]["code"] = NoiseClass.get_yinyuan_code(
                    initial)

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
        key=lambda x: (initial_order.index(
            x) if x in initial_order else len(initial_order), x)
    )

    # 组织输出结构
    result = {
        "name": "噪音类音元(Noise Yinyuan)",
        "description": "由 ClearNoise/VoicedNoise 直接生成的噪音类音元数据",
        "unpitched_yinyuan": {},
        "unstable_pitch_yinyuan": {},
        "codes": {}
    }
    for initial in sorted_initials:
        entry = merged_mapping[initial]
        if entry["type"] == "unpitched":
            result["unpitched_yinyuan"][initial] = entry["ipa"]
        else:
            result["unstable_pitch_yinyuan"][initial] = entry["ipa"]
        result["codes"][initial] = entry["code"]

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(result, f, ensure_ascii=False, indent=2)

    print(f"已生成噪音类音元文件: {output_path}")
    print(f"无调音元: {len(result['unpitched_yinyuan'])} 个，"
          f"不稳定音高音元: {len(result['unstable_pitch_yinyuan'])} 个")


if __name__ == "__main__":
    generate_noise_yinyuan()
