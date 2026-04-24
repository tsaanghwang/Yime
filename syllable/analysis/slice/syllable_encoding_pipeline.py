"""供音节编码使用的纯规范化与切分流水线。"""

from typing import Tuple

try:
    from .syllable_splitter import SyllableSplitter
except ImportError:
    from syllable_splitter import SyllableSplitter


class SyllableEncodingPipeline:
    """为编码流程提供无副作用的音节规范化与切分逻辑。"""

    TONE_MAPPING = {
        'ā': 'a1', 'á': 'a2', 'ǎ': 'a3', 'à': 'a4',
        'ē': 'e1', 'é': 'e2', 'ě': 'e3', 'è': 'e4',
        'ī': 'i1', 'í': 'i2', 'ǐ': 'i3', 'ì': 'i4',
        'ō': 'o1', 'ó': 'o2', 'ǒ': 'o3', 'ò': 'o4',
        'ū': 'u1', 'ú': 'u2', 'ǔ': 'u3', 'ù': 'u4',
        'ǖ': 'ü1', 'ǘ': 'ü2', 'ǚ': 'ü3', 'ǜ': 'ü4',
        'm̄': 'm1', 'ḿ': 'm2', 'm̌': 'm3', 'm̀': 'm4',
        'n̄': 'n1', 'ń': 'n2', 'ň': 'n3', 'ǹ': 'n4',
        'ê̄': 'ê1', 'ế': 'ê2', 'ê̌': 'ê3', 'ề': 'ê4',
        'n̄g': 'ng1', 'ńg': 'ng2', 'ňg': 'ng3', 'ǹg': 'ng4',
    }

    @classmethod
    def normalize_syllable(cls, syllable: str) -> str:
        """将调号标调统一转换为数字标调。"""
        if not syllable:
            return syllable

        if syllable in SyllableSplitter.REVERSE_SPECIAL_SYLLABLES:
            return SyllableSplitter.REVERSE_SPECIAL_SYLLABLES[syllable]

        has_tone_mark = any(char in cls.TONE_MAPPING for char in syllable)
        if not has_tone_mark:
            return syllable

        converted: list[str] = []
        tone_number = None
        for char in syllable:
            if char in cls.TONE_MAPPING:
                tone_number = cls.TONE_MAPPING[char][-1]
                converted.append(cls.TONE_MAPPING[char][0])
            else:
                converted.append(char)

        normalized = ''.join(converted)
        return normalized + tone_number if tone_number else normalized

    @staticmethod
    def split_normalized_syllable(normalized_syllable: str) -> Tuple[str, str]:
        """对已归一化为数字标调的音节执行编码切分。"""
        if not normalized_syllable:
            return "", ""

        if (
            len(normalized_syllable) >= 2
            and normalized_syllable[:-1].lower() in {'ê', 'm', 'n'}
            and normalized_syllable[-1].isdigit()
        ):
            return "'", normalized_syllable

        if (
            len(normalized_syllable) >= 3
            and normalized_syllable[:-1].lower() == 'ng'
            and normalized_syllable[-1].isdigit()
        ):
            return "'", normalized_syllable

        if len(normalized_syllable) >= 2 and normalized_syllable[0] == 'h':
            if normalized_syllable[1] == 'm' and (
                len(normalized_syllable) == 2 or normalized_syllable[2:].isdigit()
            ):
                return 'h', normalized_syllable[1:]

            if normalized_syllable[1] == 'n' and (
                len(normalized_syllable) == 2
                or (
                    len(normalized_syllable) == 3
                    and normalized_syllable[2] in {'g', 'G'}
                )
                or (
                    len(normalized_syllable) > 3
                    and normalized_syllable[2] in {'g', 'G'}
                    and normalized_syllable[3:].isdigit()
                )
            ):
                return 'h', normalized_syllable[1:]

        return SyllableSplitter.split_syllable(normalized_syllable)

    @classmethod
    def analyze_syllable(cls, syllable: str) -> Tuple[str, str]:
        """执行编码专用的完整音节处理流水线。"""
        normalized_syllable = cls.normalize_syllable(syllable)
        return cls.split_normalized_syllable(normalized_syllable)
