"""
拼音规范化模块 - 处理特殊音质与声调的组合转换
并比较两个拼音字典文件的差异
"""

import os
import json

from utils.pinyin_normalizer import normalize_dict_existing_only

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
    input_file1 = os.path.join(script_dir, 'pinyin.json') # 请根据实际情况修改文件名
    input_file2 = os.path.join(script_dir, 'standard_pinyin_reversed.json') # 请根据实际情况修改文件名
    output_file = os.path.join(script_dir, 'compare_report.json')# 输出报告文件名

    try:
        # 加载两个拼音字典文件
        dict1 = load_json_file(input_file1)
        dict2 = load_json_file(input_file2)

        # 规范化处理（但不修改原始字典）
        normalized_dict1, _ = normalize_dict_existing_only(dict1)
        normalized_dict2, _ = normalize_dict_existing_only(dict2)

        # 比较原始字典的差异（不比较规范化后的字典）
        diff_report = compare_pinyin_dicts(dict1, dict2)

        # 如果需要，可以添加规范化信息到报告中
        diff_report["normalization_info"] = {
            "file1_normalized": normalized_dict1,
            "file2_normalized": normalized_dict2
        }

        # 保存差异报告
        save_json_file(diff_report, output_file)

        # 将新增项添加到input_file1中
        if diff_report["added"]:
            # 以键为值的方式更新字典
            dict1.update({k: k for k in diff_report["added"].keys()})
            save_json_file(dict1, input_file1)
            print(f"已将 {len(diff_report['added'])} 个新增项添加到 {input_file1}")

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
