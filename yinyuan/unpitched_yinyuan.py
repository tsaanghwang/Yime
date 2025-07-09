# yinyuan/unpitched_yinyuan.py
from pianyin.pianyin import UnpitchedPianyin
from yinyuan.yinyuan import Yinyuan
from typing import Optional


class UnpitchedYinyuan(Yinyuan):
    """噪音类音元，继承自Yinyuan类"""

    def __init__(self, code: Optional[int] = None, notation: str = "",
                 config_path='yinyuan/variables_of_pitch_and_quality.json'):
        """
        初始化噪音类音元对象

        参数:
            code (int): 音元代码，默认为None
            notation (str): 音元符号表示，默认为空字符串
            config_path (str): 配置文件路径
        """
        super().__init__(config_path=config_path)
        self.code = code
        self.notation = notation

    @classmethod
    def from_pianyin(cls, pianyin: UnpitchedPianyin) -> 'UnpitchedYinyuan':
        """
        从噪音类片音创建音元对象

        参数:
            pianyin (UnpitchedPianyin): 噪音类片音对象

        返回:
            UnpitchedYinyuan: 转换后的音元对象
        """
        # 构建基本符号
        notation = pianyin.quality

        # 如果是浊辅音且有音调，添加音调符号
        if hasattr(pianyin, 'pitch') and pianyin.pitch is not None:
            variable_of_pitch = cls._set_unit_for_tone(pianyin.pitch)
            if variable_of_pitch:
                notation += variable_of_pitch

        # 添加音长和音强
        if pianyin.duration:
            notation += f"_{pianyin.duration}"
        if pianyin.loudness:
            notation += f"^{pianyin.loudness}"

        # 获取音元代码
        base_notation = pianyin.quality
        if hasattr(pianyin, 'pitch') and pianyin.pitch is not None:
            variable_of_pitch = cls._set_unit_for_tone(pianyin.pitch)
            if variable_of_pitch:
                base_notation += variable_of_pitch

        code = cls._get_yinyuan_code(base_notation)

        return cls(code=code, notation=notation)

    def to_pianyin(self) -> UnpitchedPianyin:

        """
        将音元对象转换回片音对象

        Returns:
            UnpitchedPianyin: 转换后的片音对象
        """

        # 解析基本音质
        quality = self.notation.split("_")[0].split("^")[0]

        # 检查是否有音调符号
        pitch = None
        if len(quality) > 1 and quality[-1] in ["˥", "˦", "˩"]:
            pitch = quality[-1]
            quality = quality[:-1]

        # 解析音长和音强
        duration = ""
        loudness = ""

        if "_" in self.notation:
            parts = self.notation.split("_")
            duration_part = parts[1].split(
                "^")[0] if len(parts) > 1 else "neutral"
            duration = duration_part

        if "^" in self.notation:
            parts = self.notation.split("^")
            loudness = parts[1] if len(parts) > 1 else "neutral"

        # 根据是否有音调决定返回哪种片音
        if pitch is not None:
            return UnpitchedPianyin(quality=quality, duration=duration, loudness=loudness)
        else:
            return UnpitchedPianyin(quality=quality, duration=duration, loudness=loudness)

    @staticmethod
    def _set_unit_for_tone(pitch: str) -> str:
        """定义调元，返回映射中的不同音调对应的调元"""
        pitch_levels = {
            "˥": "5", "˦": "4", "˧": "3", "˨": "2", "˩": "1"
        }

        # 处理输入是键的情况
        if pitch in pitch_levels:
            if pitch == "˥":
                return "˥"
            elif pitch == "˦":
                return "˦"
            else:  # "˧", "˨", "˩"
                return "˩"

        # 处理输入是值的情况
        reverse_pitch_levels = {v: k for k, v in pitch_levels.items()}
        if pitch in reverse_pitch_levels:
            if pitch == "5":
                return "5"
            elif pitch == "4":
                return "4"
            else:  # "3", "2", "1"
                return "1"

        # 其他情况返回空字符串
        return ""

    @staticmethod
    def _get_yinyuan_code(notation: str) -> Optional[int]:
        """根据音元符号获取对应的代码（混合模式）"""
        # 基础映射字典（核心音素）
        base_code_mapping = {
            "p": 101, "t": 102, "k": 103, "ʔ": 104,
            "f": 105, "s": 106, "ʂ": 107, "ɕ": 108,
            "x": 109, "h": 110,
            "m˥": 201, "m˦": 202, "m˩": 203,
            "n˥": 204, "n˦": 205, "n˩": 206,
            "ŋ˥": 207, "ŋ˦": 208, "ŋ˩": 209
        }

        # 先尝试从基础字典获取
        if notation in base_code_mapping:
            return base_code_mapping[notation]

        # 自动生成规则（处理新音素）
        if len(notation) == 1:  # 清辅音
            return 100 + ord(notation[0])
        elif len(notation) > 1:
            # 例如带有音调的浊辅音，简单处理：取前两个字符的Unicode和
            return 200 + sum(ord(c) for c in notation[:2])
