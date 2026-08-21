import json
from pathlib import Path
from typing import Hashable, Union, cast


PathType = Union[str, Path]


def reverse_key_value_pairs(input_path: PathType, output_path: PathType):
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
        input_file = Path(input_path)
        output_file = Path(output_path)

        with open(input_file, 'r', encoding='utf-8') as handle:
            data = cast(dict[str, Hashable], json.load(handle))

        original_count = len(data)
        reversed_data: dict[Hashable, list[str]] = {}
        merge_count = 0

        for key, value in data.items():
            if value in reversed_data:
                reversed_data[value].append(key)
                merge_count += 1
            else:
                reversed_data[value] = [key]

        new_count = len(reversed_data)

        output_dir = output_file.parent
        output_dir.mkdir(parents=True, exist_ok=True)

        with open(output_file, 'w', encoding='utf-8') as handle:
            json.dump(reversed_data, handle, ensure_ascii=False, indent=2)

        return True, original_count, new_count, merge_count

    except Exception as exc:
        print(f"Error: {str(exc)}")
        return False, 0, 0, 0
