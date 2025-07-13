# pinyin/merge_pinyin.py
from collections import defaultdict


def merge_duplicate_pinyin(input_file, output_file):
    # 读取原始文件
    with open(input_file, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    # 使用字典存储每个汉字对应的所有拼音
    pinyin_dict = defaultdict(list)

    for line in lines:
        line = line.strip()
        if not line:
            continue
        # 处理可能的多音字情况
        parts = line.split('\t')
        if len(parts) < 2:
            continue  # 跳过格式不正确的行
        char = parts[0]
        pinyin = parts[1]
        # 如果拼音中包含逗号，说明是多音字，先分割开
        for single_pinyin in pinyin.split(','):
            pinyin_dict[char].append(single_pinyin)

    # 合并重复的拼音
    merged_lines = []
    for char, pinyins in pinyin_dict.items():
        # 去重并保持原始顺序
        unique_pinyins = []
        seen = set()
        for pinyin in pinyins:
            if pinyin not in seen:
                seen.add(pinyin)
                unique_pinyins.append(pinyin)
        merged_line = f"{char}\t{','.join(unique_pinyins)}"
        merged_lines.append(merged_line)

    # 写入新文件
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write('\n'.join(merged_lines))


if __name__ == "__main__":
    input_file = 'pinyin/hanzi_to_pinyin.yaml'
    output_file = 'pinyin/toned_pinyin_merged.yaml'
    merge_duplicate_pinyin(input_file, output_file)
    print(f"合并完成，结果已保存到 {output_file}")
