"""
syllable/analysis/slice/syllable_segmenter.py

音节切分模块 - 负责从Syllable对象中提取首音和干音
"""

from .Syllable import Syllable
from .shouyin import Initial


class SyllableSegmenter:
    """
    音节切分器，负责从Syllable对象中提取Initial对象

    功能:
    1. 从音节中提取首音(Initial)部分
    2. 将音节的首音部分转换为Initial对象
    3. 保留音节与首音的关联关系
    """

    @staticmethod
    def extract_initial(syllable: Syllable, representation='pinyin', tone_style='number') -> Initial:
        """
        从音节对象中提取首音并创建Initial对象

        参数:
            syllable: Syllable对象
            representation: 表示方法(pinyin/phonetic/pianyin/yinyuan)
            tone_style: 声调显示风格('number'或'mark')

        返回:
            Initial对象
        """
        if not isinstance(syllable, Syllable):
            raise TypeError("输入必须是Syllable对象")

        # 从音节中获取声母和与声母联结的调段
        consonant = syllable.initial
        tone_segment = syllable.initial_tone_segment

        # 创建Initial对象
        initial_obj = Initial(
            consonant=consonant,
            tone_segment=tone_segment,
            representation=representation,
            tone_style=tone_style
        )

        return initial_obj

    @staticmethod
    def split_syllable(syllable: Syllable, representation='pinyin', tone_style='number'):
        """
        切分音节对象，返回首音和剩余部分

        参数:
            syllable: Syllable对象
            representation: 表示方法
            tone_style: 声调显示风格

        返回:
            tuple: (Initial对象, rest部分信息)
        """
        initial_obj = SyllableSegmenter.extract_initial(
            syllable, representation, tone_style)

        # 获取剩余部分(干音)信息
        rest_info = {
            'final': syllable.final,
            'final_tone_segment': syllable.final_tone_segment,
            'tone': syllable.tone
        }

        return initial_obj, rest_info
