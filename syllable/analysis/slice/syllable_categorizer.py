"""
音节分类工具类
功能：负责音节切分，并复用干音分类器的分类能力。
"""
from typing import Dict, Tuple

try:
    from .ganyin_categorizer import GanyinCategorizer
    from .syllable_encoding_pipeline import SyllableEncodingPipeline
except ImportError:
    from ganyin_categorizer import GanyinCategorizer
    from syllable_encoding_pipeline import SyllableEncodingPipeline


class SyllableCategorizer(GanyinCategorizer):
    """面向旧调用方的兼容壳：保留分类能力，并转发编码相关逻辑。"""

    @classmethod
    def generate_shouyin_data(cls, pinyin_data: Dict[str, str]) -> Dict[str, str]:
        """兼容旧接口，继续复用继承来的首音数据生成逻辑。"""
        return GanyinCategorizer.generate_shouyin_data(pinyin_data)

    @classmethod
    def split_syllable(cls, syllable: str) -> Tuple[str, str]:
        """兼容旧接口，转发到编码专用切分流水线。"""
        return SyllableEncodingPipeline.split_normalized_syllable(syllable)

    @staticmethod
    def analyze_syllable(syllable: str) -> Tuple[str, str]:
        """兼容旧接口，转发到编码专用完整流水线。"""
        return SyllableEncodingPipeline.analyze_syllable(syllable)

    @staticmethod
    def convert_tone_mark_to_number(syllable: str) -> str:
        """兼容旧接口，转发到编码专用规范化流水线。"""
        return SyllableEncodingPipeline.normalize_syllable(syllable)
