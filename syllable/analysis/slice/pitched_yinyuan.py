"""
乐音类音元(Pitched Yinyuan/MusicalYinyuan/YueyinYinyuan)表示模块

定义汉语音节中有稳定音调的音元表示方法，继承自 yinyuan.py 中的 PitchedYinyuan 基类。
"""

from dataclasses import dataclass
from typing import Literal
from yinyuan import PitchedYinyuan, DurationType, LoudnessType

PitchStyle = Literal['number', 'mark']


@dataclass
class MusicalYinyuan(PitchedYinyuan):
    """
    乐音类音元(MusicalYinyuan/YueyinYinyuan)，表示有稳定音调的音元

    属性:
        quality: 音质(必选)
        pitch: 音调值(1-5数字表示)
        pitch_style: 音调显示风格('number'或'mark')
    """
    pitch_style: PitchStyle = 'number'

    PITCH_LEVELS = {
        "5": "˥",  # 高平调
        "4": "˦",  # 次高平调
        "3": "˧",  # 中平调
        "2": "˨",  # 次低平调
        "1": "˩",  # 低平调
    }

    def __str__(self) -> str:
        """返回音元的字符串表示，根据 pitch_style 显示音调"""
        if self.pitch_style == 'mark':
            return f"{self.quality}{self.PITCH_LEVELS.get(self.pitch, '')}"
        return f"{self.quality}{self.pitch}"

    def to_dict(self) -> dict:
        """转换为字典表示"""
        return {
            'type': 'musical',
            'quality': self.quality,
            'pitch': self.pitch,
            'pitch_style': self.pitch_style,
            'duration': self.duration,
            'loudness': self.loudness
        }

    @classmethod
    def from_dict(cls, data: dict) -> 'MusicalYinyuan':
        """从字典创建实例"""
        return cls(
            quality=data['quality'],
            pitch=data['pitch'],
            duration=data.get('duration', 'neutral'),
            loudness=data.get('loudness', 'neutral'),
            pitch_style=data.get('pitch_style', 'number')
        )


class YueyinYinyuan():
    pass
