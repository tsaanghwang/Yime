"""音节切分与首音提取工具。"""

from typing import Dict, Tuple


class SyllableSplitter:
    """提供音节切分和首音数据生成能力。"""

    SPECIAL_SYLLABLES = {
        "ê1": "ê̄", "ê2": "ế", "ê3": "ê̌", "ê4": "ề", "ê5": "ê",
        "m1": "m̄", "m2": "ḿ", "m3": "m̌", "m4": "m̀", "m5": "m",
        "n1": "n̄", "n2": "ń", "n3": "ň", "n4": "ǹ", "n5": "n",
        "ng1": "n̄g", "ng2": "ńg", "ng3": "ňg", "ng4": "ǹg", "ng5": "ng",
    }
    REVERSE_SPECIAL_SYLLABLES = {value: key for key, value in SPECIAL_SYLLABLES.items()}

    @classmethod
    def _is_special_syllable(cls, syllable: str) -> bool:
        return syllable in cls.SPECIAL_SYLLABLES or syllable in cls.REVERSE_SPECIAL_SYLLABLES

    @classmethod
    def split_syllable(cls, syllable: str) -> Tuple[str, str]:
        """切分音节为首音和干音部分。"""
        if not syllable:
            return "", ""

        if syllable in cls.SPECIAL_SYLLABLES:
            return "'", cls.SPECIAL_SYLLABLES[syllable]

        if syllable in cls.REVERSE_SPECIAL_SYLLABLES:
            return "'", syllable

        if syllable[0] in {'a', 'o', 'e', 'ê', 'ā', 'ō', 'ē', 'ế', 'à', 'ò', 'è', 'ǎ', 'ǒ', 'ě', 'á', 'ó', 'é'}:
            return "'", syllable

        if len(syllable) >= 2:
            initial_candidate = syllable[:2].lower()
            if initial_candidate in {'zh', 'ch', 'sh'}:
                if len(syllable) > 2 and syllable[2] == 'i':
                    return initial_candidate, '_' + syllable[2:]
                return initial_candidate, syllable[2:]

        if syllable[0] in {'z', 'c', 's', 'r'} and len(syllable) > 1 and syllable[1] == 'i':
            return syllable[0], '_' + syllable[1:]

        if len(syllable) >= 2 and syllable[0].lower() in {'j', 'q', 'x', 'y'} and syllable[1].lower() == 'u':
            initial = syllable[0]
            final = 'ü' + syllable[2:] if len(syllable) > 2 else 'ü'
            return initial, final

        return syllable[0], syllable[1:] if len(syllable) > 1 else ""

    @classmethod
    def generate_shouyin_data(cls, pinyin_data: Dict[str, str]) -> Dict[str, str]:
        """生成首音数据字典。"""
        initial_order = [
            'b', 'p', 'f', 'm',
            'd', 't', 'l', 'n',
            'g', 'k', 'h',
            'z', 'c', 's',
            'zh', 'ch', 'sh', 'r',
            'j', 'q', 'x'
        ]

        shouyin_data: Dict[str, str] = {}
        ordered_shouyin_data: Dict[str, str] = {}

        for _, tone_pinyin in pinyin_data.items():
            initial, _ = cls.split_syllable(tone_pinyin)
            if initial not in shouyin_data:
                shouyin_data[initial] = initial

        for initial in initial_order:
            if initial in shouyin_data:
                ordered_shouyin_data[initial] = shouyin_data[initial]

        for initial in shouyin_data:
            if initial not in ordered_shouyin_data:
                ordered_shouyin_data[initial] = shouyin_data[initial]

        return ordered_shouyin_data
