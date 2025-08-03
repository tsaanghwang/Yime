"""
定义干音类
功能：表示音节的干音
要求：
导入音节类对干音的定义：干音由韵母和与其联结的调段构成，即 Ganyin = Final+Tone
"""
from typing import Dict
import sys
import json
import os
from collections import defaultdict
from typing import Dict, Tuple

try:
    from syllable import Syllable  # When imported as part of a package
except ImportError:
    from syllable import Syllable  # When run directly as a script


class Ganyin:
    """
    干音类，表示由韵母和与其联结的调段构成的音段
    """

    def __init__(self, final: str, gandiao: str = None):
        """
        初始化干音对象

        参数:
            final: 韵母部分
            gandiao: 与韵母联结的调段 = 声调( 音节的 tone)
        """
        self.final = final
        self.gandiao = gandiao

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
            gandiao=syllable.tone  # 直接用 tone 作为 gandiao
        )

    def __str__(self):
        return f"Ganyin(final={self.final}, gandiao={self.gandiao})"

    def __repr__(self):
        return
