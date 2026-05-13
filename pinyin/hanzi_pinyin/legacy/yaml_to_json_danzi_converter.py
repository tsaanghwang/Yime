"""
单字YAML到JSON转换器

功能概述：
------------
将单字汉字与拼音的YAML格式文件转换为结构化的JSON格式文件，专门处理单字拼音对。

主要功能：
1. 转换Tab分隔的单字-拼音对为JSON格式
2. 自动合并多音字的拼音列表
3. 大规模数据处理支持（进度日志）
4. 错误处理机制：
   - 自动跳过空行和格式错误的行
   - 记录详细的警告日志
5. 输出规范化：
   - 确保JSON格式规范
   - 强制UTF-8编码
6. 执行模式：
   - 支持绝对路径一键执行
   - 保留命令行参数接口

输入规范：
---------
格式要求：
- 每行一个单字-拼音对
- 汉字与拼音间用Tab键(\t)分隔
- 拼音内部各音节间用空格分隔

示例输入：
----------
字\tzi4
字\tzi5
中\tzhong1
中\tzhong4

输出规范：
---------
格式说明：
- 单音字直接输出拼音字符串
- 多音字用数组表示所有拼音

示例输出：
---------
{
  "字": ["zi4", "zi5"],
  "中": ["zhong1", "zhong4"]
}

使用方式：
---------
1. 直接执行（使用默认路径）：
   python yaml_to_json_danzi_converter.py

2. 命令行参数模式：
   python yaml_to_json_danzi_converter.py input.yaml output.json
"""

import json
from collections import defaultdict
import sys
import logging
from pathlib import Path

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
    逐行处理输入文件并构建拼音字典

    Args:
        input_path: 输入文件路径，需为Path对象

    Returns:
        构建完成的拼音字典，格式为{单字: [拼音1, 拼音2, ...]}

    Raises:
        UnicodeDecodeError: 当文件编码非UTF-8时抛出
        Exception: 其他文件读取错误
    """
    hanzi_pinyin_map = defaultdict(list)
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
                    # 分割单字和拼音
                    parts = line.split('\t')
                    if len(parts) != 2:
                        logging.warning(
                            f"行 {line_number}: 忽略格式错误的行 (缺少Tab分隔): {line}")
                        skipped_lines += 1
                        continue

                    hanzi, pinyin = parts
                    if len(hanzi) != 1:
                        logging.warning(
                            f"行 {line_number}: 忽略非单字行: {line}")
                        skipped_lines += 1
                        continue

                    if not hanzi or not pinyin:
                        logging.warning(
                            f"行 {line_number}: 忽略空汉字或空拼音的行: {line}")
                        skipped_lines += 1
                        continue

                    if pinyin not in hanzi_pinyin_map[hanzi]:
                        hanzi_pinyin_map[hanzi].append(pinyin)

                    processed_lines += 1
                    if processed_lines % 10000 == 0:
                        logging.info(f"已处理 {processed_lines} 行单字")

                except Exception as e:
                    logging.error(f"行 {line_number}: 处理行时出错 - {str(e)}")
                    skipped_lines += 1

        logging.info(f"单字处理完成 - 共处理 {processed_lines} 行, 跳过 {skipped_lines} 行")
        return dict(hanzi_pinyin_map)

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
        logging.info(f"成功保存单字JSON文件: {output_path}")
    except PermissionError:
        logging.error("权限错误: 无法写入输出文件")
        raise
    except Exception as e:
        logging.error(f"保存JSON文件失败: {str(e)}")
        raise

def main():
    """主执行函数"""
    # 定义默认输入输出文件路径（单字版本）
    default_input = get_absolute_path("hanzi_pinyin_danzi.yaml")
    default_output = get_absolute_path("danzi_pinyin.json")

    try:
        # 验证输入文件
        validate_file_path(default_input)

        # 处理并保存
        merged_data = process_line_by_line(default_input)
        save_as_json(merged_data, default_output)

        logging.info("单字转换成功完成")
        return True
    except Exception as e:
        logging.error(f"单字转换失败: {str(e)}")
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
            logging.info("单字转换成功完成")
            sys.exit(0)
        except Exception as e:
            logging.error(f"单字转换失败: {str(e)}")
            sys.exit(1)
    else:
        print("Usage: python yaml_to_json_danzi_converter.py [<input.yaml> <output.json>]")
        print("无参数时使用默认路径一键执行")
        sys.exit(1)