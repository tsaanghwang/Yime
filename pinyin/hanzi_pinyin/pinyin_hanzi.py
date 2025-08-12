"""
拼音汉字映射
功能：根据文件创建由拼音到汉字的映射字典

要求：
- 从输入字典中查找不同拼音
- 以拼音为键，以每个拼音对应的全部汉字构成的列表为值
- 将字典写入到输出文件中
- 输出文件按拼音首字母顺序排序

- 输入文件格式：
{"unicode": {"汉字": ["pinyin1", "pinyin2", ...]}}
例如：
{
        "U+3007": {"〇": ["líng", "yuán", "xīng"]},
        "U+3400": {"㐀": ["qiū"]},
        "U+3401": {"㐁": ["tiàn"]},
        "U+3404": {"㐄": ["kuà"]},
        "U+3405": {"㐅": ["wǔ"]},
        "U+3406": {"㐆": ["yǐn"]},
        ...
}

- 输出文件格式：
{"pinyin": ["hanzi1", "hanzi2","hanzi3", ...]}
例如：
{"líng": ["〇", "㖫", "㱥", ...],
"yuán": ["〇","允", "元", ...],
"xīng": ["〇","兴", "嫈", ...],
"qiū": ["㐀", "惆","楸", ...],
...
}
"""

import os
import json

# 定义输入输出文件路径 - 使用os.path.join确保跨平台兼容性
module_dir = os.path.dirname(os.path.abspath(__file__))
input_file = os.path.join(module_dir, 'unicode_hanzi_pinyin.json')
output_file = os.path.join(module_dir, 'pinyin_hanzi.json')

def reverse_key_value_pairs(input_file, output_file):
    """
    反转指定格式JSON 文件的键值对

    :param input_file: 输入文件路径
    :param output_file: 输出文件路径
    """
    # 读取输入文件
    with open(input_file, 'r', encoding='utf-8') as f:
        input_data = json.load(f)

    # 创建拼音到汉字的映射字典
    pinyin_hanzi_dict = {}

    # 遍历输入数据
    for unicode_data in input_data.values():
        for hanzi, pinyin_list in unicode_data.items():
            for pinyin in pinyin_list:
                # 如果拼音不存在于字典中，则添加新条目
                if pinyin not in pinyin_hanzi_dict:
                    pinyin_hanzi_dict[pinyin] = []
                # 添加汉字到对应拼音的列表中
                if hanzi not in pinyin_hanzi_dict[pinyin]:
                    pinyin_hanzi_dict[pinyin].append(hanzi)

    # 按拼音首字母排序
    sorted_pinyin_hanzi = dict(sorted(pinyin_hanzi_dict.items()))

    # 写入输出文件
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(sorted_pinyin_hanzi, f, ensure_ascii=False, indent=2)

# 执行转换
if __name__ == '__main__':
    reverse_key_value_pairs(input_file, output_file)
    print(f"由拼音到汉字的映射字典已保存到 {output_file}")