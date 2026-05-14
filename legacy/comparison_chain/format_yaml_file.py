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


def get_input_file():
    """获取用户输入的文件路径并进行验证"""
    while True:
        input_file = input("请输入要格式化的YAML文件路径: ").strip()
        if not input_file:
            print("错误: 文件路径不能为空")
            continue

        if not os.path.exists(input_file):
            print(f"错误: 文件不存在 - {input_file}")
            continue

        return input_file


def get_output_file(input_file):
    """获取用户输出的文件路径"""
    while True:
        output_option = input(f"是否覆盖原文件 {input_file}? (y/n): ").strip().lower()
        if output_option == 'y':
            return None
        elif output_option == 'n':
            output_file = input("请输入输出文件路径: ").strip()
            if not output_file:
                print("错误: 输出文件路径不能为空")
                continue
            return output_file
        else:
            print("错误: 请输入 y 或 n")


def main():
    print("YAML文件格式化工具")
    print("=" * 30)

    try:
        # 获取输入文件
        input_file = get_input_file()

        # 获取输出选项
        output_file = get_output_file(input_file)

        # 执行格式化
        success = format_yaml_file(input_file, output_file)
        if success:
            output_path = output_file if output_file else input_file
            print(f"文件格式化成功: {output_path}")
        else:
            print("文件格式化失败")
            sys.exit(1)

    except KeyboardInterrupt:
        print("\n操作已取消")
        sys.exit(0)
    except Exception as e:
        print(f"发生错误: {str(e)}")
        sys.exit(1)


if __name__ == "__main__":
    main()