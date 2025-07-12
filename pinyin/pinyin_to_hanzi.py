# 读取pinyin\hanzi_to_pinyin.yaml文件数据
# 创建由带调拼音到汉字的映射字典
# 1. 保留原yaml文件包含的所有不同的拼音形式
# 2. 保留每个不同的拼音对应的所有的不同字词
# 3. 生成字典写入pinyin/pinyin_to_hanzi.json文件

import os
import yaml
import json
from collections import defaultdict


def convert_yaml_to_json(yaml_file, json_file):
    # 初始化字典，使用defaultdict自动处理重复键
    pinyin_to_hanzi = defaultdict(list)

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

            # 添加到字典中
            pinyin_to_hanzi[pinyin].append(hanzi)

    # 转换为普通字典（非defaultdict）以便JSON序列化
    result = dict(pinyin_to_hanzi)

    # 写入JSON文件
    with open(json_file, 'w', encoding='utf-8') as f:
        json.dump(result, f, ensure_ascii=False, indent=2)

    return result


if __name__ == "__main__":
    input_file = os.path.join(os.path.dirname(__file__), "hanzi_to_pinyin.yaml")
    output_file = os.path.join(os.path.dirname(
        __file__), "pinyin_to_hanzi.json")

    print(f"正在从 {input_file} 转换数据...")
    mapping = convert_yaml_to_json(input_file, output_file)
    print(f"转换完成！结果已保存到 {output_file}")
    print(f"共处理了 {len(mapping)} 个不同的拼音")
