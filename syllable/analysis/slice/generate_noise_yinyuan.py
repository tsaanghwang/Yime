import json
from collections import defaultdict
# 确保从正确路径导入
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent))  # 添加项目根目录

from syllable.analysis.slice.yinyuan import UnpitchedYinyuan, UnstablePitchYinyuan
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))  # 修改为使用当前目录


def generate_noise_yinyuan():
    """生成噪音类音元(Noise Yinyuan)数据文件"""
    # 1. 加载原始数据
    pinyin_initial_path = Path(__file__).parent / 'pianyin_initial.json'
    with open(pinyin_initial_path, 'r', encoding='utf-8') as f:
        noise_pianyin = json.load(f)

    # 从 JSON 中获取声母排列顺序
    INITIAL_ORDER = noise_pianyin.get('initial_order', [
        'b', 'p', 'm', 'f',
        'd', 't', 'n', 'l',
        'g', 'k', 'h',
        'j', 'q', 'x',
        'zh', 'ch', 'sh', 'r',
        'z', 'c', 's'
    ])

    # 2. 创建新的数据结构
    yinyuan_data = {
        "name": "噪音类音元(Noise Yinyuan)",
        "description": "噪音类音元是噪音类片音的另一种符号化表示形式",
        "note": "包含无调音元(Unpitched)和不稳定音高音元(Unstable Pitch)",
        "unpitched_yinyuan": {},
        "unstable_pitch_yinyuan": {},
        "codes": {}
    }

    # 3. 合并清音和浊音，反转键值映射
    merged_mapping = defaultdict(list)

    def get_initial(initial):
        """获取拼音的声母部分"""
        if initial.startswith('zh'):
            return 'zh'
        elif initial.startswith('ch'):
            return 'ch'
        elif initial.startswith('sh'):
            return 'sh'
        elif initial[0] in INITIAL_ORDER:
            return initial[0]
        return ''

    # 处理清音(无调音元)
    for ipa, initial_list in noise_pianyin['unpitched_pianyin']['voiceless'].items():
        for initial in initial_list:
            merged_mapping[initial].append(ipa)

    # 处理浊音(不稳定音高音元)
    for ipa, initial_list in noise_pianyin['unpitched_pianyin']['voiced'].items():
        for initial in initial_list:
            merged_mapping[initial].append(ipa)

    # 4. 按声母排列顺序排序
    sorted_initial = sorted(merged_mapping.keys(),
                          key=lambda x: (INITIAL_ORDER.index(get_initial(x))
                                         if get_initial(x) in INITIAL_ORDER
                                         else len(INITIAL_ORDER), x))

    for initial in sorted_initial:
        # 根据音元类型分类存储
        if any(initial in lst for lst in noise_pianyin['unpitched_pianyin']['voiced'].values()):
            yinyuan_data['unstable_pitch_yinyuan'][initial] = merged_mapping[initial]
        else:
            yinyuan_data['unpitched_yinyuan'][initial] = merged_mapping[initial]
        
        # 为每个拼音生成音元代码
        code = UnpitchedYinyuan._get_yinyuan_code(initial) if initial in yinyuan_data['unpitched_yinyuan'] else UnstablePitchYinyuan._get_yinyuan_code(initial)
        if code is not None:
            yinyuan_data['codes'][initial] = code

    # 5. 写入输出文件
    output_path = 'syllable/analysis/slice/noise_yinyuan.json'
    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(yinyuan_data, f, ensure_ascii=False, indent=2)

    print(f"成功生成噪音类音元文件: {output_path}")
    print(f"共生成 {len(yinyuan_data['unpitched_yinyuan'])} 个无调音元")
    print(f"共生成 {len(yinyuan_data['unstable_pitch_yinyuan'])} 个不稳定音高音元")

    return yinyuan_data


if __name__ == '__main__':
    generate_noise_yinyuan()