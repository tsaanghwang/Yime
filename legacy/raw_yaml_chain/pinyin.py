#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
拼音处理模块

功能：
1. 合并单字和多字拼音数据
2. 处理特殊拼音形式（成音节辅音、ê韵母）
3. 生成微软拼音输入法兼容的v替代u变体
4. 输出用末位数字来标调的拼音字典

主要函数：
- extract_pinyin(): 主处理流程
- check_syllabic_consonants(): 处理辅音音节
- check_eh_syllables(): 处理特殊韵母
- add_msime_style_pinyin(): 添加微软拼音变体
"""

import json
import os
from collections import defaultdict, OrderedDict

# 常量定义
SYLLABIC_CONSONANTS = ["m", "n", "ng", "hm", "hn", "hng", "r"]
TONES = ["1", "2", "3", "4", "5"]
MSIME_PREFIXES = ("ju", "qu", "xu", "yu")

def extract_pinyin():
    """合并提取单字和多字拼音，生成统一的拼音字典

    处理流程：
    1. 读取单字(pinyin_danzi.json)和多字(pinyin_duozi.json)拼音文件
    2. 提取所有带调拼音并合并去重
    3. 处理特殊拼音形式（辅音音节、ê韵母）
    4. 添加微软拼音变体
    5. 按拼音首字母排序并输出到pinyin.json

    返回: None
    """
    # 文件路径配置
    script_dir = os.path.dirname(os.path.abspath(__file__))
    input_danzi = os.path.join(script_dir, 'pinyin_danzi.json')
    input_duozi = os.path.join(script_dir, 'pinyin_duozi.json')
    output_file = os.path.join(script_dir, 'pinyin.json')

    pinyin_set = set()
    invalid_pinyin = []

    # 处理单字拼音文件
    _process_pinyin_file(input_danzi, pinyin_set, invalid_pinyin, "单字")

    # 处理多字拼音文件
    _process_pinyin_file(input_duozi, pinyin_set, invalid_pinyin, "多字")

    # 输出无效拼音警告
    if invalid_pinyin:
        print(f"发现 {len(invalid_pinyin)} 个不带调的拼音:")
        print(", ".join(invalid_pinyin))

    # 构建临时字典并处理特殊拼音
    temp_dict = {pinyin: pinyin for pinyin in pinyin_set}
    check_syllabic_consonants(temp_dict)
    check_eh_syllables(temp_dict)

    # 先添加微软拼音变体
    add_msime_style_pinyin(temp_dict)

    # 然后排序并构建最终字典
    sorted_pinyin = sorted(temp_dict.keys(), key=lambda x: x.lower())
    pinyin_dict = OrderedDict((pinyin, pinyin) for pinyin in sorted_pinyin)

    # 保存结果
    _save_pinyin_dict(output_file, pinyin_dict)

def _process_pinyin_file(file_path, pinyin_set, invalid_pinyin, file_type):
    """处理单个拼音文件，提取有效拼音"""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            pinyin_dict = json.load(f)

        for pinyin_key in pinyin_dict.keys():
            # 多字拼音需要分割处理
            syllables = pinyin_key.split() if file_type == "多字" else [pinyin_key]

            for syllable in syllables:
                if syllable[-1].isdigit() and 1 <= int(syllable[-1]) <= 5:
                    pinyin_set.add(syllable)
                else:
                    invalid_pinyin.append(syllable)

    except FileNotFoundError:
        print(f"警告：{file_type}拼音文件 {file_path} 不存在，跳过处理")
    except json.JSONDecodeError:
        print(f"错误：{file_type}拼音文件 {file_path} 不是有效的JSON格式")

def _save_pinyin_dict(output_file, pinyin_dict):
    """保存拼音字典到文件"""
    try:
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(pinyin_dict, f, ensure_ascii=False, indent=2)
        print(f"成功生成合并的拼音字典，已保存到 {output_file}")
    except IOError as e:
        print(f"保存文件时出错: {e}")

def check_syllabic_consonants(pinyin_dict):
    """处理成音节辅音字母及其组合

    1. 添加所有可能的辅音+调号组合
    2. 将"r+调号"替换为"er+调号"
    """
    added = []
    existing = []

    # 添加所有可能的辅音+调号组合
    for consonant in SYLLABIC_CONSONANTS:
        for tone in TONES:
            syllable = f"{consonant}{tone}"
            if syllable not in pinyin_dict:
                pinyin_dict[syllable] = syllable
                added.append(syllable)
            else:
                existing.append(syllable)

    # 输出处理结果
    if added:
        print(f'已添加成音节辅音字母音节: {", ".join(added)}')
    if existing:
        print(f'已存在成音节辅音字母音节: {", ".join(existing)}')

    # 特殊处理r→er替换
    replaced = []
    for tone in TONES:
        r_syllable = f"r{tone}"
        er_syllable = f"er{tone}"
        if r_syllable in pinyin_dict:
            pinyin_dict[er_syllable] = pinyin_dict.pop(r_syllable)
            replaced.append(f"{r_syllable}→{er_syllable}")

    if replaced:
        print(f'已替换r+调号为er+调号: {", ".join(replaced)}')

def check_eh_syllables(pinyin_dict):
    """处理特殊韵母"eh"构成的音节

    1. 添加所有ê+调号组合
    2. 将eh+调号替换为ê+调号
    """
    # 添加ê+调号
    added = [f"ê{tone}" for tone in TONES
             if f"ê{tone}" not in pinyin_dict]
    for syllable in added:
        pinyin_dict[syllable] = syllable

    if added:
        print(f'已添加ê+调号音节: {", ".join(added)}')

    # 处理eh→ê替换
    eh_syllables = [f"eh{tone}" for tone in TONES
                   if f"eh{tone}" in pinyin_dict]
    replaced = []

    for eh_syllable in eh_syllables:
        tone = eh_syllable[2:]
        e_syllable = f"ê{tone}"
        pinyin_dict[e_syllable] = pinyin_dict.pop(eh_syllable)
        replaced.append(f"{eh_syllable}→{e_syllable}")

    if replaced:
        print(f'已替换eh+调号为ê+调号: {", ".join(replaced)}')

def add_msime_style_pinyin(pinyin_dict):
    """添加微软拼音风格的v替代u变体

    对ju/qu/xu/yu开头的拼音，创建u→v变体
    """
    msime_pinyins = {}
    count = 0

    for pinyin in list(pinyin_dict.keys()):
        if pinyin.startswith(MSIME_PREFIXES) and 'v' not in pinyin:
            new_pinyin = pinyin.replace('u', 'v', 1)
            msime_pinyins[new_pinyin] = new_pinyin
            count += 1

    pinyin_dict.update(msime_pinyins)
    print(f"已添加 {count} 个微软拼音风格(v替代u)的拼音变体")

if __name__ == "__main__":
    extract_pinyin()