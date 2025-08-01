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

from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Optional, Union, Literal

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
class IndeterminatePitchYinyuan(YinyuanBase, ABC):
    """
    不定调音元(NoiseYinyuan)基类
    包含无调音元和不稳定音高音元的共同特性
    """
    @property
    def type(self) -> str:
        return "noise"

# 修改 UnstablePitchYinyuan 和 UnpitchedYinyuan 类
@dataclass
class UnstablePitchYinyuan(IndeterminatePitchYinyuan):
    """有不稳定/非规律性音高的音元"""
    quality: str
    duration: DurationType = 'neutral'
    loudness: LoudnessType = 'neutral'

    @property
    def pitch(self) -> bool:
        return True

    @property
    def subtype(self) -> str:
        return "unstable_pitch"

    def is_valid(self) -> bool:
        return bool(self.quality.strip())
        
    @staticmethod
    def _get_yinyuan_code(initial: str) -> str:
        """生成音元代码"""
        return f"UPY_{initial.upper()}"
        
    @staticmethod
    def _get_yinyuan_code(initial: str) -> str:
        """生成音元代码"""
        return f"UY_{initial.upper()}"

@dataclass
class UnpitchedYinyuan(IndeterminatePitchYinyuan):
    """完全无调的音元"""
    quality: str
    duration: DurationType = 'neutral'
    loudness: LoudnessType = 'neutral'

    @property
    def pitch(self) -> None:
        return None

    @property
    def subtype(self) -> str:
        return "unpitched"

    def is_valid(self) -> bool:
        return bool(self.quality.strip())
        
    @staticmethod
    def _get_yinyuan_code(initial: str) -> str:
        """生成音元代码"""
        return f"UPY_{initial.upper()}"

# (Removed incomplete create_yinyuan function and duplicate UnpitchedYinyuan class)
