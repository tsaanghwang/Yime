"""
不定调音元(IndeterminatePitchYinyuan/NoiseYinyuan/ZaoyinYinyuan)表示法

噪音类音元分为两类：
1. 无调音元(UnpitchedYinyuan): 清辅音，没有音调
2. 不稳定音高音元(UnstablePitchYinyuan): 除阻浊辅音，有非规律性音高特征

在通用现代汉语中，噪音类音元实际就是声母。
"""

from dataclasses import dataclass
from typing import Optional, Dict
from yinyuan import (
    UnpitchedYinyuan,
    UnstablePitchYinyuan,
    DurationType,
    LoudnessType,
    IndeterminatePitchYinyuan,
)

@dataclass
class NoiseYinyuan(IndeterminatePitchYinyuan):
    """
    噪音类音元基类，继承自 IndeterminatePitchYinyuan
    包含清音和浊辅音的共同特性
    """
    quality: str = ""  # 音质特征
    duration: DurationType = 'neutral'  # 时长类型
    loudness: LoudnessType = 'neutral'  # 响度类型
    pitch: Optional[bool] = None  # 改为普通实例属性，None表示无调，True表示有不稳定音高

    def is_valid(self) -> bool:
        """验证音元是否有效"""
        return bool(self.quality.strip())

    def clear_pitch(self) -> None:
        """将音元明确定义为无调音元"""
        self.pitch = None

    def _process_mid_high_model(self, data: Dict) -> Dict:
        """处理中高模型数据，将音质和音高信息转换为音元符号"""
        result = {}
        for key, (quality, pitch) in data.items():
            self.quality = quality
            self.pitch = pitch  # 现在可以直接设置
            if self.is_valid():
                result[key] = f"{self.quality}{'ˊ' if self.pitch else ''}"
        return result

    def _change_pitch_style(self, data: Dict) -> Dict:
        """
        修改音调标记风格：将所有字符串中的 'ˊ' 替换为 'ˉ'，并兼容 parts 既可能为 dict 也可能为 str 的情况。
        """
        result = {}
        for shouyin_type, shouyin_data in data.items():
            result[shouyin_type] = {}
            for shouyin_name, parts in shouyin_data.items():
                if isinstance(parts, dict):
                    result[shouyin_type][shouyin_name] = {
                        part: (symbol.replace("ˊ", "ˉ") if isinstance(symbol, str) else symbol)
                        for part, symbol in parts.items()
                    }
                elif isinstance(parts, str):
                    result[shouyin_type][shouyin_name] = parts.replace("ˊ", "ˉ")
                else:
                    result[shouyin_type][shouyin_name] = parts
        return result

    def convert(self, pinyin_data: dict) -> dict:
            """将拼音数据转换为音元表示

            Args:
                pinyin_data: 包含拼音信息的字典

            Returns:
                返回音元表示字典，包含音质、音高和类型信息
            """
            if not isinstance(pinyin_data, dict):
                return {}

            return {
                "quality": pinyin_data.get("pinyin", ""),
                "pitch": self.pitch,
                "type": "unpitched" if self.pitch is None else "unstable_pitch"
            }
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
        return bool(self.quality.strip())

    @staticmethod
    def get_yinyuan_code(initial: str) -> str:
        return f"UPY_{initial.upper()}"


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
        return bool(self.quality.strip())

    @staticmethod
    def get_yinyuan_code(initial: str) -> str:
        return f"UPY_{initial.upper()}"
