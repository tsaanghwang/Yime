# syllable/analysis/initial_divrhyme/analysis_executor.py

import json
import os
from collections import defaultdict


class InitialDivisionalRhymeAnalysisExecutor:
    """声母等韵分析执行类，封装复杂分析逻辑"""

    # 定义特殊音节映射
    SPECIAL_SYLLABLES = {
        "ê1": "ê̄",
        "ê2": "ế",
        "ê3": "ê̌",
        "ê4": "ề",
        "ê5": "ê",
        "m1": "m̄",
        "m2": "ḿ",
        "m3": "m̌",
        "m4": "m̀",
        "m5": "m",
        "n1": "n̄",
        "n2": "ń",
        "n3": "ň",
        "n4": "ǹ",
        "n5": "n",
        "ng1": "n̄g",
        "ng2": "ńg",
        "ng3": "ňg",
        "ng4": "ǹg",
        "ng5": "ng",
        "hm1": "hm̄",
        "hm2": "hḿ",
        "hm3": "hm̌",
        "hm4": "hm̀",
        "hm5": "hm",
        "hn1": "hn̄",
        "hn2": "hń",
        "hn3": "hň",
        "hn4": "hǹ",
        "hn5": "hn",
        "hng1": "hn̄g",
        "hng2": "hńg",
        "hng3": "hňg",
        "hng4": "hǹg",
        "hng5": "hng"
    }

    def __init__(self):
        self.input_path = os.path.normpath(os.path.join(
            os.path.dirname(__file__),
            '..', '..', '..', 'pinyin', 'hanzi_pinyin', 'pinyin_normalized.json'
        ))
        self.output_path = os.path.join(
            os.path.dirname(__file__),
            'initial_divrhyme.json'
        )

    def _is_zero_onset(self, syllable):
        """判断是否为零声母音节"""
        return syllable[0] in {'a', 'o', 'e', 'ê'}

    def _is_special_syllable(self, syllable):
        """判断是否为特殊音节"""
        return syllable in self.SPECIAL_SYLLABLES

    def _split_syllable(self, syllable):
        """切分音节为声母和带调韵母"""
        if len(syllable) == 0:
            return '', ''

        # 首先检查是否为特殊音节
        if self._is_special_syllable(syllable):
            if syllable.startswith('h'):
                # h开头的特殊音节：h作为声母，剩余部分作为韵母
                return 'h', syllable[1:]
            elif syllable.startswith(('m', 'n', 'ng', 'ê')):
                # m/n/ng/ê开头的特殊音节：零声母，整个音节作为韵母
                return "'", syllable

        # 处理带数字声调的情况
        tone = syllable[-1] if syllable[-1].isdigit() else ''
        base = syllable[:-1] if tone else syllable

        # 检查是否为零声母音节（包括ê）
        if self._is_zero_onset(base):
            return "'", base + tone

        # 检查双字母声母 (zh/ch/sh)
        if len(base) >= 2 and base[:2] in {'zh', 'ch', 'sh'}:
            return base[:2], base[2:] + tone if len(base) > 2 else tone

        # 默认处理：第一个字母作为声母，剩余部分作为韵母
        if len(base) > 0:
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

                # 处理调号标调拼音 - 特殊处理
                if self._is_special_syllable(num_pinyin):
                    # 对于特殊音节，直接使用预定义的调号形式
                    tone_rhyme = self.SPECIAL_SYLLABLES[num_pinyin]
                else:
                    # 普通音节按常规处理
                    _, tone_rhyme = self._split_syllable(tone_pinyin)

                onset_rhyme_map[onset][rhyme] = tone_rhyme

            # 排序规则保持不变...
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
    analysis_executor = InitialDivisionalRhymeAnalysisExecutor()
    if analysis_executor.analyze_pinyin_file():
        print("声韵分析完成，结果已保存到:", analysis_executor.output_path)
    else:
        print("声韵分析失败，请检查输入文件")
