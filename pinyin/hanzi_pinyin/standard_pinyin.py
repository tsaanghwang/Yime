import os
import json
from collections import defaultdict


def extract_pinyin():
    """
    功能：析取由拼音与汉字构成的映射字典的拼音

    流程：
    1. 读取字典文件，析取键值对象的拼音(键)
    -  输入文件结构：{"pinyin": ["hanzi1", "hanzi2", "hanzi3", ...]}
    2. 字母组合不同的拼音按字母顺序排序
    3. 字母组合相同的拼音按调号顺序排序
    4. 构建输出字典：以标准拼音为键，以用数字标调的拼音为值
    -  即以键为值并在值中只把调号改成数字
    -  输出文件结构：{"standard_pinyin": "num_tone_pinyin"}
    5. 将最终字典以保存到指定文件
    """
    # 定义输入输出文件路径
    script_dir = os.path.dirname(os.path.abspath(__file__))
    input_file = os.path.join(script_dir, 'pinyin_hanzi.json')
    output_file = os.path.join(script_dir, 'standard_pinyin.json')

    # 读取输入JSON文件
    try:
        with open(input_file, 'r', encoding='utf-8') as f:
            pinyin_hanzi_dict = json.load(f)
    except FileNotFoundError:
        print(f"错误：输入文件 {input_file} 不存在")
        return
    except json.JSONDecodeError:
        print(f"错误：输入文件 {input_file} 不是有效的JSON格式")
        return

    TONE_MAP = {
        'ā': 'a1', 'á': 'a2', 'ǎ': 'a3', 'à': 'a4',
        'ē': 'e1', 'é': 'e2', 'ě': 'e3', 'è': 'e4',
        'ế': 'ê2', 'ề': 'ê4',  # 保留单个码点字符的映射
        'ī': 'i1', 'í': 'i2', 'ǐ': 'i3', 'ì': 'i4',
        'ō': 'o1', 'ó': 'o2', 'ǒ': 'o3', 'ò': 'o4',
        'ū': 'u1', 'ú': 'u2', 'ǔ': 'u3', 'ù': 'u4',
        'ǖ': 'ü1', 'ǘ': 'ü2', 'ǚ': 'ü3', 'ǜ': 'ü4',
        'ń': 'n2', 'ň': 'n3', 'ǹ': 'n4'
    }

    def handle_combining_chars(pinyin):
        """处理组合字符 ê̄ (ê + ̄)、ê̌ (ê + ̌) , m̄ (m + ̄)、ḿ (m + ́)、m̌ (m + ̌)、m̀ (m + ̀)和n̄ (n + ̄)"""
        # 处理 ê̄ 和 ê̌
        if 'ê̄' in pinyin:
            return pinyin.replace('ê̄', 'ê') + '1'
        if 'ê̌' in pinyin:
            return pinyin.replace('ê̌', 'ê') + '3'

        # 处理 m̄、m̀ 和 ḿ
        if 'm̄' in pinyin:
            return pinyin.replace('m̄', 'm') + '1'
        if 'ḿ' in pinyin:
            return pinyin.replace('ḿ', 'm') + '2'
        if 'm̌' in pinyin:
            return pinyin.replace('m̌', 'm') + '3'
        if 'm̀' in pinyin:
            return pinyin.replace('m̀', 'm') + '4'
        if 'n̄' in pinyin:
            return pinyin.replace('n̄', 'n') + '1'

        return None

    pinyin_dict = {}

    # 处理每个拼音
    for pinyin in pinyin_hanzi_dict.keys():
        # 先检查组合字符
        combined_result = handle_combining_chars(pinyin)
        if combined_result is not None:
            pinyin_dict[pinyin] = combined_result
            continue

        # 默认无调号为5
        num_tone_pinyin = pinyin + '5'

        # 检查每个字符是否是带调号的元音
        for char in pinyin:
            if char in TONE_MAP:
                # 找到调号，替换为数字标记
                num_tone_pinyin = pinyin.replace(
                    char, TONE_MAP[char][0]) + TONE_MAP[char][1]
                break

        # 添加到结果字典
        pinyin_dict[pinyin] = num_tone_pinyin

        # 对字典按键进行字母顺序排序
    pinyin_dict = dict(sorted(pinyin_dict.items(), key=lambda x: x[0]))

    # 保存到输出文件
    try:
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(pinyin_dict, f, ensure_ascii=False, indent=2)
        print(f"成功生成拼音字典，已保存到 {output_file}")
    except IOError as e:
        print(f"保存文件时出错: {e}")


if __name__ == "__main__":
    extract_pinyin()
