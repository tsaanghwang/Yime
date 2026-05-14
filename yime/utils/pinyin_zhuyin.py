from typing import Dict, Tuple


class PinyinZhuyinConverter:
    """拼音与注音符号转换类"""

    INITIALS_MAP = {
        "b": "ㄅ",
        "p": "ㄆ",
        "m": "ㄇ",
        "f": "ㄈ",
        "d": "ㄉ",
        "t": "ㄊ",
        "n": "ㄋ",
        "l": "ㄌ",
        "g": "ㄍ",
        "k": "ㄎ",
        "h": "ㄏ",
        "j": "ㄐ",
        "q": "ㄑ",
        "x": "ㄒ",
        "zh": "ㄓ",
        "ch": "ㄔ",
        "sh": "ㄕ",
        "r": "ㄖ",
        "z": "ㄗ",
        "c": "ㄘ",
        "s": "ㄙ",
    }

    FINALS_MAP = {
        "a": "ㄚ",
        "o": "ㄛ",
        "e": "ㄜ",
        "ê": "ㄝ",
        "ai": "ㄞ",
        "ei": "ㄟ",
        "ao": "ㄠ",
        "ou": "ㄡ",
        "an": "ㄢ",
        "en": "ㄣ",
        "ang": "ㄤ",
        "eng": "ㄥ",
        "er": "ㄦ",
        "i": "ㄧ",
        "u": "ㄨ",
        "ü": "ㄩ",
        "ia": "ㄧㄚ",
        "iao": "ㄧㄠ",
        "ie": "ㄧㄝ",
        "iu": "ㄧㄡ",
        "ian": "ㄧㄢ",
        "in": "ㄧㄣ",
        "iang": "ㄧㄤ",
        "ing": "ㄧㄥ",
        "iong": "ㄩㄥ",
        "ua": "ㄨㄚ",
        "uo": "ㄨㄛ",
        "uai": "ㄨㄞ",
        "ui": "ㄨㄟ",
        "uan": "ㄨㄢ",
        "un": "ㄨㄣ",
        "uang": "ㄨㄤ",
        "ong": "ㄨㄥ",
        "üe": "ㄩㄝ",
        "üan": "ㄩㄢ",
        "ün": "ㄩㄣ",
        "m": "ㄇ",
        "n": "ㄋ",
        "ng": "ㄫ",
        "hm": "ㄏㄇ",
        "hn": "ㄏㄋ",
        "hng": "ㄏㄫ",
    }

    TONE_MARKS = {
        "1": "̄",
        "2": "́",
        "3": "̌",
        "4": "̀",
        "5": "",
    }

    @classmethod
    def convert_pinyin_to_zhuyin(cls, pinyin_with_tone: str) -> str:
        """将数字标调拼音转换为注音符号"""
        if not pinyin_with_tone or not pinyin_with_tone[-1].isdigit():
            return pinyin_with_tone

        tone_num = pinyin_with_tone[-1]
        pinyin = pinyin_with_tone[:-1]

        if "v" in pinyin:
            pinyin = pinyin.replace("v", "ü")

        if pinyin in ["m", "n", "ng", "hm", "hn", "hng"]:
            return cls.FINALS_MAP.get(pinyin, pinyin) + cls.TONE_MARKS[tone_num]

        initial = ""
        final = pinyin

        for initial_candidate in ["zh", "ch", "sh"]:
            if pinyin.startswith(initial_candidate):
                initial = initial_candidate
                final = pinyin[len(initial_candidate):]
                break

        if not initial:
            for initial_candidate in cls.INITIALS_MAP:
                if pinyin.startswith(initial_candidate):
                    initial = initial_candidate
                    final = pinyin[len(initial_candidate):]
                    break

        zhuyin_initial = cls.INITIALS_MAP.get(initial, "")
        zhuyin_final = cls.FINALS_MAP.get(final, final)

        return zhuyin_initial + zhuyin_final + cls.TONE_MARKS[tone_num]

    @classmethod
    def process_pinyin_dict(cls, input_dict: Dict[str, str]) -> Tuple[Dict[str, str], int]:
        """处理拼音字典并返回注音符号字典和键值不匹配计数"""
        zhuyin_dict = {}
        mismatch_count = 0

        for key, value in input_dict.items():
            zhuyin = cls.convert_pinyin_to_zhuyin(key)
            if zhuyin != value:
                mismatch_count += 1
            zhuyin_dict[key] = zhuyin

        return zhuyin_dict, mismatch_count