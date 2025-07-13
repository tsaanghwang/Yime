import os


def remove_percent_and_save(input_file, output_file):
    with open(input_file, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    removed_count = 0

    processed_lines = []
    for line in lines:
        line = line.strip()
        if not line:
            processed_lines.append('\n')
            continue

        # 分割汉字和拼音部分
        parts = line.split('\t')
        if len(parts) != 2:
            processed_lines.append(line + '\n')
            continue

        character = parts[0].strip()
        pinyin = parts[1].strip()

        # 删除百分数
        if '%' in pinyin:
            pinyin = pinyin.split('%')[0].strip()
            removed_count += 1

        processed_lines.append(f"{character}\t{pinyin}\n")

    with open(output_file, 'w', encoding='utf-8') as f:
        f.writelines(processed_lines)

    print(f"共有{removed_count}行行尾的百分数已删除")


if __name__ == "__main__":
    # 使用绝对路径
    base_dir = os.path.dirname(os.path.abspath(__file__))
    input_file = os.path.join(base_dir, "hanzi_pinyin.yaml")
    output_file = os.path.join(base_dir, "hanzi_to_pinyin.yaml")
    remove_percent_and_save(input_file, output_file)
