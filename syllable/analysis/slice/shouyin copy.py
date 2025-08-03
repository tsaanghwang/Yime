# Initial Sound Representation Module
# 首音表示模块
#
# This module provides a class to represent the initial sound in Chinese phonetics,
# supporting multiple representation methods including pinyin, phonetic, pianyin and yinyuan.
#
# 首音 (initial): 由声母和与声母联结的调段构成的音段
# 声母 (initial): 必选属性
# 首调: 与声母联结的调段, 可选属性, 默认值 None
#
# The initial sound is a syllable segment composed of the initial consonant and the tone segment connected to the initial consonant
# The initial consonant is a required attribute
# The tone of the initial sound (the tone segment connected to the initial consonant), named initial tone, is an optional attribute

from pianyin.pianyin import UnpitchedPianyin  # 修改了导入路径


class Initial(UnpitchedPianyin):
    """
    Represents the initial sound of a Chinese syllable.
    表示汉语音节的首音 (initial)

    Attributes:
        quality (str): The quality of the initial consonant (声母/initial)
        tone_segment (str|None): The tone segment using 5-level notation (0-5)
        representation (str): Representation method (pinyin/phonetic/pianyin/yinyuan)
        音高表示方式 (str): Tone display style ('number' or 'mark')
    """
    # 以下内容保持不变...
    TONE_SEGMENT_MARKS = {
        "5": "˥",  # 高平调
        "4": "˦",  # 次高平调
        "3": "˧",  # 中平调
        "2": "˨",  # 次低平调
        "1": "˩",  # 低平调
        "0": "꜌"   # 与清声母联结的调段
    }

    def __init__(self, consonant, tone_segment=None, representation='pinyin', 音高表示方式='number'):
        """
        Initialize an Initial instance.
        初始化首音实例

        Args:
            consonant (str): The initial consonant (声母/initial)
            tone_segment (str|None): The tone segment (0-5) or None for no tone segment (与清声母联结的调段/wu shoudiao)
            representation (str): Representation method (default 'pinyin')
            音高表示方式 (str): Tone display style ('number' or 'mark', default 'number')
        """
        super().__init__(quality=consonant)
        self.tone_segment = str(
            tone_segment) if tone_segment is not None else None
        self.representation = representation.lower()
        self.音高表示方式 = 音高表示方式.lower()

        self._validate_input()

    def _validate_input(self):
        """Validate the input parameters. 验证输入参数"""
        if not isinstance(self.quality, str) or not self.quality:
            raise ValueError("Consonant must be a non-empty string")

        if self.tone_segment is not None and self.tone_segment not in ["0", "1", "2", "3", "4", "5"]:
            raise ValueError("Tone segment must be between 0-5 or None")

        if self.representation not in ['pinyin', 'phonetic', 'pianyin', 'yinyuan']:
            raise ValueError("Invalid representation method")

        if self.音高表示方式 not in ['number', 'mark']:
            raise ValueError("Tone style must be 'number' or 'mark'")

    def _get_tone_mark(self):
        """Get tone mark for current tone segment. 获取当前调段的符号标调"""
        if self.tone_segment is None:
            return ""
        return self.TONE_SEGMENT_MARKS.get(self.tone_segment, "")

    def __repr__(self):
        """General string representation. 一般字符串表示"""
        return f"Initial(quality={self.quality!r}, tone_segment={self.tone_segment!r}, representation={self.representation!r}, 音高表示方式={self.音高表示方式!r})"

    def __str__(self):
        """简式字符串表示. 只包含必选项 consonant"""
        return f"{self.quality}"

    @classmethod
    def generate_from_consonant_table(cls, consonant_table, representation='pinyin', 音高表示方式='number'):
        """
        从声母表生成首音对象映射
        Args:
            consonant_table (list/dict): 声母列表或字典
            representation (str): 表示方法
            音高表示方式 (str): 音高表示方式
        Returns:
            dict: 声母到Shouyin对象的映射
        """
        if isinstance(consonant_table, list):
            return {consonant: cls(consonant, representation=representation, 音高表示方式=音高表示方式)
                    for consonant in consonant_table}
        elif isinstance(consonant_table, dict):
            # 处理嵌套字典结构，只使用键(拼音字母)作为声母
            return {k: cls(k, representation=representation, 音高表示方式=音高表示方式)
                    for k in consonant_table.keys()}
        else:
            raise ValueError("consonant_table 必须是列表或字典")

    def is_valid(self) -> bool:
        """检查首音对象是否有效"""
        return bool(self.quality) and (
            self.tone_segment is None or
            self.tone_segment in ["0", "1", "2", "3", "4", "5"]
        )
