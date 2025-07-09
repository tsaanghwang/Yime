#!/usr/bin/env python3
import json
from collections import defaultdict

def analyze_pinyin_difference():
    # 加载当前数据
    with open('pinyin/pinyin_to_hanzi.json', 'r', encoding='utf-8') as f:
        current_data = json.load(f)
    
    # 假设原始数据有1695个拼音，当前有1442个
    # 这里需要原始数据文件，如果没有，我们可以模拟分析
    print("拼音数量差异分析报告")
    print("=====================")
    print(f"修改后总拼音数: {current_data['metadata']['total_pinyin']}")
    
    # 分析多音字情况
    polyphone_chars = []
    for pinyin, chars in current_data['data'].items():
        if len(chars) > 1:
            polyphone_chars.append((pinyin, len(chars)))
    
    print(f"\n多音字统计 (共{len(polyphone_chars)}种拼音):")
    for pinyin, count in sorted(polyphone_chars, key=lambda x: -x[1])[:20]:
        print(f"{pinyin}: {count}个汉字")
    
    # 将结果保存到文件
    with open('pinyin/pinyin_diff_report.txt', 'w', encoding='utf-8') as f:
        f.write("拼音差异分析报告\n")
        f.write("================\n")
        f.write(f"修改后总拼音数: {current_data['metadata']['total_pinyin']}\n")
        f.write(f"修改后总汉字数: {current_data['metadata']['total_hanzi']}\n")
        f.write(f"多音字数量: {current_data['metadata']['polyphone_count']}\n\n")
        
        f.write("多音字示例:\n")
        for pinyin, count in sorted(polyphone_chars, key=lambda x: -x[1])[:50]:
            f.write(f"{pinyin}: {count}个汉字\n")

if __name__ == '__main__':
    analyze_pinyin_difference()