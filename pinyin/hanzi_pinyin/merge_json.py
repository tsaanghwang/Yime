import json
import os
from collections import OrderedDict


def merge_json_files():
    """
    功能：合并两个拼音JSON文件

    数据转换流程：
    1. 读取两个输入JSON文件
    2. 合并两个字典的键值对
    3. 按拼音首字母排序
    4. 保存合并后的结果到新文件
    """
    # 定义输入输出文件路径
    script_dir = os.path.dirname(os.path.abspath(__file__))
    input_file1 = os.path.join(script_dir, 'pinyin_1.json')
    input_file2 = os.path.join(script_dir, 'pinyin_2.json')
    output_file = os.path.join(script_dir, 'pinyin.json')

    # 读取第一个JSON文件
    try:
        with open(input_file1, 'r', encoding='utf-8') as f:
            pinyin_dict1 = json.load(f)
    except FileNotFoundError:
        print(f"错误：输入文件 {input_file1} 不存在")
        return
    except json.JSONDecodeError:
        print(f"错误：输入文件 {input_file1} 不是有效的JSON格式")
        return

    # 读取第二个JSON文件
    try:
        with open(input_file2, 'r', encoding='utf-8') as f:
            pinyin_dict2 = json.load(f)
    except FileNotFoundError:
        print(f"错误：输入文件 {input_file2} 不存在")
        return
    except json.JSONDecodeError:
        print(f"错误：输入文件 {input_file2} 不是有效的JSON格式")
        return

    # 合并两个字典
    # 如果键相同，pinyin_dict2的值会覆盖pinyin_dict1的值
    merged_dict = {**pinyin_dict1, **pinyin_dict2}

    # 按拼音首字母排序
    sorted_pinyin = OrderedDict(
        sorted(merged_dict.items(), key=lambda x: x[0].lower()))

    # 保存到输出文件
    try:
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(sorted_pinyin, f, ensure_ascii=False, indent=2)
        print(f"成功合并拼音字典，已保存到 {output_file}")
    except IOError as e:
        print(f"保存文件时出错: {e}")


if __name__ == "__main__":
    merge_json_files()
