# syllable/analysis/onset_rhyme/helper_copy.py

# 声韵分析
# 功能：分别把两种形式的拼音把音节切分成"声母"+"带调韵母（'韵母'+'声调'）"两个部分
#
# 处理流程：
# 1. 读取JSON文件，分别把两种形式的拼音切分成"声母"+"带调韵母（'韵母'+'声调'）"两个部分
# 2. a/o/e开头的音节（零声母音节）用隔音符号"'"作为键，用除声母外的部分（'韵母'+'声调'）作为值
# 3. 非零声母音节用声母作为键，用除声母外的部分（'韵母'+'声调'）作为值
# 4. 零声母按韵母首字母排序，非零声母按拼音首字母排序，带调韵母按韵母首字母排序，然后按调类排序
# 5. 将最终字典以JSON格式保存到指定文件中
#
# 输入文件格式：
# - JSON字典，结构为{"数字标调拼音": "调号标调拼音"}
# - 路径：syllable\analysis\onset_rhyme\actual_pinyin.json
#
# 输出格式：
# - JSON字典，结构示例：
"""
{
    "b": {
        "a1": "ā",
        "a2": "á", 
        ...
    },
    "c": {
        ...
    },
    "ch": {
        ...
    }
"""
# - 路径：syllable\analysis\onset_rhyme\onset_rhyme.json

# syllable/analysis/onset_rhyme/helper.py
import json
import os
from collections import defaultdict


class OnsetRhymeAnalysisHelper:
    """声韵母分析辅助类，封装复杂分析逻辑"""

    def __init__(self):
        self.input_path = os.path.join(
            os.path.dirname(__file__),
            'pinyin_to_single_hanzi.json'
        )
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

    def perform_analysis(self, syllable):
        """
        执行实际的声韵母分析
        :param syllable: 待分析的音节对象
        :return: 分析结果字典 {'onset': str, 'rhyme': list}
        """
        onset, rhyme = self._split_syllable(syllable)
        return {
            'onset': onset,
            'rhyme': list(rhyme) if rhyme else []
        }

    def analyze_pinyin_file(self):
        """
        从JSON文件读取带调拼音，切分成"声母"+"带调韵母"两部分并保存结果
        """
        try:
            with open(self.input_path, 'r', encoding='utf-8') as f:
                pinyin_data = json.load(f)

            onset_rhyme_map = defaultdict(list)

            for pinyin in pinyin_data.keys():
                onset, rhyme = self._split_syllable(pinyin)
                onset_rhyme_map[onset].append(rhyme)

            # 排序规则:
            # 1. 零声母按韵母首字母排序
            # 2. 非零声母按拼音首字母排序
            # 3. 带调韵母按韵母首字母排序，然后按调类排序
            sorted_result = {}
            for onset in sorted(onset_rhyme_map.keys(),
                                key=lambda x: (x == "'", x)):
                rhymes = onset_rhyme_map[onset]
                sorted_rhymes = sorted(rhymes,
                                       key=lambda r: (r[0] if r else '', int(r[-1]) if r and r[-1].isdigit() else 0))
                sorted_result[onset] = sorted_rhymes

            with open(self.output_path, 'w', encoding='utf-8') as f:
                json.dump(sorted_result, f, ensure_ascii=False, indent=2)

            return True

        except Exception as e:
            print(f"Error analyzing pinyin file: {e}")
            return False
