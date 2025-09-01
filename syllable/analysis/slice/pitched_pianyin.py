"""
Pitched Segment Representation Module
乐音类片音表示模块
#
This module defines a class for representing pitched segments in Chinese phonetics.
#
乐音 (YueyinPianyin) 由音质和音高构成.
乐音的音高特指与乐音的音质联结的调段.
音质 (quality): 必选属性
音高 (pitch): 必选属性
#
A pitched segment (yueyin) consists of quality and pitch (a tone segment associated with the quality).
Quality: required attribute
Pitch: required attribute
"""

from pitched_yinyuan import MusicalYinyuan


class PitchedPianyin:
    def __init__(self, quality, pitch):
        if not quality:
            raise ValueError("quality cannot be empty")
        if not pitch:
            raise ValueError("pitch cannot be empty")

        self.quality = quality
        self.pitch = pitch
        self.duration = None
        self.loudness = None


class YueyinPianyin(PitchedPianyin):
    """
    Represents the pitched segment of a Chinese syllable.
    表示汉语音节的乐音(yueyin)

    Attributes:
        quality(str): The quality of the pitched segment(音质/quality)
        pitch(str): The pitch(音高) using 5-level notation(1-5)
        representation(str): Representation method(pianyin/yinyuan)
        pitch_style(str): Tone display style('number' or 'mark')
    """

    PITCH_LEVELS = {
        "5": "˥",  # 高平
        "4": "˦",  # 次高平调
        "3": "˧",  # 中平调
        "2": "˨",  # 次低平调
        "1": "˩",  # 低平
    }

    def __init__(self, quality, pitch, representation="pianyin", pitch_style="number"):
        """
        Initializes a YueyinPianyin instance.

        Args:
            quality(str): The quality of the pitched segment.
            pitch(str): The tone segment(1-5).
            representation(str): Representation method('pianyin' or 'yinyuan').
            pitch_style(str): Tone display style('number' or 'mark').
        """
        super().__init__(quality, pitch)
        self.representation = representation
        self.pitch_style = pitch_style

    def __str__(self):
        """
        Returns the string representation of the pitched segment.
        Format depends on representation and pitch_style attributes.
        """
        if self.representation == "yinyuan":
            return self._yinyuan_representation()
        return self._pianyin_representation()

    def _pianyin_representation(self):
        """Returns pianyin-style representation with tone marks or numbers"""
        if self.pitch_style == "mark":
            return f"{self.quality}{self.PITCH_LEVELS.get(self.pitch, '')}"
        return f"{self.quality}{self.pitch}"

    def _yinyuan_representation(self):
        """Returns yinyuan-style representation with tone marks or numbers"""
        # Yinyuan representation could be implemented differently
        # Here we use the same format as pinyin for demonstration
        return self._pianyin_representation()

    def to_dict(self):
        """Returns a dictionary representation of the YueyinPianyin object"""
        return {
            "quality": self.quality,
            "pitch": self.pitch,
            "representation": self.representation,
            "pitch_style": self.pitch_style,
            "duration": self.duration,
            "loudness": self.loudness
        }

    @classmethod
    def from_dict(cls, data):
        """Creates a YueyinPianyin instance from a dictionary"""
        return cls(
            quality=data.get("quality"),
            pitch=data.get("pitch"),
            representation=data.get("representation", "pianyin"),
            pitch_style=data.get("pitch_style", "number")
        )

    @classmethod
    def create_yueyin(cls, quality, pitch, representation="pianyin", pitch_style="number"):
        """
        创建乐音类片音实例的便捷方法

        Args:
            quality (str): 音质/quality
            pitch (str): 音高/pitch (1-5)
            representation (str): 表示方法 ('pianyin' 或 'yinyuan')
            pitch_style (str): 声调显示样式 ('number' 或 'mark')

        Returns:
            YueyinPianyin: 创建的乐音类片音实例
        """
        return cls(
            quality=quality,
            pitch=pitch,
            representation=representation,
            pitch_style=pitch_style
        )
