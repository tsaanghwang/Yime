"""
乐音类音元(Pitched Yinyuan/MusicalYinyuan/YueyinYinyuan)表示模块

定义汉语音节中有稳定音调的音元表示方法，继承自 yinyuan.py 中的 PitchedYinyuan 基类。
"""

from dataclasses import dataclass
from typing import Literal, cast
# from syllable.analysis.yinyuan import PitchedYinyuan, DurationType, LoudnessType
from .yinyuan import PitchedYinyuan, DurationType, LoudnessType

PitchStyle = Literal['number', 'mark']
PITCH_MARKS: dict[int, str] = {
    1: 'ˉ',
    2: 'ˊ',
    3: 'ˇ',
    4: 'ˋ',
    5: '˙',
}


@dataclass
class MusicalYinyuan(PitchedYinyuan):
    """
    乐音类音元(MusicalYinyuan/YueyinYinyuan)，表示有稳定音调的音元

    属性:
        quality: 音质(必选)
        pitch: 音调值(1-5数字表示)
        pitch_style: pitch_style('number'或'mark')
    """
    pitch_style: PitchStyle = 'number'

    def __str__(self) -> str:
        """返回音元的字符串表示，根据 pitch_style 显示音调"""
        if self.pitch_style == 'mark':
            return f"{self.quality}{PITCH_MARKS.get(cast(int, self.pitch), '')}"
        return f"{self.quality}{self.pitch}"

    def to_dict(self) -> dict[str, object]:
        """转换为字典表示"""
        result: dict[str, object] = {
            'type': 'musical',
            'quality': self.quality,
            'pitch': self.pitch,
            'pitch_style': self.pitch_style,
            'duration': self.duration,
            'loudness': self.loudness
        }
        return result

    @classmethod
    def from_dict(cls, data: dict[str, object]) -> 'MusicalYinyuan':
        """从字典创建实例"""
        return cls(
            quality=cast(str, data['quality']),
            _pitch=str(data['pitch']),
            duration=cast(DurationType, data.get('duration', 'neutral')),
            loudness=cast(LoudnessType, data.get('loudness', 'neutral')),
            pitch_style=cast(PitchStyle, data.get('pitch_style', 'number')),
        )


class YueyinYinyuan():
    pass
