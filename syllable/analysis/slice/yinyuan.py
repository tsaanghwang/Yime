"""
音元(Yinyuan)表示法模块

定义表示汉语音节音元的类层次结构。音元具有四个属性：
1. 音质(quality) - 必选，表示声音的基本特性
2. 音调(pitch) - 乐音必选，噪音可选
3. 音长(duration) - 默认'neutral'
4. 音强(loudness) - 默认'neutral'

音元分类体系：
1. 有调音元(PitchedYinyuan): 有稳定音调
2. 不定调音元(IndeterminatePitchYinyuan/NoiseYinyuan): 
   - 无调音元(UnpitchedYinyuan): 完全无调(如清辅音)
   - 不稳定音高音元(UnstablePitchYinyuan): 有不稳定/非规律性音高(如浊阻音)
"""

from typing import Optional, Union, Literal
from abc import ABC, abstractmethod
from dataclasses import dataclass

# 类型别名定义
DurationType = Literal['short', 'neutral', 'long']
LoudnessType = Literal['weak', 'neutral', 'strong']
PitchType = Union[str, bool, None]

@dataclass
class YinyuanBase(ABC):
    """音元基类，定义音元的基本属性和行为"""
    quality: str
    duration: DurationType = 'neutral'
    loudness: LoudnessType = 'neutral'

    @property
    @abstractmethod
    def pitch(self) -> PitchType:
        """返回音调信息"""
        pass

    @property
    @abstractmethod
    def type(self) -> str:
        """返回音元类型标识"""
        pass

    @abstractmethod
    def is_valid(self) -> bool:
        """验证音元是否有效"""
        pass

    def __str__(self) -> str:
        """友好的字符串表示"""
        attrs = [
            f"quality={repr(self.quality)}",
            f"duration={repr(self.duration)}",
            f"loudness={repr(self.loudness)}"
        ]
        return f"{self.__class__.__name__}({', '.join(attrs)})"

@dataclass
class PitchedYinyuan(YinyuanBase):
    """有稳定音调的音元"""
    pitch_value: str  # 必须放在没有默认值的参数前面
    duration: DurationType = 'neutral'
    loudness: LoudnessType = 'neutral'

    @property
    def pitch(self) -> str:
        return self.pitch_value

    @property
    def type(self) -> str:
        return "pitched"

    def is_valid(self) -> bool:
        return bool(self.quality.strip()) and bool(self.pitch_value.strip())

    def __str__(self) -> str:
        base_str = super().__str__()
        return base_str[:-1] + f", pitch={repr(self.pitch_value)})"

@dataclass
class IndeterminatePitchYinyuan(YinyuanBase, ABC):
    """
    不定调音元(NoiseYinyuan)基类
    包含无调音元和不稳定音高音元的共同特性
    """
    @property
    def type(self) -> str:
        return "noise"

@dataclass
class UnstablePitchYinyuan(IndeterminatePitchYinyuan):
    """有不稳定/非规律性音高的音元"""
    @property
    def pitch(self) -> bool:
        return True

    @property
    def subtype(self) -> str:
        return "unstable_pitch"

    def is_valid(self) -> bool:
        return bool(self.quality.strip())

@dataclass
class UnpitchedYinyuan(IndeterminatePitchYinyuan):
    """完全无调的音元"""
    @property
    def pitch(self) -> None:
        return None

    @property
    def subtype(self) -> str:
        return "unpitched"

    def is_valid(self) -> bool:
        return bool(self.quality.strip())

def create_yinyuan(
    quality: str,
    pitch: Optional[str] = None,
    unstable_pitch: bool = False,
    duration: DurationType = 'neutral',
    loudness: LoudnessType = 'neutral'
) -> YinyuanBase:
    """
    创建音元对象的工厂函数
    :param quality: 音质(必选)
    :param pitch: 音调(有调音元必选)
    :param unstable_pitch: 是否为不稳定音高
    :param duration: 音长
    :param loudness: 音强
    :return: 对应的音元对象
    """
    if unstable_pitch:
        return UnstablePitchYinyuan(quality, duration, loudness)
    if pitch is not None:
        return PitchedYinyuan(quality, pitch, duration, loudness)
    return UnpitchedYinyuan(quality, duration, loudness)