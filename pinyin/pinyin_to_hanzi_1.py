# 拼音到汉字转换工具
# 功能：从YAML格式的拼音数据文件创建拼音到汉字的映射字典
#
# 处理流程：
# 1. 读取YAML文件，解析每行的汉字和带调拼音
# 2. 构建字典结构：带调拼音作为键，只保留第一个对应的汉字作为值
# 3. 筛选不同形式的拼音（单字和多字词内部的拼音）
# 4. 检查不带调的拼音并记录
# 5. 按拼音首字母排序
# 6. 将最终字典以JSON格式保存到指定文件
#
# 输入文件格式要求：
# - 每行包含汉字和拼音，以制表符分隔
# - 示例格式："汉字\tpinyin1 pinyin2"
#
# 输出格式：
# - JSON字典，结构为{"pinyin": "汉字1"}

import yaml
import json
import os
import re
from collections import defaultdict

def has_toneless_pinyin(pinyin_list):
    """检查拼音列表中是否存在不带调的拼音"""
    for pinyin in pinyin_list:
        if not any(char.isdigit() for char in pinyin):
            return True
    return False

def extract_all_pinyin(pinyin_str):
    """从拼音字符串中提取所有拼音形式（包括多字词内部的拼音）"""
    # 分割拼音字符串为单独的拼音
    pinyin_list = pinyin_str.split()
    
    # 收集所有拼音形式
    all_pinyin = []
    for pinyin in pinyin_list:
        # 标准化拼音形式（可选）
        standardized = pinyin.lower().replace("ü", "v")
        all_pinyin.append(standardized)
    
    return all_pinyin

def convert_pinyin_to_dict(yaml_file, json_file):
    """将YAML格式的拼音数据转换为拼音到汉字的映射字典

    Args:
        yaml_file: 输入的YAML文件路径
        json_file: 输出的JSON文件路径

    Returns:
        生成的拼音到汉字映射字典
    """
    # 初始化字典，每个拼音只保留第一个对应的汉字
    pinyin_to_hanzi = {}
    # 用于记录所有遇到的拼音形式
    all_pinyin_forms = set()
    # 用于记录不带调的拼音
    toneless_pinyin_found = False

    try:
        with open(yaml_file, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue

                # 分割汉字和拼音，只取前两部分
                parts = line.split('\t')
                if len(parts) < 2:
                    print(f"警告：跳过格式不正确的行: {line}")
                    continue

                hanzi, pinyin = parts[0], parts[1]
                
                # 提取所有拼音形式
                pinyin_forms = extract_all_pinyin(pinyin)
                all_pinyin_forms.update(pinyin_forms)
                
                # 检查是否有不带调的拼音
                if not toneless_pinyin_found and has_toneless_pinyin(pinyin_forms):
                    toneless_pinyin_found = True
                
                # 只保留第一个出现的汉字
                for pinyin_form in pinyin_forms:
                    if pinyin_form not in pinyin_to_hanzi:
                        pinyin_to_hanzi[pinyin_form] = hanzi

        # 按拼音首字母排序
        sorted_pinyin = sorted(pinyin_to_hanzi.items(), key=lambda x: x[0])
        pinyin_to_hanzi = dict(sorted_pinyin)
        
        # 记录不带调拼音的情况
        if toneless_pinyin_found:
            print("提示：发现不带调的拼音形式")
        else:
            print("提示：所有拼音都带有声调标记")

        # 确保输出目录存在
        os.makedirs(os.path.dirname(json_file), exist_ok=True)
        
        # 写入JSON文件
        with open(json_file, 'w', encoding='utf-8') as f:
            json.dump(pinyin_to_hanzi, f, ensure_ascii=False, indent=2)

        return pinyin_to_hanzi
        
    except FileNotFoundError:
        print(f"错误：找不到输入文件 {yaml_file}")
        print(f"当前工作目录: {os.getcwd()}")
        print(f"请确保文件存在且路径正确")
        return None
    except Exception as e:
        print(f"处理过程中发生错误: {str(e)}")
        return None

if __name__ == "__main__":
    # 获取脚本所在目录的父目录
    script_dir = os.path.dirname(os.path.abspath(__file__))
    parent_dir = os.path.dirname(script_dir)
    
    # 修正路径 - 直接从脚本所在目录(pinyin)查找文件
    input_file = os.path.join(script_dir, "toned_pinyin.yaml")
    output_file = os.path.join(script_dir, "pinyin_to_single_hanzi.json")

    print(f"正在从 {input_file} 转换数据...")
    mapping = convert_pinyin_to_dict(input_file, output_file)
    if mapping is not None:
        print(f"转换完成！结果已保存到 {output_file}")
        print(f"共处理了 {len(mapping)} 个不同的拼音形式")