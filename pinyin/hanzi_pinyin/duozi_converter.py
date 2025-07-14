"""
多字YAML到JSON转换器

功能：
1. 将Tab分隔的多字-拼音对转换为JSON格式
2. 处理重复多字的情况，合并拼音列表
3. 支持大规模数据处理，每处理10000行输出进度日志
4. 自动跳过空行和格式错误的行，并记录警告日志
5. 确保输出JSON文件格式规范，支持UTF-8编码
6. 使用绝对路径一键执行生成目标文件

输入格式规范：
1. 每行一个多字-拼音对，汉字与拼音间用Tab键(\t)分隔
2. 拼音内部各音节间用空格分隔，如：li4 xue2 du3 xing2
3. 示例格式：
力學篤行\tli4 xue2 du3 xing2
力巴\tli4 ba5
力巴頭\tli4 ba5 tou2
力度\tli4 du4
力度\tli4 du5

输出格式规范：
1. 单音词直接输出拼音字符串
2. 多音词用数组表示所有拼音
3. 示例格式：
{
  "力學篤行": "li4 xue2 du3 xing2",
  "力巴": "li4 ba5",
  "力巴頭": "li4 ba5 tou2",
  "力度": ["li4 du4", "li4 du5"],
  "力微任重": ["li4 wei1 ren4 zhong4", "li4 wei2 ren4 zhong4"]
}
"""

import json
from collections import defaultdict
import sys
import logging
from pathlib import Path
import os

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)


def get_absolute_path(relative_path: str) -> Path:
    """获取绝对路径"""
    script_dir = Path(__file__).parent.absolute()
    return script_dir / relative_path


def validate_file_path(file_path: Path) -> None:
    """验证文件路径是否存在且可读"""
    if not file_path.exists():
        raise FileNotFoundError(f"输入文件不存在: {file_path}")
    if not file_path.is_file():
        raise ValueError(f"路径不是文件: {file_path}")


def process_line_by_line(input_path: Path) -> dict:
    """
    逐行处理输入文件

    Args:
        input_path: 输入文件路径

    Returns:
        合并后的字典数据 {多字: [拼音1, 拼音2, ...]}
    """
    phrase_pinyin_map = defaultdict(list)
    processed_lines = 0
    skipped_lines = 0

    try:
        with open(input_path, 'r', encoding='utf-8') as file:
            for line_number, line in enumerate(file, 1):
                line = line.strip()
                if not line:
                    skipped_lines += 1
                    continue

                try:
                    # 分割汉字和拼音
                    parts = line.split('\t')
                    if len(parts) != 2:
                        logging.warning(
                            f"行 {line_number}: 忽略格式错误的行 (缺少Tab分隔): {line}")
                        skipped_lines += 1
                        continue

                    phrase, pinyin = parts
                    if not phrase or not pinyin:
                        logging.warning(
                            f"行 {line_number}: 忽略空汉字或空拼音的行: {line}")
                        skipped_lines += 1
                        continue

                    if pinyin not in phrase_pinyin_map[phrase]:
                        phrase_pinyin_map[phrase].append(pinyin)

                    processed_lines += 1
                    if processed_lines % 10000 == 0:
                        logging.info(f"已处理 {processed_lines} 行")

                except Exception as e:
                    logging.error(f"行 {line_number}: 处理行时出错 - {str(e)}")
                    skipped_lines += 1

        logging.info(f"处理完成 - 共处理 {processed_lines} 行, 跳过 {skipped_lines} 行")
        return dict(phrase_pinyin_map)

    except UnicodeDecodeError:
        logging.error("文件编码错误: 必须使用UTF-8编码")
        raise
    except Exception as e:
        logging.error(f"文件处理失败: {str(e)}")
        raise


def save_as_json(data: dict, output_path: Path) -> None:
    """
    保存为JSON文件

    Args:
        data: 要保存的数据
        output_path: 输出文件路径
    """
    try:
        with open(output_path, 'w', encoding='utf-8') as file:
            json.dump(data, file, ensure_ascii=False, indent=2)
        logging.info(f"成功保存JSON文件: {output_path}")
    except PermissionError:
        logging.error("权限错误: 无法写入输出文件")
        raise
    except Exception as e:
        logging.error(f"保存JSON文件失败: {str(e)}")
        raise


def main():
    """主执行函数"""
    # 定义默认输入输出文件路径
    default_input = get_absolute_path("duozi_pinyin.yaml")
    default_output = get_absolute_path("duozi_pinyin.json")

    try:
        # 验证输入文件
        validate_file_path(default_input)

        # 处理并保存
        merged_data = process_line_by_line(default_input)
        save_as_json(merged_data, default_output)

        logging.info("转换成功完成")
        return True
    except Exception as e:
        logging.error(f"转换失败: {str(e)}")
        return False


if __name__ == "__main__":
    if len(sys.argv) == 1:
        # 无参数时使用默认路径一键执行
        success = main()
        sys.exit(0 if success else 1)
    elif len(sys.argv) == 3:
        # 保留命令行参数支持
        input_file, output_file = sys.argv[1], sys.argv[2]
        try:
            validate_file_path(Path(input_file))
            merged_data = process_line_by_line(Path(input_file))
            save_as_json(merged_data, Path(output_file))
            logging.info("转换成功完成")
            sys.exit(0)
        except Exception as e:
            logging.error(f"转换失败: {str(e)}")
            sys.exit(1)
    else:
        print("Usage: python duozi_converter.py [<input.yaml> <output.json>]")
        print("无参数时使用默认路径一键执行")
        sys.exit(1)
