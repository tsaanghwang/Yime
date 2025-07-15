import yaml
import os


def split_yaml(input_file, output_single, output_multi):
    """拆分YAML文件为单字和多字拼音文件"""
    with open(input_file, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    single_char = []
    multi_char = []

    for line in lines:
        line = line.strip()
        if not line:
            continue

        parts = line.split('\t')
        if len(parts) != 2:
            continue

        hanzi, pinyin = parts
        if len(hanzi) == 1:
            single_char.append(f"{hanzi}\t{pinyin}")
        else:
            multi_char.append(f"{hanzi}\t{pinyin}")

    # 写入单字文件
    with open(output_single, 'w', encoding='utf-8') as f:
        f.write('\n'.join(single_char))

    # 写入多字文件
    with open(output_multi, 'w', encoding='utf-8') as f:
        f.write('\n'.join(multi_char))

    print(f"拆分完成: 单字条目 {len(single_char)} 条, 多字条目 {len(multi_char)} 条")


if __name__ == "__main__":
    input_file = os.path.join(os.path.dirname(
        __file__), 'hanzi_pinyin_v2.yaml')
    output_single = os.path.join(
        os.path.dirname(__file__), 'hanzi_pinyin_danzi.yaml')
    output_multi = os.path.join(os.path.dirname(__file__), 'hanzi_pinyin_duozi.yaml')

    split_yaml(input_file, output_single, output_multi)
