import json
import os
from collections import defaultdict


def create_pinyin_to_hanzi_mapping():
    """
    创建由拼音到汉字的映射字典

    数据转换流程：
    1. 读取JSON文件，解析每行带调拼音
    2. 检查不带调的拼音并记录
    3. 构建字典结构：以带调拼音为键，以对应的不同汉字为值
    4. 按拼音首字母排序
    5. 将最终字典以JSON格式保存到指定文件
    """
    # 定义输入输出文件路径 - 使用os.path.join确保跨平台兼容性
    script_dir = os.path.dirname(os.path.abspath(__file__))
    input_file = os.path.join(script_dir, 'danzi_pinyin.json')
    output_file = os.path.join(script_dir, 'pinyin_danzi.json')

    try:
        # 1. 读取输入JSON文件
        with open(input_file, 'r', encoding='utf-8') as f:
            hanzi_to_pinyin = json.load(f)

        # 2. 构建拼音到汉字的映射字典
        pinyin_to_hanzi = defaultdict(list)

        for hanzi, pinyins in hanzi_to_pinyin.items():
            for pinyin in pinyins:
                pinyin_to_hanzi[pinyin].append(hanzi)

        # 3. 按拼音首字母排序
        sorted_pinyin_to_hanzi = dict(
            sorted(pinyin_to_hanzi.items(), key=lambda x: x[0]))

        # 4. 保存结果到输出文件
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(sorted_pinyin_to_hanzi, f, ensure_ascii=False, indent=2)

        print(f"转换完成，结果已保存到: {output_file}")
        return True

    except Exception as e:
        print(f"转换过程中发生错误: {str(e)}")
        return False


if __name__ == '__main__':
    create_pinyin_to_hanzi_mapping()
