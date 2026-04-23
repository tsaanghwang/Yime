"""
音节分类工具类
功能：负责音节切分，并复用干音分类器的分类能力。
"""
from typing import Dict, Tuple

try:
    from .ganyin_categorizer import GanyinCategorizer
    from .syllable_splitter import SyllableSplitter
except ImportError:
    from ganyin_categorizer import GanyinCategorizer
    from syllable_splitter import SyllableSplitter


class SyllableCategorizer(GanyinCategorizer):
    """音节切分器，继承干音分类能力并补充音节级规则。"""

    @staticmethod
    def split_syllable(syllable: str) -> Tuple[str, str]:
        """切分音节为首音和干音部分

        参数:
            syllable: 拼音字符串
        返回:
            元组 (首音部分, 干音部分)
        """
        if not syllable:
            return "", ""

        # 处理特殊音节（数字标调形式）
        if syllable in SyllableCategorizer.SPECIAL_SYLLABLES:
            return "'", SyllableCategorizer.SPECIAL_SYLLABLES[syllable]

        # 处理特殊音节（调号标调形式）
        if syllable in SyllableCategorizer.REVERSE_SPECIAL_SYLLABLES:
            return "'", syllable

        # 处理 hm/hn/hng 系列音节（数字标调）
        if len(syllable) >= 2 and syllable[0] == 'h':
            if syllable[1] == 'm' and (len(syllable) == 2 or syllable[2:].isdigit()):
                return "h", syllable[1:]  # 首音"h"，干音"m"或"m1"等
            if syllable[1] == 'n' and (len(syllable) == 2 or
                                    (len(syllable) == 3 and syllable[2] in ('g', 'G') or
                                    len(syllable) > 3 and syllable[2] in ('g', 'G') and syllable[3:].isdigit())):
                return "h", syllable[1:]  # 首音"h"，干音"n"、"ng"或带数字调号

        # 零声母处理 (适用于数字标调和调号标调)
        if syllable[0] in {'a', 'o', 'e', 'ê', 'ā', 'ō', 'ē', 'ế', 'à', 'ò', 'è', 'ǎ', 'ǒ', 'ě', 'á', 'ó', 'é'}:
            return "'", syllable

        if len(syllable) >= 2:
            initial_candidate = syllable[:2].lower()
            if initial_candidate in {'zh', 'ch', 'sh'}:
                # 处理舌尖音后接 "i" 的情况
                if len(syllable) > 2 and syllable[2] == 'i':
                    return initial_candidate, '_' + syllable[2:]
                return initial_candidate, syllable[2:]

        # 单字母声母 (z, c, s, r) - 检查后接 "i" 的情况
        if syllable[0] in {'z', 'c', 's', 'r'} and len(syllable) > 1 and syllable[1] == 'i':
            return syllable[0], '_' + syllable[1:]

        # 处理 ju, qu, xu, yu 的情况
        if len(syllable) >= 2 and syllable[0].lower() in {'j', 'q', 'x', 'y'} and syllable[1].lower() == 'u':
            initial = syllable[0]
            # 将干音中的 u 改为 ü
            final = 'ü' + syllable[2:] if len(syllable) > 2 else 'ü'
            return initial, final

        # 默认处理：第一个字母作为声母
        return syllable[0], syllable[1:] if len(syllable) > 1 else ""

    generate_shouyin_data = SyllableSplitter.generate_shouyin_data

    @staticmethod
    def analyze_syllable(syllable: str) -> Tuple[str, str]:
        """
        修复版音节切分方法，确保特殊音节保留声调数字
        参数:
            syllable: 要分析的音节字符串
        返回:
            元组 (首音部分, 干音部分)
        """
        # 统一转换为数字标调格式
        normalized_syllable = SyllableCategorizer.convert_tone_mark_to_number(syllable)
        # 处理带数字声调的特殊音节（ê/ng/m/n + 数字）
        if (len(normalized_syllable) >= 2 and
            normalized_syllable[:-1].lower() in ['ê', 'm', 'n'] and
            normalized_syllable[-1].isdigit()):
            return "'", normalized_syllable  # 零声母 + 完整带调音节

        # 处理 ng + 数字的情况（如 ng5）
        if (len(normalized_syllable) >= 3 and
            normalized_syllable[:-1].lower() == 'ng' and
            normalized_syllable[-1].isdigit()):
            return "'", normalized_syllable

        # 原有处理逻辑
        shouyin, ganyin = SyllableCategorizer.split_syllable(normalized_syllable)

        # 处理特殊音节情况
        if ganyin.startswith('_'):
            return shouyin, ganyin
        # elif ganyin in SyllableCategorizer.SPECIAL_SYLLABLES:
            # return shouyin, SyllableCategorizer.SPECIAL_SYLLABLES[ganyin]

        return shouyin, ganyin

    @staticmethod
    def convert_tone_mark_to_number(syllable: str) -> str:
        """将调号标调转换为数字标调格式

        参数:
            syllable: 可能包含调号标调的音节字符串

        返回:
            转换为数字标调格式的音节
        """
        if not syllable:
            return syllable

        # 特殊音节处理
        if syllable in SyllableCategorizer.REVERSE_SPECIAL_SYLLABLES:
            return SyllableCategorizer.REVERSE_SPECIAL_SYLLABLES[syllable]

        # 调号到数字的映射
        tone_mapping = {
            'ā': 'a1', 'á': 'a2', 'ǎ': 'a3', 'à': 'a4',
            'ē': 'e1', 'é': 'e2', 'ě': 'e3', 'è': 'e4',
            'ī': 'i1', 'í': 'i2', 'ǐ': 'i3', 'ì': 'i4',
            'ō': 'o1', 'ó': 'o2', 'ǒ': 'o3', 'ò': 'o4',
            'ū': 'u1', 'ú': 'u2', 'ǔ': 'u3', 'ù': 'u4',
            'ǖ': 'ü1', 'ǘ': 'ü2', 'ǚ': 'ü3', 'ǜ': 'ü4',
            'm̄': 'm1', 'ḿ': 'm2', 'm̌': 'm3', 'm̀': 'm4',
            'n̄': 'n1', 'ń': 'n2', 'ň': 'n3', 'ǹ': 'n4',
            'ê̄': 'ê1', 'ế': 'ê2', 'ê̌': 'ê3', 'ề': 'ê4',
            'n̄g': 'ng1', 'ńg': 'ng2', 'ňg': 'ng3', 'ǹg': 'ng4'
        }

        # 检查是否包含调号
        has_tone_mark = any(char in tone_mapping for char in syllable)
        if not has_tone_mark:
            # 已经是数字标调或无声调
            return syllable

        # 转换调号
        converted: list[str] = []
        tone_number = None
        for char in syllable:
            if char in tone_mapping:
                # 找到调号对应的数字
                tone_number = tone_mapping[char][-1]
                converted.append(tone_mapping[char][0])
            else:
                converted.append(char)

        # 添加数字调号
        if tone_number:
            return ''.join(converted) + tone_number
        return ''.join(converted)
