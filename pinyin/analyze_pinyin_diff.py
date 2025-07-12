#!/usr/bin/env python3
import json
from collections import defaultdict

def load_data():
    with open('pinyin/pinyin_to_hanzi.json', 'r', encoding='utf-8') as f:
        toned_data = json.load(f)
    with open('pinyin/pinyin_to_hanzi.json', 'r', encoding='utf-8') as f:
        pinyin_data = json.load(f)
    return toned_data, pinyin_data

def analyze_pinyin_diff(toned_data, pinyin_data):
    # 收集单字拼音
    single_pinyin = set()
    for char, pinyins in toned_data.items():
        if len(char) == 1:  # 单字
            for pinyin in pinyins:
                single_pinyin.add(pinyin.split('%')[0].strip())
    
    # 收集多字词拼音
    multi_pinyin = set()
    for phrase, pinyins in toned_data.items():
        if len(phrase) > 1:  # 多字词
            for pinyin in pinyins:
                multi_pinyin.add(pinyin.split('%')[0].strip())
    
    # 找出多字词有但单字没有的拼音
    diff_pinyin = multi_pinyin - single_pinyin
    
    # 找出这些拼音对应的单字(从pinyin_to_hanzi.json中查找)
    result = defaultdict(list)
    for pinyin in sorted(diff_pinyin):
        if pinyin in pinyin_data['data']:
            result[pinyin] = pinyin_data['data'][pinyin]
    
    return result

if __name__ == '__main__':
    toned_data, pinyin_data = load_data()
    diff = analyze_pinyin_diff(toned_data, pinyin_data)
    
    print("多字词中存在但单字中缺失的拼音及对应汉字:")
    for pinyin, chars in diff.items():
        print(f"{pinyin}: {', '.join(chars)}")
    
    print(f"\n总计: {len(diff)}个拼音")