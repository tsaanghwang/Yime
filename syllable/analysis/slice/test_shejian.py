#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from ganyin_categorizer import GanyinCategorizer
import json


def test_shejian_processing():
    """测试舌尖音处理功能"""
    print("=== 舌尖音处理功能测试 ===")

    # 读取实际数据
    try:
        with open('ganyin.json', 'r', encoding='utf-8') as f:
            data = json.load(f)
        ganyin_data = data['ganyin']
    except FileNotFoundError:
        print("错误: ganyin.json 文件不存在，请先运行 ganyin.py")
        return

    # 统计舌尖音
    shejian_count = 0
    normal_i_count = 0

    print("\n1. 舌尖音干音（声母为 z,c,s,zh,ch,sh,r + i）:")
    for key, value in sorted(ganyin_data.items()):
        if key.startswith('_i'):
            print(f"  {key}: {value}")
            shejian_count += 1

    print(f"\n舌尖音干音总数: {shejian_count}")

    print("\n2. 普通 i 音干音（其他声母 + i）:")
    for key, value in sorted(ganyin_data.items()):
        if key.startswith('i') and not key.startswith('_i'):
            if normal_i_count < 5:  # 只显示前5个
                print(f"  {key}: {value}")
            normal_i_count += 1

    if normal_i_count > 5:
        print(f"  ... 还有 {normal_i_count - 5} 个")

    print(f"\n普通 i 音干音总数: {normal_i_count}")

    print("\n3. 验证 '_i' 的分类:")
    category = GanyinCategorizer.categorize('_i')
    print(f"  '_i' 分类为: {category}")

    print("\n4. 验证韵母数据完整性:")
    all_finals = GanyinCategorizer.get_all_finals()
    for cat_name, finals in all_finals.items():
        if '_i' in finals:
            print(f"  '_i' 已包含在 {cat_name} 中 ✓")

    print("\n测试完成！")


if __name__ == "__main__":
    test_shejian_processing()
