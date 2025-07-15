import json
import os
from collections import defaultdict


def extract_pinyin():
    """
    功能：析取由拼音到汉字的映射字典的拼音

    数据转换流程：
    1. 读取JSON文件，析取键值对象的每个音节的拼音
        -  输入格式示例：
    {
        "ai1 yo1": ["哎喲", "唉唷"],
        "an1 le4 yi3": ["安樂椅"],
        "an1 na4 ka3 lie4 ni2 na4": ["安娜·卡列尼娜"],
        ...
    }
    2. 检查不带调的拼音并作记录
    3. 按拼音首字母排序
    4. 构建字典结构：以带调拼音为键和值（键值相同）
        -  输出格式示例：
    {
        "a1": "a1",
        "ba1": "ba1",
        ...,
        "zui4": "zui4"
    }
    5. 将最终字典以JSON格式保存到指定文件
    """
    # 定义输入输出文件路径
    script_dir = os.path.dirname(os.path.abspath(__file__))
    input_file = os.path.join(script_dir, 'pinyin_duozi.json')
    output_file = os.path.join(script_dir, 'pinyin_2.json')

    # 读取输入JSON文件
    with open(input_file, 'r', encoding='utf-8') as f:
        pinyin_data = json.load(f)

    # 存储所有单个拼音音节
    pinyin_set = set()
    
    # 遍历所有拼音键，分割成单个音节并添加到集合中
    for pinyin_key in pinyin_data.keys():
        syllables = pinyin_key.split()
        pinyin_set.update(syllables)

    # 将集合转换为排序列表
    sorted_pinyin = sorted(list(pinyin_set))

    # 创建最终的字典，键和值相同
    result_dict = {pinyin: pinyin for pinyin in sorted_pinyin}

    # 保存结果到JSON文件
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(result_dict, f, ensure_ascii=False, indent=4)

    return result_dict


if __name__ == "__main__":
    extract_pinyin()
