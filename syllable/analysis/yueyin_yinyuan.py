"""乐音类音元对象。"""

from typing import Literal
from .pitched_yinyuan import MusicalYinyuan, DurationType
from syllable.pianyin import PitchedPianyin

PitchStyle = Literal['number', 'mark']
LoudnessType = Literal['weak', 'neutral', 'strong']


class YueyinYinyuan(MusicalYinyuan):
    """
    乐音类音元(YueyinYinyuan) - MusicalYinyuan 的中文别名类。

    本类只表示“已经归并完成的乐音音元对象”。
    片音到音元的归并规则由 ``YueyinMapper`` 承担，不再混入对象本身。
    """

    def __init__(self, quality: str, pitch: str, duration: DurationType = 'neutral',
                loudness: LoudnessType = 'neutral', pitch_style: PitchStyle = 'number'):
        super().__init__(
            quality=quality,
            _pitch=pitch,
            duration=duration,
            loudness=loudness,
            pitch_style=pitch_style,
        )

    def to_chinese_dict(self) -> dict[str, str]:
        """转换为中文键名的字典表示"""
        return {
            '类型': '乐音',
            '音质': self.quality,
            '音调': self.pitch,
            'pitch_style': self.pitch_style,
            '音长': self.duration,
            '音强': self.loudness
        }

    @classmethod
    def from_pianyin(cls, pianyin: PitchedPianyin) -> 'YueyinYinyuan':
        """从乐音片音对象创建乐音音元对象。"""
        if pianyin.pitch is None:
            raise ValueError("YueyinYinyuan 只能由带音高的乐音片音创建")

        return cls(
            quality=pianyin.quality,
            pitch=pianyin.pitch,
            duration='neutral',
            loudness='neutral',
            pitch_style='number'
        )

    def __str__(self) -> str:
        """中文友好的字符串表示"""
        return f"乐音类音元(音质={self.quality}, 音调={self.pitch})"
