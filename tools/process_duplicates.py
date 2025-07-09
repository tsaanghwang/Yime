import json
from collections import defaultdict

def transform_multi_value_json(input_file, output_file):
    # 读取原始JSON文件
    with open(input_file, 'r', encoding='utf-8') as f:
        data = json.load(f)
    
    # 创建新的数据结构，处理多值对应
    new_data = defaultdict(list)
    
    # 遍历原始数据，收集所有对应关系
    for ipa, pinyin in data.items():
        new_data[ipa].append(pinyin)
    
    # 将defaultdict转换为普通dict
    result = dict(new_data)
    
    # 写入新文件
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(result, f, indent=2, ensure_ascii=False)
    
    print(f"转换完成，结果已保存到 {output_file}")

# 使用示例
input_path = 'pinyin/yunmu_de_IPA.json'
output_path = 'pinyin/yunmu_de_IPA_transformed.json'
transform_multi_value_json(input_path, output_path)