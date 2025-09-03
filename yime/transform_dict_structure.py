# transform_dict_structure.py
import json
import sys
from pathlib import Path

# 确保能正确导入utils模块
utils_path = Path("c:/Users/Freeman Golden/OneDrive/Yime/utils")
if utils_path.exists():
    sys.path.insert(0, str(utils_path))

from utils.pinyin_normalizer import PinyinNormalizer
from utils.pinyin_zhuyin import PinyinZhuyinConverter  # 新增导入

def convert_to_zhuyin(pinyin):
    """使用PinyinZhuyinConverter处理注音符号转换"""
    return PinyinZhuyinConverter.convert_pinyin_to_zhuyin(pinyin)

def enhance_mapping(input_file='yinjie_mapping.json', output_file='enhanced_yinjie_mapping.json'):
    with open(input_file, 'r', encoding='utf-8') as f:
        data = json.load(f)

    # 提取所有拼音进行批量处理
    pinyin_dict = {}
    for yinjie, mappings in data['音元符号'].items():
        if mappings['数字标调']:
            pinyin_dict[mappings['数字标调']] = mappings['数字标调']

    # 使用PinyinNormalizer进行标准化处理
    normalized_dict, _ = PinyinNormalizer.process_pinyin_dict(pinyin_dict)

    # 使用PinyinZhuyinConverter进行注音符号处理
    zhuyin_dict, _ = PinyinZhuyinConverter.process_pinyin_dict(pinyin_dict)

    for yinjie, mappings in data['音元符号'].items():
        # 补充调号标调和注音符号
        if mappings['数字标调']:
            pinyin = mappings['数字标调']

            # 使用标准化后的拼音
            mappings['调号标调'] = normalized_dict.get(pinyin, pinyin)

            # 使用PinyinZhuyinConverter处理注音符号
            mappings['注音符号'] = zhuyin_dict.get(pinyin, pinyin)

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