import json
from pathlib import Path

def reverse_key_value_pairs(input_path, output_path):
    """
    反转 JSON 文件的键值对，所有值统一用列表表示。
    若有多个键对应同一个值，则值对应一个键列表。

    Args:
        input_path: 输入 JSON 文件路径
        output_path: 输出 JSON 文件路径

    Returns:
        tuple: (是否成功, 原始键值对数量, 新键值对数量, 合并项数量)
    """
    try:
        # 读取输入文件
        with open(input_path, 'r', encoding='utf-8') as f:
            data = json.load(f)

        original_count = len(data)
        reversed_data = {}
        merge_count = 0

        # 反转键值对，所有值统一用列表表示
        for k, v in data.items():
            if v in reversed_data:
                reversed_data[v].append(k)
                merge_count += 1
            else:
                reversed_data[v] = [k]

        new_count = len(reversed_data)

        # 写入输出文件
        output_dir = Path(output_path).parent
        output_dir.mkdir(parents=True, exist_ok=True)

        with open(output_path, 'w', encoding='utf-8') as f:
            json.dump(reversed_data, f, ensure_ascii=False, indent=2)

        return True, original_count, new_count, merge_count

    except Exception as e:
        print(f"Error: {str(e)}")
        return False, 0, 0, 0

if __name__ == "__main__":
    script_dir = Path(__file__).parent.resolve()
    input_file = script_dir.parent / "syllable_codec" / "yinjie_code.json"
    output_file = script_dir / "code_pinyin.json"

    success, original, new, merged = reverse_key_value_pairs(input_file, output_file)

    if success:
        print(f"操作成功完成！")
        print(f"原始键值对数量: {original}")
        print(f"新键值对数量: {new}")
        print(f"合并项数量: {merged}")
        print(f"结果已保存到: {output_file}")
    else:
        print("操作失败，请检查输入文件是否存在且格式正确。")
