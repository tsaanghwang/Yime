# 拼音按声母分类
# 功能：从JSON格式的拼音汉字映射字典导入数据对拼音按声母分类
#
# 处理流程：
# 1. 读取JSON文件，析出带调拼音（键）
# 2. 构建字典结构：以声母为键，以拼音为值
# 3. a/o/e开头的音节（零声母音节）以a/e/o作键
# 4. 区分z, c, s 与 zh, ch, sh
# 5. 将分类结果以JSON格式保存到指定文件
#
# 输入文件格式：
# - JSON字典，结构为{"pinyin": "汉字"}
# - 路径：syllable\analysis\onset_rhyme\pinyin_to_single_hanzi.json
#
# 输出文件格式：
# - JSON字典，结构为{"shengmu": "pinyin"}，例如：{"b": ["ba1", "ba2", ...], "c": [...]}
# - 路径：syllable\analysis\onset_rhyme\pinyin_classified.json

import json
import os
from collections import defaultdict


def classify_pinyin(pinyin_dict):
    """
    分类拼音到声母类别

    参数:
        pinyin_dict: 拼音到汉字的字典

    返回:
        按声母分类的字典
    """
    classified = defaultdict(list)

    for pinyin in pinyin_dict.keys():
        # 处理零声母情况
        if pinyin[0] in {'a', 'e', 'o'}:
            initial = pinyin[0]
        # 处理平翘舌音
        elif pinyin.startswith('zh'):
            initial = 'zh'
        elif pinyin.startswith('ch'):
            initial = 'ch'
        elif pinyin.startswith('sh'):
            initial = 'sh'
        elif pinyin.startswith('z'):
            initial = 'z'
        elif pinyin.startswith('c'):
            initial = 'c'
        elif pinyin.startswith('s'):
            initial = 's'
        # 其他声母取第一个字母
        else:
            initial = pinyin[0]

        classified[initial].append(pinyin)

    return classified


def main():
    # 输入文件路径
    input_path = os.path.join(
        os.path.dirname(__file__),
        'pinyin_to_single_hanzi.json'
    )

    # 输出文件路径
    output_path = os.path.join(
        os.path.dirname(__file__),
        'pinyin_classified.json'
    )

    try:
        # 读取输入文件
        with open(input_path, 'r', encoding='utf-8') as f:
            pinyin_dict = json.load(f)

        # 分类拼音
        classified = classify_pinyin(pinyin_dict)

        # 将分类结果按声母排序
        sorted_classified = {k: sorted(v)
                             for k, v in sorted(classified.items())}

        # 写入输出文件
        with open(output_path, 'w', encoding='utf-8') as f:
            json.dump(sorted_classified, f, ensure_ascii=False, indent=2)

        print(f"拼音分类完成，结果已保存到: {output_path}")

    except Exception as e:
        print(f"处理过程中发生错误: {str(e)}")


if __name__ == '__main__':
    main()
