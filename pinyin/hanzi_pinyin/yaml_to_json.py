#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import json
import os
import argparse
from typing import Dict, List, Tuple, Any
from collections import defaultdict
import logging

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('yaml_to_json.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)


class YAMLToJSONConverter:
    """将YAML格式的拼音数据转换为JSON格式的转换器"""

    def __init__(self):
        self.mappings: Dict[str, List[str]] = defaultdict(list)
        self.unconverted_lines: List[Dict[str, Any]] = []
        self.detailed_stats = {
            'total_lines': 0,
            'discarded_by_separator': 0,
            'empty_lines': 0,
            'comment_lines': 0,
            'invalid_format_lines': 0,
            'converted_lines': 0,
            'polyphonic_chars': 0,
            'monophonic_chars': 0
        }

    def _process_line(self, line: str, line_num: int) -> bool:
        """处理单行数据"""
        line = line.strip()
        if not line:
            self._record_unconverted(line_num, line, '空行')
            self.detailed_stats['empty_lines'] += 1
            return False

        if line.startswith('#'):
            self._record_unconverted(line_num, line, '注释行')
            self.detailed_stats['comment_lines'] += 1
            return False

        parts = line.split('\t')
        if len(parts) < 2:
            self._record_unconverted(line_num, line, '格式不正确，缺少制表符分隔')
            self.detailed_stats['invalid_format_lines'] += 1
            return False

        character = parts[0].strip()
        pinyin = parts[1].strip().split('%')[0].strip()  # 删除行尾百分数

        # 处理多字词拼音（可能包含空格分隔的多个拼音）
        if len(character) > 1:
            pinyin_list = pinyin.split()
            for p in pinyin_list:
                if p not in self.mappings[character]:
                    self.mappings[character].append(p)
        else:
            if pinyin not in self.mappings[character]:
                self.mappings[character].append(pinyin)
        self.detailed_stats['converted_lines'] += 1

        return True

    def _record_unconverted(self, line_num: int, content: str, reason: str) -> None:
        """记录未转换的行"""
        self.unconverted_lines.append({
            'line_number': line_num,
            'content': content,
            'reason': reason
        })

    def _analyze_polyphonic_stats(self) -> None:
        """分析多音字统计"""
        self.detailed_stats['polyphonic_chars'] = 0
        self.detailed_stats['monophonic_chars'] = 0

        # 只统计单字符的情况，忽略多字词
        for char, pinyin_list in self.mappings.items():
            if len(char) == 1:  # 只处理单字符
                if len(pinyin_list) > 1:
                    self.detailed_stats['polyphonic_chars'] += 1
                else:
                    self.detailed_stats['monophonic_chars'] += 1

    def _write_output_files(self, json_file: str) -> None:
        """写入输出文件"""
        # 写入主JSON文件
        with open(json_file, 'w', encoding='utf-8') as f:
            json.dump(self.mappings, f, ensure_ascii=False, indent=2)

        # 写入未转换行文件
        unconverted_file = os.path.join(
            os.path.dirname(json_file), 'unconverted_lines.json')
        with open(unconverted_file, 'w', encoding='utf-8') as f:
            json.dump(self.unconverted_lines, f, ensure_ascii=False, indent=2)

    def _print_report(self) -> None:
        """打印转换报告"""
        logger.info("\n详细转换报告:")
        logger.info("="*60)
        logger.info(f"总行数: {self.detailed_stats['total_lines']}")
        logger.info(f"成功转换: {self.detailed_stats['converted_lines']} 行")
        logger.info(
            f"被分割符丢弃的行: {self.detailed_stats['discarded_by_separator']} 行")
        logger.info(f"空行: {self.detailed_stats['empty_lines']} 行")
        logger.info(f"注释行: {self.detailed_stats['comment_lines']} 行")
        logger.info(f"格式错误行: {self.detailed_stats['invalid_format_lines']} 行")

        calculated_total = (
            self.detailed_stats['converted_lines'] +
            self.detailed_stats['discarded_by_separator'] +
            self.detailed_stats['empty_lines'] +
            self.detailed_stats['comment_lines'] +
            self.detailed_stats['invalid_format_lines']
        )

        logger.info(f"\n计算总和: {calculated_total} 行")
        logger.info(
            f"差异: {self.detailed_stats['total_lines'] - calculated_total} 行")
        logger.info(f"\n多音字统计:")
        logger.info(f"多音字数量: {self.detailed_stats['polyphonic_chars']}")
        logger.info(f"单音字数量: {self.detailed_stats['monophonic_chars']}")

    def convert(self, yaml_file: str, json_file: str) -> None:
        """执行转换过程"""
        try:
            # 读取文件内容
            with open(yaml_file, 'r', encoding='utf-8') as f:
                content = f.read()

            self.detailed_stats['total_lines'] = len(content.split('\n'))

            # 分割文件内容，处理各部分
            parts = content.split('...')
            mapping_part = parts[-1].strip() if parts else ""

            # 记录被分割丢弃的部分
            discarded_parts = parts[:-1]
            if discarded_parts:
                discarded_lines = sum(len(part.split('\n'))
                                      for part in discarded_parts)
                self.detailed_stats['discarded_by_separator'] = discarded_lines
                self.unconverted_lines.append({
                    'line_range': f'1-{discarded_lines}',
                    'content': '...'.join(discarded_parts),
                    'reason': '被分割符"..."丢弃的部分'
                })

            # 处理映射部分
            mapping_lines = mapping_part.split('\n')
            start_line = len(discarded_parts) + 1 if discarded_parts else 1
            for line_num, line in enumerate(mapping_lines, start_line):
                self._process_line(line, line_num)

            # 分析多音字统计
            self._analyze_polyphonic_stats()

            # 写入输出文件
            self._write_output_files(json_file)

            # 打印报告
            self._print_report()

        except FileNotFoundError:
            logger.error(f"文件未找到: {yaml_file}")
            raise
        except Exception as e:
            logger.error(f"转换过程中发生错误: {str(e)}")
            raise


def main():
    """主函数，处理命令行参数"""
    parser = argparse.ArgumentParser(description='将YAML格式的拼音数据转换为JSON格式')
    parser.add_argument('yaml_file', nargs='?',
                        default=os.path.join(os.path.dirname(
                            __file__), 'hanzi_pinyin.yaml'),
                        help='输入的YAML文件路径 (默认: 同目录下的hanzi_pinyin.yaml)')
    parser.add_argument('json_file', nargs='?',
                        default=os.path.join(os.path.dirname(
                            __file__), 'hanzi_to_pinyin.json'),
                        help='输出的JSON文件路径 (默认: 同目录下的hanzi_to_pinyin.json)')
    parser.add_argument('--verbose', '-v', action='store_true', help='显示详细输出')

    args = parser.parse_args()

    if args.verbose:
        logger.setLevel(logging.DEBUG)

    converter = YAMLToJSONConverter()
    converter.convert(args.yaml_file, args.json_file)


if __name__ == '__main__':
    main()
