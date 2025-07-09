# 乐音类音元表示法
# 乐音类音元是乐音类片音的另一种符号化表示形式

from typing import Optional
from tools.pitched_pianyin import Yueyin


class PitchedYinyuan(Yueyin):
    """乐音类音元，继承自Yueyin类，表示乐音类片音的音元形式"""

    def __init__(self, code: Optional[int] = None, notation: str = "", **kwargs):
        """
        初始化乐音类音元对象

        参数:
            code (int): 音元代码，默认为None
            notation (str): 音元符号表示，默认为空字符串
            **kwargs: 传递给父类的其他参数
        """
        self.code = code
        self.notation = notation
        super().__init__(quality="", tone_segment="", representation="yinyuan", **kwargs)

    @classmethod
    def from_pianyin(cls, pianyin: Yueyin) -> 'PitchedYinyuan':
        """
        从乐音类片音创建音元对象

        参数:
            pianyin (Yueyin): 乐音类片音对象

        返回:
            PitchedYinyuan: 转换后的音元对象
        """
        if not pianyin.is_valid():
            raise ValueError(
                "Invalid Yueyin: missing required quality or pitch")

        # 构建基本符号
        notation = f"{pianyin.quality}{pianyin.TONE_SEGMENT_MARKS.get(pianyin.pitch, '')}"

        # 获取音元代码
        base_notation = f"{pianyin.quality}{pianyin.TONE_SEGMENT_MARKS.get(pianyin.pitch, '')}"
        code = cls._get_yinyuan_code(base_notation)

        # 创建实例并定义属性
        instance = cls(code=code, notation=notation)
        instance.quality = pianyin.quality
        instance.pitch = pianyin.pitch
        instance.duration = pianyin.duration
        instance.loudness = pianyin.loudness

        return instance

    def to_pianyin(self) -> Yueyin:
        """
        将音元对象转换回片音对象

        返回:
            Yueyin: 转换后的片音对象
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

        # 创建Yueyin实例
        yueyin = Yueyin(quality=quality, tone_segment=pitch,
                        representation="pianyin")
        yueyin.duration = duration
        yueyin.loudness = loudness

        return yueyin

    @staticmethod
    def _get_yinyuan_code(notation: str) -> Optional[int]:
        """
        根据音元符号获取对应的代码
        这里使用与Yinyuan类相似的编码方式，但代码范围不同(300-399)
        """
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
        """
        根据音元代码获取基础符号表示
        """
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

    def _yinyuan_representation(self):
        """重写父类的音元表示方法"""
        return self.notation if self.notation else super()._yinyuan_representation()
