"""
音节分类工具类
功能：负责音节切分，并复用干音分类器的分类能力。
"""
from typing import Tuple

try:
    from .ganyin_categorizer import GanyinCategorizer
    from .syllable_encoding_pipeline import SyllableEncodingPipeline
except ImportError:
    from ganyin_categorizer import GanyinCategorizer
    from syllable_encoding_pipeline import SyllableEncodingPipeline


class SyllableCategorizer(GanyinCategorizer):
    """面向旧调用方的最薄兼容壳：保留类名，并转发编码流水线入口。"""

    @classmethod
    def split_syllable(cls, syllable: str) -> Tuple[str, str]:
        """兼容旧接口，转发到编码专用切分流水线。"""
        return SyllableEncodingPipeline.split_normalized_syllable(syllable)

    analyze_syllable = staticmethod(SyllableEncodingPipeline.analyze_syllable)
    convert_tone_mark_to_number = staticmethod(SyllableEncodingPipeline.normalize_syllable)
