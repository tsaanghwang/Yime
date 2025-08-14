import json
import os
from collections import defaultdict, OrderedDict

def extract_pinyin():
    """
    功能：合并提取单字和多字拼音，生成统一的拼音字典

    数据转换流程：
    1. 读取两个输入JSON文件：
       - pinyin_danzi.json (单字拼音)
       - pinyin_duozi.json (多字拼音)
    2. 提取所有带调的拼音音节
    3. 合并并去重所有拼音
    4. 检查成音节辅音字母及其组合
    5. 检查特殊韵母"eh"构成的音节并进行替换
    6. 按拼音首字母排序
    7. 构建字典结构：以带调拼音为键和值（键值相同）
    8. 将最终字典以JSON格式保存到pinyin.json

    输出格式示例：
    {
        "a1": "a1",
        "ba1": "ba1",
        ...,
        "zui4": "zui4"
    }
    """
    # 定义输入输出文件路径
    script_dir = os.path.dirname(os.path.abspath(__file__))
    input_danzi = os.path.join(script_dir, 'pinyin_danzi.json')
    input_duozi = os.path.join(script_dir, 'pinyin_duozi.json')
    output_file = os.path.join(script_dir, 'pinyin.json')

    # 存储所有拼音
    pinyin_set = set()
    invalid_pinyin = []

    # 处理单字拼音文件
    try:
        with open(input_danzi, 'r', encoding='utf-8') as f:
            pinyin_danzi_dict = json.load(f)

        for pinyin in pinyin_danzi_dict.keys():
            if pinyin[-1].isdigit() and 1 <= int(pinyin[-1]) <= 5:
                pinyin_set.add(pinyin)
            else:
                invalid_pinyin.append(pinyin)
    except FileNotFoundError:
        print(f"警告：单字拼音文件 {input_danzi} 不存在，跳过处理")
    except json.JSONDecodeError:
        print(f"错误：单字拼音文件 {input_danzi} 不是有效的JSON格式")
        return

    # 处理多字拼音文件
    try:
        with open(input_duozi, 'r', encoding='utf-8') as f:
            pinyin_duozi_dict = json.load(f)

        for pinyin_key in pinyin_duozi_dict.keys():
            syllables = pinyin_key.split()
            for syllable in syllables:
                if syllable[-1].isdigit() and 1 <= int(syllable[-1]) <= 5:
                    pinyin_set.add(syllable)
                else:
                    invalid_pinyin.append(syllable)
    except FileNotFoundError:
        print(f"警告：多字拼音文件 {input_duozi} 不存在，跳过处理")
    except json.JSONDecodeError:
        print(f"错误：多字拼音文件 {input_duozi} 不是有效的JSON格式")
        return

    # 记录无效拼音（不带调）
    if invalid_pinyin:
        print(f"发现 {len(invalid_pinyin)} 个不带调的拼音:")
        print(", ".join(invalid_pinyin))

    # 构建临时字典用于检查
    temp_dict = {pinyin: pinyin for pinyin in pinyin_set}

    # 检查成音节辅音字母及其组合
    check_syllabic_consonants(temp_dict)

    # 检查特殊韵母"eh"构成的音节并进行替换
    check_eh_syllables(temp_dict)

    # 更新拼音集合
    pinyin_set = set(temp_dict.keys())

    # 按拼音首字母排序
    sorted_pinyin = sorted(pinyin_set, key=lambda x: x.lower())

    # 构建输出字典
    pinyin_dict = OrderedDict((pinyin, pinyin) for pinyin in sorted_pinyin)

    # 保存到输出文件
    try:
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(pinyin_dict, f, ensure_ascii=False, indent=2)
        print(f"成功生成合并的拼音字典，已保存到 {output_file}")
    except IOError as e:
        print(f"保存文件时出错: {e}")

def check_syllabic_consonants(pinyin_dict):
    """
    无条件添加所有可能的成音节辅音字母及其组合与调号构成的音节到字典中，
    并将"r+调号"音节替换为"er+调号"
    """
    syllabic_consonants = ["m", "n", "ng", "hm", "r"]
    tones = ["1", "2", "3", "4", "5"]

    added_syllables = []
    existing_syllables = []

    # 无条件添加所有可能的 syllabic_consonant+tone 音节
    for consonant in syllabic_consonants:
        for tone in tones:
            syllable = f"{consonant}{tone}"
            if syllable not in pinyin_dict:
                pinyin_dict[syllable] = syllable
                added_syllables.append(syllable)
            else:
                existing_syllables.append(syllable)

    # 打印总结信息
    if added_syllables:
        print(f'已添加以下成音节辅音字母音节到字典中: {", ".join(added_syllables)}')
    if existing_syllables:
        print(f'字典中已存在以下成音节辅音字母音节: {", ".join(existing_syllables)}')

    # 特殊处理"r+调号"的情况，替换为"er+调号"
    replaced = []
    for tone in tones:
        r_syllable = f"r{tone}"
        er_syllable = f"er{tone}"
        if r_syllable in pinyin_dict:
            pinyin_dict[er_syllable] = pinyin_dict.pop(r_syllable)
            replaced.append(f"{r_syllable}→{er_syllable}")

    if replaced:
        print(f'已替换所有 r+调号 音节为 er+调号: {", ".join(replaced)}')

def check_eh_syllables(pinyin_dict):
    """
    检查字典中是否存在由特殊韵母"eh"与调号构成的音节，并进行相应替换

    参数:
        pinyin_dict: 合并后的拼音字典

    功能:
        1. 无条件添加所有可能的 "ê+tone" 音节到字典中
        2. 报告输入文件中存在的 "eh+tone" 音节情况
        3. 将"eh+调号"替换为"ê+调号"
    """
    tones = ["1", "2", "3", "4", "5"]

    # 无条件添加所有可能的 ê+tone 音节
    added = []
    for tone in tones:
        e_syllable = f"ê{tone}"
        if e_syllable not in pinyin_dict:
            pinyin_dict[e_syllable] = e_syllable
            added.append(e_syllable)

    if added:
        print(f'已添加所有 ê+调号 音节到字典中: {", ".join(added)}')

    # 检查输入文件中存在的 eh+tone 音节
    eh_syllables = [f"eh{tone}" for tone in tones if f"eh{tone}" in pinyin_dict]

    if eh_syllables:
        print(f"输入文件中存在以下 eh+tone 音节: {', '.join(eh_syllables)}")
    else:
        print("输入文件中未发现 eh+tone 音节")

    # 执行替换逻辑
    replaced = []
    for eh_syllable in eh_syllables:
        tone = eh_syllable[2:]  # 获取调号部分
        e_syllable = f"ê{tone}"
        pinyin_dict[e_syllable] = pinyin_dict.pop(eh_syllable)
        replaced.append(f"{eh_syllable}→{e_syllable}")

    if replaced:
        print(f'已替换所有 eh+调号 音节为 ê+调号: {", ".join(replaced)}')

if __name__ == "__main__":
    extract_pinyin()