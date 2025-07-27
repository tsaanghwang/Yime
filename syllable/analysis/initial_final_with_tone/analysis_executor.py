# syllable/analysis/initial_final_with_tone/analysis_executor.py

import json
import os
from collections import defaultdict


class InitialFinalWithToneAnalysisExecutor:
    """声母韵母声调分析执行类，封装复杂分析逻辑"""

    # 定义特殊音节映射（已移除所有h开头的特殊音节）
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
        "ng5": "ng"
    }

    def __init__(self):
        self.input_path = os.path.normpath(os.path.join(
            os.path.dirname(__file__),
            '..', '..', '..', 'pinyin', 'hanzi_pinyin', 'pinyin_normalized.json'
        ))
        self.output_path = os.path.join(
            os.path.dirname(__file__),
            'initial_final_with_tone.json'
        )

    def _is_zero_initial(self, syllable):
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
            # 只处理m/n/ng/ê开头的特殊音节：零声母，整个音节作为韵母
            if syllable.startswith(('m', 'n', 'ng', 'ê')):
                return "'", syllable

        # 处理带数字声调的情况, 声调在最后一个字符并且是数字, 定义：quality = 声母 + 韵母
        tone = syllable[-1] if syllable[-1].isdigit() else ''
        quality = syllable[:-1] if tone else syllable

        # 检查是否为零声母音节（包括ê）
        if self._is_zero_initial(quality):
            return "'", quality + tone

        # 检查双字母声母 (zh/ch/sh)
        if len(quality) >= 2 and quality[:2] in {'zh', 'ch', 'sh'}:
            return quality[:2], quality[2:] + tone if len(quality) > 2 else tone

        # 默认处理：第一个字母作为声母，剩余部分作为韵母
        if len(quality) > 0:
            return quality[0], quality[1:] + tone if len(quality) > 1 else tone

        return '', tone

    def analyze_pinyin_file(self):
        try:
            with open(self.input_path, 'r', encoding='utf-8') as f:
                pinyin_data = json.load(f)

            initial_final_with_tone_map = defaultdict(dict)

            for num_pinyin, tone_pinyin in pinyin_data.items():
                initial, final_with_tone = self._split_syllable(num_pinyin)

                # 特殊处理特殊音节
                if self._is_special_syllable(num_pinyin):
                    final_with_tone = self.SPECIAL_SYLLABLES[num_pinyin]
                    if num_pinyin not in initial_final_with_tone_map[initial]:
                        initial_final_with_tone_map[initial][num_pinyin] = final_with_tone
                else:
                    # 普通音节：键只保留韵母部分，值使用带声调形式
                    # 确保只处理真正的韵母部分
                    if initial == "'":  # 零声母音节
                        final_part = num_pinyin  # 整个音节作为韵母
                    else:
                        # 确保去掉的是完整的声母部分
                        final_part = num_pinyin[len(initial):] if len(
                            num_pinyin) > len(initial) else ""

                    # 确保final_part不为空且包含声调数字
                    if final_part and final_part[-1].isdigit():
                        _, final_with_tone = self._split_syllable(tone_pinyin)
                        initial_final_with_tone_map[initial][final_part] = final_with_tone

            # 排序逻辑保持不变...
            sorted_result = {}
            for initial in sorted(initial_final_with_tone_map.keys(),
                                  key=lambda x: (x == "'", x)):
                final_with_tone_items = initial_final_with_tone_map[initial]
                sorted_final_with_tone_items = dict(sorted(final_with_tone_items.items(),
                                                           key=lambda item: (item[0][0] if item[0] else '',
                                                                             int(item[0][-1]) if item[0] and item[0][-1].isdigit() else 0)))
                sorted_result[initial] = sorted_final_with_tone_items

            with open(self.output_path, 'w', encoding='utf-8') as f:
                json.dump(sorted_result, f, ensure_ascii=False, indent=2)

            return True

        except Exception as e:
            print(f"Error analyzing pinyin file: {e}")
            return False


if __name__ == "__main__":
    analysis_executor = InitialFinalWithToneAnalysisExecutor()
    if analysis_executor.analyze_pinyin_file():
        print("声母韵母声调分析完成，结果已保存到:", analysis_executor.output_path)
    else:
        print("声母韵母声调分析失败，请检查输入文件")
