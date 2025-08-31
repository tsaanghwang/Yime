import json
from pathlib import Path


def reverse_key_value_pairs(input_path, output_path):
    """
    反转 JSON 文件的键值对

    Args:
        input_path: 输入 JSON 文件路径
        output_path: 输出 JSON 文件路径

    Returns:
        tuple: (是否成功, 原始键值对数量, 新键值对数量)
    """
    try:
        # 读取输入文件
        with open(input_path, 'r', encoding='utf-8') as f:
            data = json.load(f)

        # 初始化统计信息
        original_count = len(data)
        reversed_data = {}

        # 反转键值对
        for k, v in data.items():
            reversed_data[v] = k

        # 写入输出文件
        output_dir = Path(output_path).parent
        output_dir.mkdir(parents=True, exist_ok=True)

        with open(output_path, 'w', encoding='utf-8') as f:
            json.dump(reversed_data, f, ensure_ascii=False, indent=2)

        return True, original_count, original_count  # 新键值对数量与原始相同，因为没有合并

    except Exception as e:
        print(f"Error: {str(e)}")
        return False, 0, 0


if __name__ == "__main__":
    # 使用当前目录下的 yinjie_code.json
    input_file = Path("yinjie_code.json")
    output_file = Path("code_pinyin.json")

    success, original, new = reverse_key_value_pairs(input_file, output_file)

    if success:
        print(f"操作成功完成！")
        print(f"原始键值对数量: {original}")
        print(f"新键值对数量: {new}")
        print(f"结果已保存到: {output_file}")
    else:
        print("操作失败，请检查输入文件是否存在且格式正确。")