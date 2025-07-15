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
    5. 检查成音节辅音字母及其组合
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

    # 检查成音节辅音字母及其组合
    check_syllabic_consonants(merged_dict)

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


def check_syllabic_consonants(pinyin_dict):
    """
    检查字典中是否存在由成音节的辅音字母及其组合构成的音节

    参数:
        pinyin_dict: 合并后的拼音字典
    """
    syllabic_consonants = ["m", "n", "ng", "hm", "r"]
    tones = ["1", "2", "3", "4", "5"]

    # 检查由成音节辅音+调号构成的音节
    consonant_with_tone = False
    found_syllables = []  # 存储找到的音节
    for consonant in syllabic_consonants:
        for tone in tones:
            syllable = f"{consonant}{tone}"
            if syllable in pinyin_dict:
                consonant_with_tone = True
                found_syllables.append(syllable)
                # 特殊处理r5
                if syllable == "r5":
                    if "er5" not in pinyin_dict:
                        pinyin_dict["er5"] = "er5"
                    del pinyin_dict["r5"]
                    print('已处理音节"r5"，添加了"er5"条目并删除"r5"')

    if consonant_with_tone:
        if found_syllables:
            print(f"字典中存在由调号与成音节的辅音构成的音节: {', '.join(found_syllables)}")
        else:
            print("字典中存在由调号与成音节的辅音构成的音节")

    # 检查只包含成音节辅音的音节
    consonant_only = False
    for consonant in syllabic_consonants:
        if consonant in pinyin_dict:
            consonant_only = True
            break

    if consonant_only:
        print("字典中存在只包含成音节的辅音字母及其组合充当的音节")


if __name__ == "__main__":
    merge_json_files()
