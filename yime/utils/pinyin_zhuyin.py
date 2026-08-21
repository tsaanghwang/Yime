from typing import Dict, Tuple
import sys


class PinyinZhuyinConverter:
    """拼音与注音符号转换类"""

    SPECIAL_SYLLABLES = {
        "m": "ㄇ",
        "n": "ㄋ",
        "ng": "ㄫ",
        "hm": "ㄏㄇ",
        "hn": "ㄏㄋ",
        "hng": "ㄏㄫ",
        "zhi": "ㄓ",
        "chi": "ㄔ",
        "shi": "ㄕ",
        "ri": "ㄖ",
        "zi": "ㄗ",
        "ci": "ㄘ",
        "si": "ㄙ",
    }

    ZERO_INITIAL_MAP = {
        "yi": "i",
        "ya": "ia",
        "yo": "io",
        "yao": "iao",
        "ye": "ie",
        "you": "iu",
        "yan": "ian",
        "yin": "in",
        "yang": "iang",
        "ying": "ing",
        "yong": "iong",
        "wu": "u",
        "wa": "ua",
        "wo": "uo",
        "wai": "uai",
        "wei": "ui",
        "wan": "uan",
        "wen": "un",
        "wang": "uang",
        "weng": "ong",
        "yu": "ü",
        "yue": "üe",
        "yuan": "üan",
        "yun": "ün",
    }

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
        "io": "ㄧㄛ",
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
        "0": "",
        "1": "̄",
        "2": "́",
        "3": "̌",
        "4": "̀",
        "5": "",
    }

    @classmethod
    def _normalize_pinyin(cls, pinyin: str) -> tuple[str, str]:
        if pinyin in cls.ZERO_INITIAL_MAP:
            return "", cls.ZERO_INITIAL_MAP[pinyin]

        initial = ""
        final = pinyin

        for initial_candidate in ("zh", "ch", "sh"):
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

        if initial in {"j", "q", "x"} and final.startswith("u"):
            final = "ü" + final[1:]

        return initial, final

    @classmethod
    def convert_pinyin_to_zhuyin(cls, pinyin_with_tone: str) -> str:
        """将数字标调拼音转换为注音符号"""
        if not pinyin_with_tone or not pinyin_with_tone[-1].isdigit():
            return pinyin_with_tone

        tone_num = pinyin_with_tone[-1]
        pinyin = pinyin_with_tone[:-1]

        if "v" in pinyin:
            pinyin = pinyin.replace("v", "ü")

        if pinyin in cls.SPECIAL_SYLLABLES:
            return cls.SPECIAL_SYLLABLES[pinyin] + cls.TONE_MARKS.get(tone_num, "")

        initial, final = cls._normalize_pinyin(pinyin)

        zhuyin_initial = cls.INITIALS_MAP.get(initial, "")
        zhuyin_final = cls.FINALS_MAP.get(final, final)

        return zhuyin_initial + zhuyin_final + cls.TONE_MARKS.get(tone_num, "")

    @classmethod
    def process_pinyin_dict(cls, input_dict: Dict[str, str]) -> Tuple[Dict[str, str], int]:
        """处理拼音字典并返回注音符号字典和键值不匹配计数"""
        zhuyin_dict: Dict[str, str] = {}
        mismatch_count = 0

        for key, value in input_dict.items():
            zhuyin = cls.convert_pinyin_to_zhuyin(key)
            if zhuyin != value:
                mismatch_count += 1
            zhuyin_dict[key] = zhuyin

        return zhuyin_dict, mismatch_count


def main(argv: list[str] | None = None) -> int:
    args = list(argv if argv is not None else sys.argv[1:])
    if not args:
        print("usage: python pinyin_zhuyin.py <pinyin1> [pinyin2 ...]")
        return 0

    for item in args:
        print(f"{item} -> {PinyinZhuyinConverter.convert_pinyin_to_zhuyin(item)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
