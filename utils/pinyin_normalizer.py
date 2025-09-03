"""
拼音标准化处理模块
包含PinyinNormalizer类，提供拼音标调转换的核心功能
"""

from typing import Dict, Tuple

class PinyinNormalizer:
    """拼音标准化处理类"""

    # 特殊音质列表
    SPECIAL_QUALITIES = ["ê", "m", "n", "ng", "hm", "hn", "hng"]
    # 所有可能的声调
    TONES = ["1", "2", "3", "4", "5"]

    # 声调符号映射
    TONE_MARKS = {
        "1": "̄",  # 高调
        "2": "́",  # 升调
        "3": "̌",  # 低调
        "4": "̀",  # 降调
        "5": ""   # 轻声
    }

    @classmethod
    def normalize_special_pinyin(cls, syllabic_quality: str, tone: str) -> str:
        """标准化特殊音质拼音（ê, m, n, ng, hm, hn, hng）"""
        if not tone in cls.TONE_MARKS:
            return syllabic_quality

        if syllabic_quality == "ê":
            return "ê" + cls.TONE_MARKS[tone]
        elif syllabic_quality in ["m", "n"]:
            return syllabic_quality + cls.TONE_MARKS[tone]
        elif syllabic_quality == "ng":
            return "n" + cls.TONE_MARKS[tone] + "g"  # 标调在n上
        elif syllabic_quality in ["hm", "hn", "hng"]:
            if syllabic_quality == "hng":
                return "h" + "n" + cls.TONE_MARKS[tone] + "g"
            return "h" + syllabic_quality[1] + cls.TONE_MARKS[tone]
        return syllabic_quality

    @classmethod
    def supplement_special_pinyin(cls, pinyin_dict: Dict[str, str]) -> Dict[str, str]:
        """补充缺失的特殊音质拼音并返回新字典"""
        special_pinyin_list = [f"{sq}{tone}" for sq in cls.SPECIAL_QUALITIES for tone in cls.TONES]
        supplemented_dict = pinyin_dict.copy()

        for pinyin in special_pinyin_list:
            if pinyin not in supplemented_dict:
                supplemented_dict[pinyin] = pinyin

        print(f"新增补充的特殊拼音数量: {len(special_pinyin_list) - len(set(pinyin_dict) & set(special_pinyin_list))}")
        return supplemented_dict

    @classmethod
    def normalize_pinyin(cls, pinyin_with_tone: str) -> str:
        """将用数字标调的拼音转换为用调号标调的拼音"""
        if not pinyin_with_tone or not pinyin_with_tone[-1].isdigit():
            return pinyin_with_tone

        tone_num = pinyin_with_tone[-1]
        pinyin = pinyin_with_tone[:-1]

        # 处理v->ü/u转换
        if 'v' in pinyin:
            v_index = pinyin.index('v')
            if v_index > 0:
                prev_char = pinyin[v_index-1]
                if prev_char in ['j', 'q', 'x', 'y']:
                    pinyin = pinyin.replace('v', 'u')
                elif prev_char in ['l', 'n']:
                    pinyin = pinyin.replace('v', 'ü')
            else:
                pinyin = pinyin.replace('v', 'ü')

        # 检查是否是特殊音质拼音
        for sq in cls.SPECIAL_QUALITIES:
            if pinyin == sq:
                return cls.normalize_special_pinyin(sq, tone_num)

        # 优先在a/o/e上标调
        for vowel in ['a', 'o', 'e']:
            if vowel in pinyin:
                index = pinyin.index(vowel)
                return pinyin[:index] + vowel + cls.TONE_MARKS[tone_num] + pinyin[index+1:]

        # 处理iu/ui特殊情况
        if 'iu' in pinyin:
            index = pinyin.index('iu') + 1  # 标在u上
            return pinyin[:index] + 'u' + cls.TONE_MARKS[tone_num] + pinyin[index+1:]
        elif 'ui' in pinyin:
            index = pinyin.index('ui') + 1  # 标在i上
            return pinyin[:index] + 'i' + cls.TONE_MARKS[tone_num] + pinyin[index+1:]

        # 最后在i/u/ü上标调
        for vowel in ['i', 'u', 'ü']:
            if vowel in pinyin:
                index = pinyin.index(vowel)
                return pinyin[:index] + vowel + cls.TONE_MARKS[tone_num] + pinyin[index+1:]

        return pinyin

    @classmethod
    def process_pinyin_dict(cls, input_dict: Dict[str, str]) -> Tuple[Dict[str, str], int]:
        """处理拼音字典并返回标准化后的字典和键值不匹配计数"""
        normalized_dict = {}
        mismatch_count = 0

        supplemented_dict = cls.supplement_special_pinyin(input_dict)

        for key, value in supplemented_dict.items():
            if key != value:
                mismatch_count += 1
                normalized_dict[key] = cls.normalize_pinyin(key)
            else:
                normalized_dict[key] = cls.normalize_pinyin(key)

        return normalized_dict, mismatch_count