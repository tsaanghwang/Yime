"""
拼音规范化模块 - 处理特殊音质与声调的组合转换
并比较两个拼音字典文件的差异
"""

import os
import json

def normalize_special_pinyin(pinyin_dict):
    """
    规范化包含特殊音质的拼音
    修改后：只处理实际存在于输入字典中的拼音，不自动补充缺失的组合
    """
    # 定义特殊音质和声调
    special_qualities = ["ê", "m", "n", "ng", "hm", "hn", "hng"]
    tones = ["1", "2", "3", "4", "5"]

    # 特殊音质与声调的对应关系
    tone_marks = {
        "1": "\u0304",  # 阴平(第一声) - ̄
        "2": "\u0301",  # 阳平(第二声) - ́
        "3": "\u030C",  # 上声(第三声) - ̌
        "4": "\u0300",  # 去声(第四声) - ̀
        "5": ""         # 轻声(第五声) - 无标记
    }

    # 只处理实际存在于输入字典中的拼音
    for pinyin in list(pinyin_dict.keys()):
        for sq in special_qualities:
            if pinyin.startswith(sq) and len(pinyin) > len(sq):
                tone = pinyin[-1]
                if tone in tones:
                    base = sq
                    # 处理 ê 的特殊情况
                    if sq == "ê":
                        normalized = "ê" + tone_marks[tone]
                    else:
                        # 处理 m/n 系列
                        normalized = base[0] + tone_marks[tone] + base[1:]
                    pinyin_dict[pinyin] = normalized

    return pinyin_dict

def load_json_file(filepath):
    """
    从指定路径加载JSON文件并返回字典
    """
    with open(filepath, 'r', encoding='utf-8') as f:
        return json.load(f)

def compare_pinyin_dicts(dict1, dict2):
    """
    比较两个拼音字典的差异
    修改后：确保使用原始输入字典的键值对
    """
    report = {
        "added": {},
        "removed": {},
        "changed": {},
        "normalization_changes": {}  # 新增字段记录规范化变化
    }

    # 找出新增的项(在dict2中但不在dict1中)
    for key in dict2:
        if key not in dict1:
            report["added"][key] = dict2[key]  # 直接使用dict2的原始值

    # 找出删除的项(在dict1中但不在dict2中)
    for key in dict1:
        if key not in dict2:
            report["removed"][key] = dict1[key]  # 直接使用dict1的原始值

    # 找出值变化的项(在两者中都存在但值不同)
    for key in dict1:
        if key in dict2:
            if dict1[key] != dict2[key]:
                report["changed"][key] = {
                    "old": dict1[key],  # 原始值
                    "new": dict2[key]   # 原始值
                }

    return report

def main():
    # 定义输入输出文件路径
    script_dir = os.path.dirname(os.path.abspath(__file__))
    input_file1 = os.path.join(script_dir, 'pinyin_normalized.json') # 请根据实际情况修改文件名
    input_file2 = os.path.join(script_dir, 'standard_pinyin_reversed.json') # 请根据实际情况修改文件名
    output_file = os.path.join(script_dir, 'compare_report.json')# 输出报告文件名


    try:
        # 加载两个拼音字典文件
        dict1 = load_json_file(input_file1)
        dict2 = load_json_file(input_file2)

        # 规范化处理（但不修改原始字典）
        normalized_dict1 = normalize_special_pinyin(dict1.copy())
        normalized_dict2 = normalize_special_pinyin(dict2.copy())

        # 比较原始字典的差异（不比较规范化后的字典）
        diff_report = compare_pinyin_dicts(dict1, dict2)

        # 如果需要，可以添加规范化信息到报告中
        diff_report["normalization_info"] = {
            "file1_normalized": normalized_dict1,
            "file2_normalized": normalized_dict2
        }

        # 保存差异报告
        save_json_file(diff_report, output_file)

        print(f"比较完成，结果已保存到 {output_file}")
        print(f"新增项: {len(diff_report['added'])}")
        print(f"删除项: {len(diff_report['removed'])}")
        print(f"修改项: {len(diff_report['changed'])}")

    except Exception as e:
        print(f"发生错误: {str(e)}")

def save_json_file(data, filepath):
    """
    将数据保存为JSON文件
    """
    with open(filepath, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

if __name__ == "__main__":
    main()
