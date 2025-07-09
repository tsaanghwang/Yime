import json
from collections import defaultdict
from yinyuan.unpitched_yinyuan import UnpitchedYinyuan  # 修改为导入yinyuan目录下的类
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))  # 修改为使用当前目录

def generate_unpitched_yinyuan():
    # 1. 加载原始数据
    with open('pianyin/pianyin_initial.json', 'r', encoding='utf-8') as f:
        unpitched_pianyin = json.load(f)

    # 从 JSON 中获取声母排列顺序
    # 如果没有提供声母顺序，则使用默认顺序
    INITIAL_ORDER = unpitched_pianyin.get('initial_order', [
        'b', 'p', 'm', 'f',
        'd', 't', 'n', 'l',
        'g', 'k', 'h',
        'j', 'q', 'x',
        'zh', 'ch', 'sh', 'r',
        'z', 'c', 's'
    ])

    # 2. 创建新的数据结构
    yinyuan_data = {
        "name": "噪音类音元",
        "description": "噪音类音元是噪音类片音的另一种符号化表示形式",
        "note": "暂时借用表示声母的符号表示噪音类音元，以便理解。零声母[ŋ, ʔ, ɣ]用隔音符号/'(U+0027)/来表示，在音节界限不发生混淆时省略，只在音节界限发生混淆时标注。",
        "unpitched_yinyuan": {},
        "codes": {}  # 新增音元代码映射
    }

    # 3. 合并清音和浊音，反转键值映射
    merged_mapping = defaultdict(list)

    def get_initial(initial):
        """获取拼音的声母部分"""
        # 先检查双字母声母(zh, ch, sh)
        if initial.startswith('zh'):
            return 'zh'
        elif initial.startswith('ch'):
            return 'ch'
        elif initial.startswith('sh'):
            return 'sh'
        # 然后检查单字母声母
        elif initial[0] in INITIAL_ORDER:
            return initial[0]
        else:
            return ''  # 无标准声母的情况

    # 处理清音
    for ipa, initial_list in unpitched_pianyin['unpitched_pianyin']['voiceless'].items():
        for initial in initial_list:
            merged_mapping[initial].append(ipa)

    # 处理浊音
    for ipa, initial_list in unpitched_pianyin['unpitched_pianyin']['voiced'].items():
        for initial in initial_list:
            merged_mapping[initial].append(ipa)

    # 4. 按声母排列顺序排序
    sorted_initial = sorted(merged_mapping.keys(),
                                 key=lambda x: (INITIAL_ORDER.index(get_initial(x))
                                                if get_initial(x) in INITIAL_ORDER
                                                else len(INITIAL_ORDER), x))

    for initial in sorted_initial:
        yinyuan_data['unpitched_yinyuan'][initial] = merged_mapping[initial]
        # 为每个拼音生成音元代码
        code = UnpitchedYinyuan._get_yinyuan_code(initial)
        if code is not None:
            yinyuan_data['codes'][initial] = code

    # 5. 写入输出文件
    output_path = 'yinyuan/unpitched_yinyuan.json'
    Path(output_path).parent.mkdir(parents=True, exist_ok=True)  # 确保目录存在
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(yinyuan_data, f, ensure_ascii=False, indent=2)

    print(f"成功生成噪音类音元文件: {output_path}")
    print(f"共生成 {len(yinyuan_data['unpitched_yinyuan'])} 个噪音类音元")

    return yinyuan_data


if __name__ == '__main__':
    generate_unpitched_yinyuan()
