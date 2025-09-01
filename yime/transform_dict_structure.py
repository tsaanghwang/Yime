# transform_dict_structure.py
import json

def enhance_mapping(input_file='yinjie_mapping.json', output_file='enhanced_yinjie_mapping.json'):
    with open(input_file, 'r', encoding='utf-8') as f:
        data = json.load(f)

    for yinjie, mappings in data['音元符号'].items():
        # 补充调号标调和注音符号
        if mappings['数字标调']:
            pinyin = mappings['数字标调']
            tone = pinyin[-1]
            base = pinyin[:-1]

            # 生成调号标调
            if tone in '12345':
                diaohao_map = {'1': 'ˉ', '2': 'ˊ', '3': 'ˇ', '4': 'ˋ', '5': ''}
                mappings['调号标调'] = base + diaohao_map[tone]

            # 生成注音符号 (这里需要实际注音转换逻辑)
            mappings['注音符号'] = convert_to_zhuyin(pinyin)  # 需要实现此函数

            # 完善反向映射
            mappings['反向映射'] = {
                mappings['数字标调']: {
                    '调号': mappings['调号标调'],
                    '注音': mappings['注音符号']
                },
                mappings['调号标调']: {
                    '数字': mappings['数字标调'],
                    '注音': mappings['注音符号']
                },
                mappings['注音符号']: {
                    '数字': mappings['数字标调'],
                    '调号': mappings['调号标调']
                }
            }

    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

# 示例调用
enhance_mapping()