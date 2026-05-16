"""Public shim for the reverse-key/value JSON helper."""

from pathlib import Path

from yime.utils.reverse_key_value_pairs import reverse_key_value_pairs

__all__ = ["main", "reverse_key_value_pairs"]


def main() -> int:
    script_dir = Path(__file__).parent.resolve()
    input_file = script_dir.parent / "syllable" / "codec" / "yinjie_code.json"
    output_file = script_dir / "code_pinyin.json"

    success, original, new, merged = reverse_key_value_pairs(input_file, output_file)

    if success:
        print(f"操作成功完成！")
        print(f"原始键值对数量: {original}")
        print(f"新键值对数量: {new}")
        print(f"合并项数量: {merged}")
        print(f"结果已保存到: {output_file}")
        return 0

    print("操作失败，请检查输入文件是否存在且格式正确。")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
