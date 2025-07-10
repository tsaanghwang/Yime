#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
拼音转汉字增强版工具
支持多音字处理、词频统计和批量转换功能
"""

import os
import json
from collections import defaultdict


class PinyinConverter:
    def __init__(self, dictionary_file=None):
        """
        初始化拼音转换器
        :param dictionary_file: 拼音字典文件路径，如果为None则使用默认路径
        """
        if dictionary_file is None:
            # 获取脚本所在目录
            script_dir = os.path.dirname(os.path.abspath(__file__))
            dictionary_file = os.path.join(script_dir, 'pinyin_to_hanzi.json')

        with open(dictionary_file, 'r', encoding='utf-8') as f:
            self.dictionary = json.load(f)

        # 初始化统计信息
        self.polyphone_stats = defaultdict(int)
        self.unconverted_lines = 0
        self.total_entries = 0
        self.unique_pinyin = 0
        self.unique_hanzi = set()

    def convert_single(self, pinyin):
        """
        转换单个拼音，返回所有可能的汉字选项
        :param pinyin: 要转换的拼音
        :return: 汉字列表，按频率排序
        """
        if pinyin not in self.dictionary:
            return []

        # 获取所有汉字选项
        hanzi_list = self.dictionary[pinyin]

        # 如果是多音字则记录统计
        if len(hanzi_list) > 1:
            self.polyphone_stats[pinyin] += 1

        return hanzi_list

    def convert_phrase(self, pinyin_phrase):
        """
        转换多字词拼音
        :param pinyin_phrase: 拼音词组，空格分隔
        :return: 可能的汉字组合列表
        """
        pinyin_list = pinyin_phrase.split()
        results = ['']

        for pinyin in pinyin_list:
            options = self.convert_single(pinyin)
            if not options:
                self.unconverted_lines += 1
                return []

            # 生成所有可能的组合
            new_results = []
            for res in results:
                for opt in options:
                    new_results.append(res + opt)
            results = new_results

        return results

    def get_stats(self):
        """
        获取转换统计信息
        :return: 包含详细统计信息的字典
        """
        # 计算唯一拼音和汉字数量
        self.unique_pinyin = len(self.dictionary)
        for pinyin, hanzi_list in self.dictionary.items():
            self.unique_hanzi.update(hanzi_list)
            self.total_entries += len(hanzi_list)

        # 计算多音字数量(一个汉字对应多个拼音)
        hanzi_to_pinyin = defaultdict(set)
        for pinyin, hanzi_list in self.dictionary.items():
            for hanzi in hanzi_list:
                hanzi_to_pinyin[hanzi].add(pinyin)

        polyphone_count = sum(1 for pinyin_set in hanzi_to_pinyin.values()
                              if len(pinyin_set) > 1)

        return {
            'total_pinyin': self.unique_pinyin,
            'total_hanzi': len(self.unique_hanzi),
            'total_entries': self.total_entries,
            'polyphone_count': polyphone_count,
            'polyphone_stats': dict(self.polyphone_stats),
            'unconverted_lines': self.unconverted_lines
        }


def main():
    # 示例用法
    converter = PinyinConverter()

    # 单字转换
    print("单字'zhong'的可能汉字:", converter.convert_single('zhong'))

    # 多字词转换
    print("词组'zhong guo'的可能组合:", converter.convert_phrase('zhong guo'))

    # 输出统计信息
    print("转换统计:", converter.get_stats())


if __name__ == '__main__':
    main()
