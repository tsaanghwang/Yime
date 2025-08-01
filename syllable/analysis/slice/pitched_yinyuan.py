"""
乐音(Pitched Yinyuan/Musical Yinyuan/Yueyin)表示模块

定义汉语音节中有稳定音调的音元表示方法，继承自 yinyuan.py 中的 PitchedYinyuan 基类。
"""

from dataclasses import dataclass
from typing import Literal
from syllable.analysis.slice.yinyuan import PitchedYinyuan, DurationType, LoudnessType

ToneStyle = Literal['number', 'mark']

@dataclass
class MusicalYinyuan(PitchedYinyuan):
    """
    乐音类音元(Musical Yinyuan/Yueyin)，表示有稳定音调的音元
    
    属性:
        quality: 音质(必选)
        pitch_value: 音调值(1-5数字表示)
        tone_style: 音调显示风格('number'或'mark')
    """
    tone_style: ToneStyle = 'number'
    
    TONE_MARKS = {
        "5": "˥",  # 高平调
        "4": "˦",  # 次高平调
        "3": "˧",  # 中平调
        "2": "˨",  # 次低平调
        "1": "˩",  # 低平调
    }

    def __str__(self) -> str:
        """返回音元的字符串表示，根据 tone_style 显示音调"""
        if self.tone_style == 'mark':
            return f"{self.quality}{self.TONE_MARKS.get(self.pitch_value, '')}"
        return f"{self.quality}{self.pitch_value}"

    def to_dict(self) -> dict:
        """转换为字典表示"""
        return {
            'type': 'musical',
            'quality': self.quality,
            'pitch': self.pitch_value,
            'tone_style': self.tone_style,
            'duration': self.duration,
            'loudness': self.loudness
        }

    @classmethod
    def from_dict(cls, data: dict) -> 'MusicalYinyuan':
        """从字典创建实例"""
        return cls(
            quality=data['quality'],
            pitch_value=data['pitch'],
            duration=data.get('duration', 'neutral'),
            loudness=data.get('loudness', 'neutral'),
            tone_style=data.get('tone_style', 'number')
        )