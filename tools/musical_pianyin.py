# Pitched Sound Representation Module
# 乐音表示模块
#
# This module defines a class for representing pitched_yinyuan sounds in Chinese phonetics,
# supporting various representation methods such as pianyin and yinyuan.
#
# 乐音 (yueyin) 由音质和音高(与音质联结的调段)构成
# 音质 (quality): 必选属性
# 音调 (pitch): 必选属性
#
# A pitched_yinyuan sound (yueyin) consists of quality and pitch (a tone segment associated with the quality).
# Quality: required attribute
# Pitch: required attribute

from pianyin.pianyin import PitchedPianyin


class Yueyin(PitchedPianyin):
    """
    Represents the pitched_yinyuan sound of a Chinese syllable.
    表示汉语音节的乐音 (yueyin) 

    Attributes:
        quality (str): The quality of the pitched_yinyuan sound (音质/quality)
        tone_segment (str): The tone segment (音调/pitch) using 5-level notation (1-5)
        representation (str): Representation method (pianyin/yinyuan)
        tone_style (str): Tone display style ('number' or 'mark')
    """

    TONE_SEGMENT_MARKS = {
        "5": "˥",  # 高平调
        "4": "˦",  # 次高平调
        "3": "˧",  # 中平调
        "2": "˨",  # 次低平调
        "1": "˩",  # 低平调
    }

    def __init__(self, quality, tone_segment, representation="pianyin", tone_style="number"):
        """
        Initializes a Yueyin instance.

        Args:
            quality (str): The quality of the pitched_yinyuan sound.
            tone_segment (str): The tone segment (1-5).
            representation (str): Representation method ('pianyin' or 'yinyuan').
            tone_style (str): Tone display style ('number' or 'mark').
        """
        super().__init__(quality, tone_segment)
        self.representation = representation
        self.tone_style = tone_style

    def __str__(self):
        """
        Returns the string representation of the pitched_yinyuan sound.
        Format depends on representation and tone_style attributes.
        """
        if self.representation == "yinyuan":
            return self._yinyuan_representation()
        return self._pianyin_representation()

    def _pianyin_representation(self):
        """Returns pianyin-style representation with tone marks or numbers"""
        if self.tone_style == "mark":
            return f"{self.quality}{self.TONE_SEGMENT_MARKS.get(self.pitch, '')}"
        return f"{self.quality}{self.pitch}"

    def _yinyuan_representation(self):
        """Returns yinyuan-style representation with tone marks or numbers"""
        # Yinyuan representation could be implemented differently
        # Here we use the same format as pinyin for demonstration
        return self._pianyin_representation()

    def to_dict(self):
        """Returns a dictionary representation of the Yueyin object"""
        return {
            "quality": self.quality,
            "pitch": self.pitch,
            "representation": self.representation,
            "tone_style": self.tone_style,
            "duration": self.duration,
            "loudness": self.loudness
        }

    @classmethod
    def from_dict(cls, data):
        """Creates a Yueyin instance from a dictionary"""
        return cls(
            quality=data.get("quality"),
            tone_segment=data.get("pitch"),
            representation=data.get("representation", "pianyin"),
            tone_style=data.get("tone_style", "number")
        )
