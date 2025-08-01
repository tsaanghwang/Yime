"""
不定调音元(IndeterminatePitchYinyuan/NoiseYinyuan/Zaoyin)表示法

噪音类音元分为两类：
1. 无调音元(UnpitchedYinyuan): 清辅音，没有音调
2. 不稳定音高音元(UnstablePitchYinyuan): 除阻浊辅音，有非规律性音高特征

在通用现代汉语中，噪音类音元通常对应音节中的声母实际发音。
"""

from dataclasses import dataclass
from typing import Optional
from syllable.analysis.slice.yinyuan import (
    IndeterminatePitchYinyuan,
    DurationType,
    LoudnessType
)


@dataclass
class NoiseYinyuan(IndeterminatePitchYinyuan):
    """
    噪音类音元基类，继承自 IndeterminatePitchYinyuan
    包含清音和浊辅音的共同特性
    """

    def clear_pitch(self) -> None:
        """将音元明确定义为无调音元"""
        self.pitch = None


@dataclass
class ClearNoise(NoiseYinyuan):
    """
    清音类噪音(无调音元)
    对应清辅音，没有音调
    """
    pitch: None = None  # 明确标注无音调

    @property
    def subtype(self) -> str:
        return "unpitched"

    def is_valid(self) -> bool:
        """只需要有音质即可有效"""
        return bool(self.quality.strip())


@dataclass
class VoicedNoise(NoiseYinyuan):
    """
    浊辅音类噪音(不稳定音高音元)
    可能有非规律性音高特征
    """
    pitch: bool = True  # 表示有不稳定音高

    @property
    def subtype(self) -> str:
        return "unstable_pitch"

    def is_valid(self) -> bool:
        """只需要有音质即可有效"""
        return bool(self.quality.strip())
