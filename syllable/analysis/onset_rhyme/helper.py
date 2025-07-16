# syllable/analysis/onset_rhyme/helper.py

import json
import os
from collections import defaultdict


class OnsetRhymeAnalysisHelper:
    """声韵母分析辅助类，封装复杂分析逻辑"""

    def __init__(self):
        self.input_path = os.path.normpath(os.path.join(
            os.path.dirname(__file__),
            '..', '..', '..', 'pinyin', 'hanzi_pinyin', 'pinyin_normalized.json'
        ))
        self.output_path = os.path.join(
            os.path.dirname(__file__),
            'onset_rhyme.json'
        )

    def _is_zero_onset(self, syllable):
        """判断是否为零声母音节"""
        return syllable[0] in {'a', 'o', 'e'}

    def _split_syllable(self, syllable):
        """切分音节为声母和带调韵母"""
        if len(syllable) == 0:
            return '', ''

        # 处理带数字声调的情况 (如 'a1', 'ban3')
        tone = syllable[-1] if syllable[-1].isdigit() else ''
        base = syllable[:-1] if tone else syllable

        if self._is_zero_onset(base):
            return "'", base + tone

        # 检查双字母声母 (zh/ch/sh)
        if len(base) >= 2 and base[:2] in {'zh', 'ch', 'sh'}:
            return base[:2], base[2:] + tone if len(base) > 2 else tone
        elif len(base) > 0:
            return base[0], base[1:] + tone if len(base) > 1 else tone

        return '', tone

    def analyze_pinyin_file(self):
        """
        从JSON文件读取数字标调拼音和调号标调拼音的映射，
        切分成"声母"+"带调韵母"两部分并保存结果
        """
        try:
            with open(self.input_path, 'r', encoding='utf-8') as f:
                pinyin_data = json.load(f)

            onset_rhyme_map = defaultdict(dict)

            for num_pinyin, tone_pinyin in pinyin_data.items():
                # 处理数字标调拼音
                onset, rhyme = self._split_syllable(num_pinyin)
                # 处理调号标调拼音，只取韵母部分
                _, tone_rhyme = self._split_syllable(tone_pinyin)
                onset_rhyme_map[onset][rhyme] = tone_rhyme

            # 排序规则:
            # 1. 零声母按韵母首字母排序
            # 2. 非零声母按拼音首字母排序
            # 3. 带调韵母按韵母首字母排序，然后按调类排序
            sorted_result = {}
            for onset in sorted(onset_rhyme_map.keys(),
                                key=lambda x: (x == "'", x)):
                rhymes = onset_rhyme_map[onset]
                sorted_rhymes = dict(sorted(rhymes.items(),
                                            key=lambda item: (item[0][0] if item[0] else '',
                                                              int(item[0][-1]) if item[0] and item[0][-1].isdigit() else 0)))
                sorted_result[onset] = sorted_rhymes

            with open(self.output_path, 'w', encoding='utf-8') as f:
                json.dump(sorted_result, f, ensure_ascii=False, indent=2)

            return True

        except Exception as e:
            print(f"Error analyzing pinyin file: {e}")
            return False


if __name__ == "__main__":
    helper = OnsetRhymeAnalysisHelper()
    if helper.analyze_pinyin_file():
        print("声韵分析完成，结果已保存到:", helper.output_path)
    else:
        print("声韵分析失败，请检查输入文件")
