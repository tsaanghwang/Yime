# 片音(Pianyin)表示法
# 片音具有音质、音调、音长和音强四个属性
# 在通用现代汉语中，片音的音质和音调是必选的，音长和音强是默认的
# 片音类表示汉语音节的片音
# Pianyin notation
# A Pianyin has four attributes: quality, pitch, duration, and loudness
# In Standard Modern Chinese, quality and pitch are required, while duration and loudness are default
# The Pianyin class represents the phonetic components of a Chinese syllable
# 片音(Pianyin)分成噪音和乐音两类
# 噪音的音调是空，音质就是噪音
# 乐音的音调非空，音质和音调构成乐音

from abc import ABC, abstractmethod
from typing import Optional


class Pianyin(ABC):
    """片音(Pianyin)抽象基类，表示汉语音节的片音"""

    def __init__(self, quality: str, pitch: Optional[str] = None,
                 duration: str = 'neutral', loudness: str = 'neutral'):
        """
        初始化片音对象
        :param quality: 音质(必选)
        :param pitch: 音调(乐音必选，噪音可选)
        :param duration: 音长(默认)
        :param loudness: 音强(默认)
        """
        self.quality = quality
        self.pitch = pitch
        self.duration = duration
        self.loudness = loudness

    @abstractmethod
    def is_valid(self) -> bool:
        """检查片音对象是否有效，子类必须实现"""
        pass

    def __str__(self) -> str:
        """返回片音的通用字符串表示"""
        return (f"{self.__class__.__name__}(quality='{self.quality}'"
                f"{f', pitch={repr(self.pitch)}' if self.pitch is not None else ''}"
                f"{f', duration={repr(self.duration)}' if self.duration else ''}"
                f"{f', loudness={repr(self.loudness)}' if self.loudness else ''})")


class UnpitchedPianyin(Pianyin):
    """噪音类片音，音调为空，音质为噪音"""

    def __init__(self, quality: str, duration: str = 'neutral', loudness: str = 'neutral'):
        super().__init__(quality=quality, pitch=None, duration=duration, loudness=loudness)

    def is_valid(self) -> bool:
        """噪音只需要有音质即可有效"""
        return bool(self.quality)


class PitchedPianyin(Pianyin):
    """乐音类片音，音调非空，音质和音调构成乐音"""

    def __init__(self, quality: str, pitch: str, duration: str = 'neutral', loudness: str = 'neutral'):
        super().__init__(quality=quality, pitch=pitch, duration=duration, loudness=loudness)

    def is_valid(self) -> bool:
        """乐音需要有音质和音调才能有效"""
        return bool(self.quality and self.pitch)
