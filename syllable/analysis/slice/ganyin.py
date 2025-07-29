"""
定义干音类
功能：该类用于分析干音的特征、成分和类型
要求：
1. 导入syllable\analysis\slice\Syllable.py对干音的定义：
干音：由韵母和与其联结的调段构成，即 Ganyin=Rest_Segment（Final+Tone）
2. 定义一个干音分类工具类 GanyinCategorizer，根据韵母的类型把干音分成四个子类：
    - 单质干音（Single Quality Ganyin），例如 "ī", "ǒ", "ń", "ǹg", "-ī",  "èr"
    - 前长干音（Front Long Ganyin），例如 "āi", "ēi", "āo", "ōu", "ān", "ēn", "āng", "ēng"
    - 后长干音（Back Long Ganyin），例如 "iā", "iē", "iō", "uō", "īn", "īng", "ǖn", "ǖng"
    - 三质干音（Triple Quality Ganyin）, 例如 "iāo", "iōu", "uān", "uēn", "iāng", "uāng", "uēng"    
"""
from typing import Tuple, Dict
from .Syllable import Syllable


class Ganyin:
    """
    干音类，表示由韵母和与其联结的调段构成的音段
    """

    def __init__(self, final: str, tone_segment: str = None, tone: str = None):
        """
        初始化干音对象

        参数:
            final: 韵母部分
            tone_segment: 与韵母联结的调段
            tone: 声调
        """
        self.final = final
        self.tone_segment = tone_segment
        self.tone = tone

    @classmethod
    def from_syllable(cls, syllable: Syllable):
        """
        从Syllable对象创建Ganyin对象

        参数:
            syllable: Syllable对象

        返回:
            Ganyin对象
        """
        if not isinstance(syllable, Syllable):
            raise TypeError("输入必须是Syllable对象")

        return cls(
            final=syllable.final,
            tone_segment=syllable.final_tone_segment,
            tone=syllable.tone
        )

    def __str__(self):
        return f"Ganyin(final={self.final}, tone_segment={self.tone_segment}, tone={self.tone})"

    def __repr__(self):
        return self.__str__()


class GanyinCategorizer:
    """
    干音分类工具类，根据韵母类型将干音分类
    """
    @staticmethod
    def categorize(final: str) -> str:
        """
        根据韵母类型分类干音

        参数:
            final: 韵母字符串

        返回:
            干音类型字符串
        """
        if not final:
            return "未知类型"

        # 定义各类韵母的特征
        single_quality = {'i', 'u', 'ü', 'a', 'o', 'e', 'er', 'n', 'ng', 'm'}
        front_long = {'ai', 'ei', 'ao', 'ou', 'an', 'en', 'ang', 'eng'}
        back_long = {'ia', 'ie', 'io', 'uo', 'in', 'ing', 'ün', 'üng'}
        triple_quality = {'iao', 'iou', 'uan', 'uen', 'iang', 'uang', 'ueng'}

        # 标准化处理，去除声调标记
        normalized = GanyinCategorizer._normalize_final(final)

        if normalized in single_quality:
            return "单质干音"
        elif normalized in front_long:
            return "前长干音"
        elif normalized in back_long:
            return "后长干音"
        elif normalized in triple_quality:
            return "三质干音"
        else:
            return "未知类型"

    @staticmethod
    def _normalize_final(final: str) -> str:
        """
        标准化韵母字符串，去除声调标记

        参数:
            final: 原始韵母字符串

        返回:
            标准化后的韵母字符串
        """
        # 去除声调数字
        if final[-1].isdigit():
            return final[:-1]
        # 去除声调符号
        tone_marks = {'ā', 'á', 'ǎ', 'à', 'ē', 'é', 'ě', 'è',
                      'ī', 'í', 'ǐ', 'ì', 'ō', 'ó', 'ǒ', 'ò',
                      'ū', 'ú', 'ǔ', 'ù', 'ǖ', 'ǘ', 'ǚ', 'ǜ'}
        return ''.join(c for c in final if c not in tone_marks)

    @staticmethod
    def get_all_categories() -> Tuple[str, str, str, str]:
        """
        获取所有干音分类类型

        返回:
            包含所有分类类型的元组
        """
        return ("单质干音", "前长干音", "后长干音", "三质干音")
