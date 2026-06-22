"""
音调不定的音元(UncertainPitchYinyuan/NoiseYinyuan/ZaoyinYinyuan)表示法

噪音类音元分为两类：
1. 无调音元(UnpitchedYinyuan): 清辅音，没有音调
2. 不稳定音高音元(UnstablePitchYinyuan): 除阻浊辅音，有非规律性音高特征

在通用现代汉语中，噪音类音元实际就是声母。
"""

from dataclasses import dataclass, field
from typing import Optional, Dict, Mapping, Tuple
from .yinyuan import (
    DurationType,
    LoudnessType,
    UncertainPitchYinyuan,
)

@dataclass
class NoiseYinyuan(UncertainPitchYinyuan):
    """
    噪音类音元基类，继承自 UncertainPitchYinyuan
    包含清音和浊辅音的共同特性
    """
    quality: str = ""  # 音质特征
    duration: DurationType = 'neutral'  # 时长类型
    loudness: LoudnessType = 'neutral'  # 响度类型
    _pitch: Optional[bool] = field(default=None, init=False, repr=False)

    @property
    def pitch(self) -> Optional[bool]:
        return self._pitch

    @pitch.setter
    def pitch(self, value: Optional[bool]) -> None:
        self._pitch = value

    def is_valid(self) -> bool:
        """验证音元是否有效"""
        return bool(self.quality.strip())

    def clear_pitch(self) -> None:
        """将音元明确定义为无调音元"""
        self.pitch = None

    def _process_mid_high_model(self, data: Dict[str, Tuple[str, Optional[bool]]]) -> Dict[str, str]:
        """处理中高模型数据，将音质和音高信息转换为音元符号"""
        result: Dict[str, str] = {}
        for key, (quality, pitch) in data.items():
            self.quality = quality
            self.pitch = pitch
            if self.is_valid():
                result[key] = f"{self.quality}{'ˊ' if self.pitch else ''}"
        return result

    def convert(self, pianyin_data: Mapping[str, str]) -> dict[str, str | bool | None]:
            """将片音数据转换为音元表示

            Args:
                pianyin_data: 包含片音信息的字典

            Returns:
                返回音元表示字典，包含音质、音高和类型信息
            """
            return {
                "quality": pianyin_data.get("pinyin", ""),
                "pitch": self.pitch,
                "type": "unpitched" if self.pitch is None else "unstable_pitch"
            }


@dataclass
class ClearNoise(NoiseYinyuan):
    """
    清音类噪音(无调音元)
    对应清辅音，没有音调
    """
    def __post_init__(self) -> None:
        self.pitch = None

    @property
    def subtype(self) -> str:
        return "unpitched"


@dataclass
class VoicedNoise(NoiseYinyuan):
    """
    浊辅音类噪音(不稳定音高音元)
    可能有非规律性音高特征
    """
    def __post_init__(self) -> None:
        self.pitch = True

    @property
    def subtype(self) -> str:
        return "unstable_pitch"
