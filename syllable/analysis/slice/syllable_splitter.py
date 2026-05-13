"""音节切分与首音提取工具。"""

import json
from pathlib import Path
from typing import Dict, Tuple
import unicodedata


class SyllableSplitter:
    """提供音节切分和首音数据生成能力。"""

    UMLAUT_TONE_VOWELS = {'u', 'ū', 'ú', 'ǔ', 'ù', 'ü', 'ǖ', 'ǘ', 'ǚ', 'ǜ'}
    TONE_MARK_TO_BASE = {
        'ā': ('a', '1'), 'á': ('a', '2'), 'ǎ': ('a', '3'), 'à': ('a', '4'),
        'ē': ('e', '1'), 'é': ('e', '2'), 'ě': ('e', '3'), 'è': ('e', '4'),
        'ī': ('i', '1'), 'í': ('i', '2'), 'ǐ': ('i', '3'), 'ì': ('i', '4'),
        'ō': ('o', '1'), 'ó': ('o', '2'), 'ǒ': ('o', '3'), 'ò': ('o', '4'),
        'ū': ('u', '1'), 'ú': ('u', '2'), 'ǔ': ('u', '3'), 'ù': ('u', '4'),
        'ǖ': ('ü', '1'), 'ǘ': ('ü', '2'), 'ǚ': ('ü', '3'), 'ǜ': ('ü', '4'),
        'ḿ': ('m', '2'), 'ń': ('n', '2'), 'ň': ('n', '3'), 'ǹ': ('n', '4'),
    }

    SPECIAL_SYLLABLES = {
        "ê1": "ê̄", "ê2": "ế", "ê3": "ê̌", "ê4": "ề", "ê5": "ê",
        "m1": "m̄", "m2": "ḿ", "m3": "m̌", "m4": "m̀", "m5": "m",
        "n1": "n̄", "n2": "ń", "n3": "ň", "n4": "ǹ", "n5": "n",
        "ng1": "n̄g", "ng2": "ńg", "ng3": "ňg", "ng4": "ǹg", "ng5": "ng",
    }
    REVERSE_SPECIAL_SYLLABLES = {value: key for key, value in SPECIAL_SYLLABLES.items()}
    _MARKED_GANYIN_CACHE: dict[str, str] | None = None
    _TONE_NUMBER_TO_MARK = {
        '1': '\u0304',
        '2': '\u0301',
        '3': '\u030c',
        '4': '\u0300',
    }

    @classmethod
    def _load_marked_ganyin_map(cls) -> dict[str, str]:
        if cls._MARKED_GANYIN_CACHE is None:
            ganyin_path = Path(__file__).resolve().parent / 'yinyuan' / 'ganyin.json'
            payload = json.loads(ganyin_path.read_text(encoding='utf-8')).get('ganyin', {})
            if payload and all(isinstance(value, dict) for value in payload.values()):
                flattened: dict[str, str] = {}
                for entries in payload.values():
                    flattened.update(entries)
                cls._MARKED_GANYIN_CACHE = flattened
            else:
                cls._MARKED_GANYIN_CACHE = payload
        return cls._MARKED_GANYIN_CACHE

    @classmethod
    def _normalize_for_family_matching(cls, syllable: str) -> str:
        normalized: list[str] = []
        tone_number = ''
        for char in syllable:
            if char in cls.TONE_MARK_TO_BASE:
                base, tone = cls.TONE_MARK_TO_BASE[char]
                normalized.append(base)
                tone_number = tone
            else:
                normalized.append(char)

        normalized_text = ''.join(normalized)
        if tone_number and not normalized_text[-1].isdigit():
            return normalized_text + tone_number
        return normalized_text

    @classmethod
    def _marked_final_from_numeric(cls, numeric_final: str) -> str:
        if numeric_final.endswith('5'):
            return numeric_final[:-1]
        return cls._load_marked_ganyin_map().get(numeric_final, cls._compose_marked_final(numeric_final))

    @classmethod
    def _compose_marked_final(cls, numeric_final: str) -> str:
        if numeric_final in cls.SPECIAL_SYLLABLES:
            return cls.SPECIAL_SYLLABLES[numeric_final]

        if not numeric_final or not numeric_final[-1].isdigit():
            return numeric_final

        tone_number = numeric_final[-1]
        base_final = numeric_final[:-1]
        tone_mark = cls._TONE_NUMBER_TO_MARK.get(tone_number)
        if not tone_mark:
            return base_final

        tone_index = cls._find_tone_mark_position(base_final)
        if tone_index < 0:
            return numeric_final

        marked = base_final[:tone_index + 1] + tone_mark + base_final[tone_index + 1:]
        return unicodedata.normalize('NFC', marked)

    @staticmethod
    def _find_tone_mark_position(base_final: str) -> int:
        for vowel in ('a', 'o', 'e'):
            position = base_final.find(vowel)
            if position >= 0:
                return position

        for index in range(len(base_final) - 1, -1, -1):
            if base_final[index] in {'i', 'u', 'ü', 'm', 'n'}:
                return index

        if base_final.endswith('ng'):
            return len(base_final) - 2

        return -1

    @classmethod
    def _split_y_standard_family(cls, syllable: str) -> Tuple[str, str] | None:
        normalized = cls._normalize_for_family_matching(syllable)
        tone_number = normalized[-1] if normalized and normalized[-1].isdigit() else ''
        base = normalized[:-1] if tone_number else normalized

        if not base.startswith('y') or base.startswith('yi') or base.startswith('yu') or base.startswith('yong'):
            return None

        numeric_final: str | None = None
        if base.startswith('you'):
            numeric_final = 'iou' + tone_number
        elif base.startswith('yo'):
            numeric_final = 'io' + tone_number
        elif base.startswith('ya'):
            numeric_final = 'i' + base[1:] + tone_number
        elif base.startswith('ye'):
            numeric_final = 'i' + base[1:] + tone_number

        if not numeric_final:
            return None

        if syllable == normalized:
            return 'y', numeric_final

        return 'y', cls._marked_final_from_numeric(numeric_final)

    @classmethod
    def _split_yong_cuokou_placeholder_family(cls, syllable: str) -> Tuple[str, str] | None:
        normalized = cls._normalize_for_family_matching(syllable)
        tone_number = normalized[-1] if normalized and normalized[-1].isdigit() else ''
        base = normalized[:-1] if tone_number else normalized

        if not base.startswith('yong'):
            return None

        numeric_final = 'iong' + tone_number
        if syllable == normalized:
            return 'ɥ', numeric_final

        return 'ɥ', cls._marked_final_from_numeric(numeric_final)

    @classmethod
    def _split_w_standard_family(cls, syllable: str) -> Tuple[str, str] | None:
        normalized = cls._normalize_for_family_matching(syllable)
        tone_number = normalized[-1] if normalized and normalized[-1].isdigit() else ''
        base = normalized[:-1] if tone_number else normalized

        if not base.startswith('w') or base.startswith('wu') or base.startswith('wong'):
            return None

        numeric_final: str | None = None
        if base.startswith('wei'):
            numeric_final = 'uei' + tone_number
        elif base.startswith('weng'):
            numeric_final = 'ueng' + tone_number
        elif base.startswith('wang'):
            numeric_final = 'uang' + tone_number
        elif base.startswith('wen'):
            numeric_final = 'uen' + tone_number
        elif base.startswith('wai'):
            numeric_final = 'uai' + tone_number
        elif base.startswith('wan'):
            numeric_final = 'uan' + tone_number
        elif base.startswith('wa'):
            numeric_final = 'u' + base[1:] + tone_number
        elif base.startswith('wo'):
            numeric_final = 'u' + base[1:] + tone_number

        if not numeric_final:
            return None

        if syllable == normalized:
            return 'w', numeric_final

        return 'w', cls._marked_final_from_numeric(numeric_final)

    @classmethod
    def _split_general_abbreviated_finals(cls, syllable: str) -> Tuple[str, str] | None:
        normalized = cls._normalize_for_family_matching(syllable)
        tone_number = normalized[-1] if normalized and normalized[-1].isdigit() else ''
        base = normalized[:-1] if tone_number else normalized

        if len(base) < 2 or base.startswith(('y', 'w')):
            return None

        initial_length = 2 if len(base) >= 2 and base[:2].lower() in {'zh', 'ch', 'sh'} else 1
        initial = base[:initial_length]
        final_base = base[initial_length:]

        if initial.lower() in {'j', 'q', 'x'} and final_base.startswith('u'):
            return None

        numeric_final: str | None = None
        if final_base == 'iu':
            numeric_final = 'iou' + tone_number
        elif final_base == 'ui':
            numeric_final = 'uei' + tone_number
        elif final_base == 'un':
            numeric_final = 'uen' + tone_number

        if not numeric_final:
            return None

        initial_text = syllable[:initial_length]
        if syllable == normalized:
            return initial_text, numeric_final

        return initial_text, cls._marked_final_from_numeric(numeric_final)

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

        general_abbreviation_split = cls._split_general_abbreviated_finals(syllable)
        if general_abbreviation_split is not None:
            return general_abbreviation_split

        if len(syllable) >= 2:
            initial_candidate = syllable[:2].lower()
            if initial_candidate in {'zh', 'ch', 'sh'}:
                if len(syllable) > 2 and syllable[2] == 'i':
                    return initial_candidate, '_' + syllable[2:]
                return initial_candidate, syllable[2:]

        if syllable[0] in {'z', 'c', 's', 'r'} and len(syllable) > 1 and syllable[1] == 'i':
            return syllable[0], '_' + syllable[1:]

        if len(syllable) >= 2 and syllable[0].lower() in {'j', 'q', 'x'} and syllable[1] in cls.UMLAUT_TONE_VOWELS:
            initial = syllable[0]
            final = 'ü' + syllable[2:] if syllable[1].lower() == 'u' and len(syllable) > 2 else syllable[1:]
            return initial, final

        if len(syllable) >= 2 and syllable[0].lower() == 'y' and syllable[1] in cls.UMLAUT_TONE_VOWELS:
            final = 'ü' + syllable[2:] if syllable[1].lower() == 'u' and len(syllable) > 2 else syllable[1:]
            return 'ɥ', final

        yong_placeholder_split = cls._split_yong_cuokou_placeholder_family(syllable)
        if yong_placeholder_split is not None:
            return yong_placeholder_split

        y_standard_split = cls._split_y_standard_family(syllable)
        if y_standard_split is not None:
            return y_standard_split

        w_standard_split = cls._split_w_standard_family(syllable)
        if w_standard_split is not None:
            return w_standard_split

        if len(syllable) >= 2 and syllable[0].lower() in {'j', 'q', 'x'} and syllable[1].lower() == 'u':
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
