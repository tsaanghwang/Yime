"""
YAML文件格式统一工具
功能：
1. 统一文件中汉字和拼音之间的分隔符为Tab
2. 统一拼音之间的分隔符为空格
3. 保存格式化后的文件
"""

import sys
import logging
import os

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)


def format_yaml_file(input_file, output_file=None):
    """
    格式化YAML文件，统一分隔符

    Args:
        input_file: 输入文件路径
        output_file: 输出文件路径(可选，默认为覆盖原文件)
    """
    if output_file is None:
        output_file = input_file

    formatted_lines = []
    changed_lines = 0

    try:
        with open(input_file, 'r', encoding='utf-8') as f:
            for line_num, line in enumerate(f, 1):
                original_line = line.strip()
                if not original_line:
                    formatted_lines.append('')
                    continue

                # 分割汉字和拼音部分
                if '\t' in original_line:
                    parts = original_line.split('\t', 1)
                else:
                    parts = original_line.split(' ', 1)

                if len(parts) != 2:
                    logging.warning(
                        f"行 {line_num}: 无法分割汉字和拼音 - {original_line}")
                    formatted_lines.append(original_line)
                    continue

                hanzi, pinyin = parts

                # 统一拼音部分的分隔符为空格
                pinyin = ' '.join(pinyin.split())

                # 构建新行：汉字 + Tab + 拼音(空格分隔)
                new_line = f"{hanzi}\t{pinyin}"

                if new_line != original_line:
                    changed_lines += 1
                    logging.debug(
                        f"行 {line_num} 修改: {original_line} → {new_line}")

                formatted_lines.append(new_line)

        # 写入输出文件
        with open(output_file, 'w', encoding='utf-8') as f:
            f.write('\n'.join(formatted_lines))

        logging.info(f"格式化完成: 共修改 {changed_lines} 行")
        return True

    except Exception as e:
        logging.error(f"文件处理失败: {str(e)}")
        return False


def main():
    if len(sys.argv) < 2:
        print("Usage: python check_yaml_format.py <input.yaml> [output.yaml]")
        print("如果未指定输出文件，将直接修改输入文件")
        sys.exit(1)

    input_file = sys.argv[1]
    output_file = sys.argv[2] if len(sys.argv) > 2 else None

    if not os.path.exists(input_file):
        logging.error(f"输入文件不存在: {input_file}")
        sys.exit(1)

    try:
        success = format_yaml_file(input_file, output_file)
        if success:
            logging.info(
                f"文件格式化成功: {input_file} → {output_file or input_file}")
        else:
            logging.error("文件格式化失败")
            sys.exit(1)

    except Exception as e:
        logging.error(f"格式化失败: {str(e)}")
        sys.exit(1)


if __name__ == "__main__":
    main()
