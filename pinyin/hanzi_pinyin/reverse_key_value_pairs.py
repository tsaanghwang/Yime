import json
from pathlib import Path
import os

def reverse_key_value_pairs(input_path, output_path):
    """
    反转 JSON 文件的键值对，并检查是否有合并

    Args:
        input_path: 输入 JSON 文件路径
        output_path: 输出 JSON 文件路径

    Returns:
        tuple: (是否成功, 原始键值对数量, 新键值对数量, 是否有合并)
    """
    try:
        # 读取输入文件
        with open(input_path, 'r', encoding='utf-8') as f:
            data = json.load(f)

        # 初始化统计信息
        original_count = len(data)
        new_count = 0
        reversed_data = {}

        # 反转键值对
        for k, v in data.items():
            # 如果值已经作为键存在，则合并
            if v in reversed_data:
                if isinstance(reversed_data[v], list):
                    reversed_data[v].append(k)
                else:
                    reversed_data[v] = [reversed_data[v], k]
            else:
                reversed_data[v] = k
                new_count += 1

        # 检查是否有合并
        has_merge = original_count > new_count

        # 写入输出文件
        output_dir = Path(output_path).parent
        output_dir.mkdir(parents=True, exist_ok=True)

        with open(output_path, 'w', encoding='utf-8') as f:
            json.dump(reversed_data, f, ensure_ascii=False, indent=2)

        return True, original_count, new_count, has_merge

    except Exception as e:
        print(f"Error: {str(e)}")
        return False, 0, 0, False


if __name__ == "__main__":
    # 使用从项目根目录开始的绝对路径
    script_dir = os.path.dirname(os.path.abspath(__file__))
    input_file = os.path.join(script_dir, 'standard_pinyin.json')
    output_file = os.path.join(script_dir, 'standard_pinyin_reversed.json')

    success, original, new, merged = reverse_key_value_pairs(
        input_file, output_file)

    if success:
        print(f"操作成功完成！")
        print(f"原始键值对数量: {original}")
        print(f"新键值对数量: {new}")
        print(f"是否有合并: {'是' if merged else '否'}")
        print(f"结果已保存到: {output_file}")
    else:
        print("操作失败，请检查输入文件是否存在且格式正确。")
