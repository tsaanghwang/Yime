# yinyuan/pitched_yinyuan.py
import json
from typing import Optional
from pianyin.pianyin import PitchedPianyin
from .yinyuan import Yinyuan


class PitchedYinyuan(Yinyuan, PitchedPianyin):
    """乐音类音元，继承自Yinyuan和PitchedPianyin类"""

    # 定义音调标记映射
    TONE_SEGMENT_MARKS = {
        "5": "˥",  # 高平调
        "4": "˦",  # 次高平调
        "3": "˧",  # 中平调
        "2": "˨",  # 次低平调
        "1": "˩",  # 低平调
    }

    def __init__(self, code: Optional[int] = None, notation: str = "",
                 config_path='yinyuan/variables_of_pitch_and_quality.json', **kwargs):
        """
        初始化乐音类音元对象

        参数:
            code (int): 音元代码，默认为None
            notation (str): 音元符号表示，默认为空字符串
            config_path (str): 配置文件路径
            **kwargs: 传递给父类的其他参数
        """
        Yinyuan.__init__(self, config_path=config_path)
        PitchedPianyin.__init__(self, quality="", pitch="")
        self.code = code
        self.notation = notation
        self.representation = "yinyuan"

    @classmethod
    def from_pianyin(cls, pianyin: PitchedPianyin) -> 'PitchedYinyuan':
        """
        从乐音类片音创建音元对象

        参数:
            pianyin (PitchedPianyin): 乐音类片音对象

        返回:
            PitchedYinyuan: 转换后的音元对象
        """
        if not pianyin.is_valid():
            raise ValueError(
                "Invalid PitchedPianyin: missing required quality or pitch")

        # 构建基本符号
        notation = f"{pianyin.quality}{cls.TONE_SEGMENT_MARKS.get(pianyin.pitch, '')}"

        # 获取音元代码
        base_notation = f"{pianyin.quality}{cls.TONE_SEGMENT_MARKS.get(pianyin.pitch, '')}"
        code = cls._get_yinyuan_code(base_notation)

        # 创建实例并定义属性
        instance = cls(code=code, notation=notation)
        instance.quality = pianyin.quality
        instance.pitch = pianyin.pitch
        instance.duration = pianyin.duration
        instance.loudness = pianyin.loudness

        return instance

    def to_pianyin(self) -> PitchedPianyin:
        """
        将音元对象转换回片音对象

        返回:
            PitchedPianyin: 转换后的片音对象
        """
        if self.code is None:
            raise ValueError("PitchedYinyuan code is required for conversion")

        # 解析基本音质和音调
        base_notation = self._get_base_notation_from_code(self.code)
        if not base_notation:
            raise ValueError(f"Invalid PitchedYinyuan code: {self.code}")

        quality = base_notation[0]
        pitch_mark = base_notation[1:]

        # 从音调标记反查数字音调
        pitch = next(
            (k for k, v in self.TONE_SEGMENT_MARKS.items() if v == pitch_mark), None)
        if pitch is None:
            raise ValueError(f"Unsupported pitch mark: {pitch_mark}")

        # 解析音长和音强
        duration = "neutral"
        loudness = "neutral"

        if "_" in self.notation:
            parts = self.notation.split("_")
            duration = parts[1].split("^")[0] if len(parts) > 1 else "neutral"
        if "^" in self.notation:
            parts = self.notation.split("^")
            loudness = parts[1] if len(parts) > 1 else "neutral"

        # 创建PitchedPianyin实例
        return PitchedPianyin(quality=quality, pitch=pitch, duration=duration, loudness=loudness)

    @staticmethod
    def _get_yinyuan_code(notation: str) -> Optional[int]:
        """根据音元符号获取对应的代码"""
        code_mapping = {
            "i˥": 301, "i˦": 302, "i˩": 303,
            "u˥": 304, "u˦": 305, "u˩": 306,
            "ʏ˥": 307, "ʏ˦": 308, "ʏ˩": 309,
            "ᴀ˥": 310, "ᴀ˦": 311, "ᴀ˩": 312,
            "o˥": 313, "o˦": 314, "o˩": 315,
            "ᴇ˥": 316, "ᴇ˦": 317, "ᴇ˩": 318,
            "ʅ˥": 319, "ʅ˦": 320, "ʅ˩": 321,
            "ɚ˥": 322, "ɚ˦": 323, "ɚ˩": 324
        }
        return code_mapping.get(notation, None)

    @staticmethod
    def _get_base_notation_from_code(code: int) -> Optional[str]:
        """根据音元代码获取基础符号表示"""
        code_mapping = {
            301: "i˥", 302: "i˦", 303: "i˩",
            304: "u˥", 305: "u˦", 306: "u˩",
            307: "ʏ˥", 308: "ʏ˦", 309: "ʏ˩",
            310: "ᴀ˥", 311: "ᴀ˦", 312: "ᴀ˩",
            313: "o˥", 314: "o˦", 315: "o˩",
            316: "ᴇ˥", 317: "ᴇ˦", 318: "ᴇ˩",
            319: "ʅ˥", 320: "ʅ˦", 321: "ʅ˩",
            322: "ɚ˥", 323: "ɚ˦", 324: "ɚ˩"
        }
        return code_mapping.get(code, None)

    def __str__(self) -> str:
        """返回音元的字符串表示"""
        return f"PitchedYinyuan(code={self.code}, notation='{self.notation}')"

    def __repr__(self) -> str:
        """返回音元的正式表示，可用于eval"""
        return f"PitchedYinyuan(code={self.code}, notation='{self.notation}')"
