"""
根据syllable\analysis\slice\pitched_yinyuan.py定义的Yinyuan类和
syllable\analysis\slice\indeterminate_pitch_yinyuan.py定义的
ClearNoise和VoicedNoise类，重构syllable\analysis\slice\generate_noise_yinyuan.py

噪音类音元数据生成模块

该模块负责将拼音初始音转换为对应的噪音类音元表示，包括清音(无调音元)和浊音(不稳定音高音元)，
并生成JSON格式的输出文件。
"""

import json
from collections import defaultdict
from pathlib import Path
from typing import Dict, List, Literal, TypedDict
from indeterminate_pitch_yinyuan import ClearNoise, VoicedNoise

# 类型定义
class NoiseYinyuanData(TypedDict):
    """噪音类音元数据结构类型定义"""
    name: str
    description: str
    note: str
    unpitched_yinyuan: Dict[str, List[str]]
    unstable_pitch_yinyuan: Dict[str, List[str]]
    codes: Dict[str, str]

InitialType = Literal[
    'b', 'p', 'm', 'f', 'd', 't', 'n', 'l',
    'g', 'k', 'h', 'j', 'q', 'x',
    'zh', 'ch', 'sh', 'r', 'z', 'c', 's'
]

def get_initial(initial: str, initial_order: List[InitialType]) -> str:
    """从拼音初始音中提取标准化的声母

    Args:
        initial: 原始拼音初始音
        initial_order: 标准声母顺序列表

    Returns:
        标准化后的声母，如'zh'、'ch'、'sh'或单字母声母
    """
    if initial.startswith('zh'):
        return 'zh'
    elif initial.startswith('ch'):
        return 'ch'
    elif initial.startswith('sh'):
        return 'sh'
    elif initial and initial[0] in initial_order:
        return initial[0]
    return ''

def generate_noise_yinyuan() -> NoiseYinyuanData:
    """生成噪音类音元数据文件

    Returns:
        生成的噪音类音元数据字典，包含:
        - name: 音元类型名称
        - description: 描述
        - note: 备注
        - unpitched_yinyuan: 无调音元映射
        - unstable_pitch_yinyuan: 不稳定音高音元映射
        - codes: 音元代码映射

    Raises:
        FileNotFoundError: 当输入文件不存在时抛出
    """
    base_dir = Path(__file__).parent
    input_path = base_dir / 'yinyuan' / 'pianyin_initial.json'
    output_path = base_dir / 'yinyuan' / 'noise_yinyuan.json'

    if not input_path.exists():
        raise FileNotFoundError(f"找不到输入文件: {input_path}")

    with open(input_path, 'r', encoding='utf-8') as f:
        noise_pianyin: Dict = json.load(f)

    INITIAL_ORDER: List[InitialType] = noise_pianyin.get('initial_order', [
        'b', 'p', 'm', 'f', 'd', 't', 'n', 'l',
        'g', 'k', 'h', 'j', 'q', 'x',
        'zh', 'ch', 'sh', 'r', 'z', 'c', 's'
    ])

    yinyuan_data: NoiseYinyuanData = {
        "name": "噪音类音元(Noise Yinyuan)",
        "description": "噪音类音元是噪音类片音的另一种符号化表示形式",
        "note": "包含无调音元(Unpitched)和不稳定音高音元(Unstable Pitch)",
        "unpitched_yinyuan": {},
        "unstable_pitch_yinyuan": {},
        "codes": {}
    }

    merged_mapping: Dict[str, List[str]] = defaultdict(list)

    # 处理清音(无调音元)和浊音(不稳定音高音元)
    for yinyuan_type in ['unpitched', 'unstable_pitch']:
        for ipa, initial_list in noise_pianyin['unpitched_pianyin'][yinyuan_type].items():
            for initial in initial_list:
                merged_mapping[initial].append(ipa)

    # 按声母顺序排序
    sorted_initial = sorted(
        merged_mapping.keys(),
        key=lambda x: (INITIAL_ORDER.index(get_initial(x, INITIAL_ORDER))
                      if get_initial(x, INITIAL_ORDER) in INITIAL_ORDER
                      else len(INITIAL_ORDER), x)
    )

    # 分类生成音元数据
    for initial in sorted_initial:
        is_voiced = any(initial in lst
                       for lst in noise_pianyin['unpitched_pianyin']['unstable_pitch'].values())

        if is_voiced:
            yinyuan_data['unstable_pitch_yinyuan'][initial] = merged_mapping[initial]
            code = VoicedNoise._get_yinyuan_code(initial)
        else:
            yinyuan_data['unpitched_yinyuan'][initial] = merged_mapping[initial]
            code = ClearNoise._get_yinyuan_code(initial)

        if code:
            yinyuan_data['codes'][initial] = code

    # 保存结果
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(yinyuan_data, f, ensure_ascii=False, indent=2)

    print(f"成功生成噪音类音元文件: {output_path}")
    print(f"共生成 {len(yinyuan_data['unpitched_yinyuan'])} 个无调音元")
    print(f"共生成 {len(yinyuan_data['unstable_pitch_yinyuan'])} 个不稳定音高音元")
    return yinyuan_data

if __name__ == '__main__':
    generate_noise_yinyuan()
