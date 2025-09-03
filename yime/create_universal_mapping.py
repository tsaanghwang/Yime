# create_universal_mapping.py
import json

def create_universal_map(mapping_file='yime/enhanced_yinjie_mapping.json',
                        pinyin_hanzi_file='yime/pinyin_codeTable.json',
                        output_file='yime/universal_mapping.json'):

    with open(mapping_file, 'r', encoding='utf-8') as f:
        yinjie_data = json.load(f)

    with open(pinyin_hanzi_file, 'r', encoding='utf-8') as f:
        pinyin_hanzi = json.load(f)

    universal_map = {}

    for yinjie, mappings in yinjie_data['音元符号'].items():
        # 获取所有可能的拼音表示形式
        pinyin_variants = [
            mappings['数字标调'],
            mappings['调号标调'],
            mappings['注音符号']
        ]

        # 对每种拼音形式查找对应的汉字
        for pinyin in pinyin_variants:
            if pinyin in pinyin_hanzi:
                universal_map[pinyin] = {
                    '汉字': pinyin_hanzi[pinyin],
                    '音元符号': yinjie,
                    '其他形式': [v for v in pinyin_variants if v != pinyin]
                }

    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(universal_map, f, ensure_ascii=False, indent=2)

# 示例调用
create_universal_map()