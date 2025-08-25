"""
噪音类片音表示法
噪音类片音分为两类：清辅音和浊辅音。
清音没有音调，浊辅音类噪音有非规律性的音高特征。
浊辅音类噪音的音调不具有辨义作用，通常不标调。
在通用现代汉语中，噪音类片音就是声母的音值（分布在音节中的声母的实际发音）。
噪音类表示汉语音节的噪音
"""

from abc import ABC, abstractmethod
from typing import Optional


class UnpitchedPianyin(ABC):
    """噪音类片音，清音无音调，浊辅音可能有音调"""

    def __init__(self, quality: str, duration: str = '', loudness: str = '', pitch: Optional[str] = None):
        """
        初始化噪音对象
        :param quality: 音质(必选)
        :param duration: 音长(默认)
        :param loudness: 音强(默认)
        :param pitch: 音调(可选)，None表示清音无音调，不传或特定值表示浊辅音可能有音调
        """
        self.quality = quality
        self.duration = duration
        self.loudness = loudness
        self.pitch = pitch

    def clear_pitch(self) -> None:
        """明确定义为清音(无音调)"""
        self.pitch = None

    @abstractmethod
    def is_valid(self) -> bool:
        """检查噪音对象是否有效，子类必须实现"""
        pass

    def __str__(self) -> str:
        """返回噪音的通用字符串表示"""
        return (f"{self.__class__.__name__}(quality='{self.quality}'"
                f"{f', pitch={repr(self.pitch)}' if self.pitch is not None else ''}"
                f"{f', duration={repr(self.duration)}' if self.duration else ''}"
                f"{f', loudness={repr(self.loudness)}' if self.loudness else ''})")


class ClearPianyin(UnpitchedPianyin):
    """清音类噪音，无音调"""

    def __init__(self, quality: str, duration: str = '', loudness: str = ''):
        super().__init__(quality=quality, duration=duration, loudness=loudness, pitch=None)

    def is_valid(self) -> bool:
        """清音只需要有音质即可有效"""
        return bool(self.quality)


class VoicedUnpitchedPianyin(UnpitchedPianyin):
    """浊辅音类噪音，可能有音调"""

    def __init__(self, quality: str, pitch: Optional[str] = None, duration: str = '', loudness: str = ''):
        super().__init__(quality=quality, pitch=pitch, duration=duration, loudness=loudness)

    def is_valid(self) -> bool:
        """浊辅音需要有音质，音调可选"""
        return bool(self.quality)
