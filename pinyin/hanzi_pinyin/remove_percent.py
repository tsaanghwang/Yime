import re
import os


def remove_percent_and_save(input_file, output_file):
    with open(input_file, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    original_count = len(lines)
    processed_lines = []
    removed_count = 0
    no_tone_count = 0

    # 优化后的百分号匹配模式，精确匹配行尾
    percent_pattern = re.compile(r'\s*\d+\.?\d*%$')

    for line in lines:
        original_line = line
        line = line.strip()  # 去除首尾空白
        new_line = percent_pattern.sub('', line)

        if new_line != line:  # 只有当行被修改时才处理
            removed_count += 1
            processed_lines.append(new_line + '\n')
        else:
            processed_lines.append(original_line)  # 保留原行

    with open(output_file, 'w', encoding='utf-8') as f:
        f.writelines(processed_lines)

    print(f"共有{removed_count}行行尾的百分数已删除")
    if no_tone_count > 0:
        print(f"发现{no_tone_count}行不用数字标调的拼音")
    else:
        print("未发现不用数字标调的拼音")


if __name__ == "__main__":
    # 使用绝对路径
    base_dir = os.path.dirname(os.path.abspath(__file__))
    input_file = os.path.join(base_dir, "hanzi_pinyin_raw.yaml")
    output_file = os.path.join(base_dir, "hanzi_pinyin.yaml")
    remove_percent_and_save(input_file, output_file)
