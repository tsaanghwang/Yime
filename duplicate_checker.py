# 音元(Yinyuan)表示法
# 音元表示片音，是片音(Pianyin)的另一种符号化表示形式

from pianyin.pianyin import Pianyin
class Yinyuan:
    """音元(Yinyuan)类是片音类的另一种符号化表示形式"""
    def __init__(self, code: int = None, notation: str = ""):
        """
        初始化音元对象
        
        参数:
            code (int): 音元代码，默认为None
            notation (str): 音元符号表示，默认为空字符串
            
        异常:
            ValueError: 如果音元代码无效
        """
        self.notation = notation
        if code is not None and not isinstance(code, int):
            raise ValueError("Yinyuan code must be an integer")
        
        self.code = code

    def __str__(self) -> str:
        """返回音元的字符串表示"""
        return f"Yinyuan(code={self.code}, notation='{self.notation}')"
    
    def __repr__(self) -> str:
        """返回音元的正式表示，可用于eval"""
        return f"Yinyuan(code={self.code}, notation='{self.notation}')"
    
    @classmethod
    def from_pianyin(cls, pianyin: 'Pianyin') -> 'Yinyuan':
        """
        从片音对象创建音元对象
        
        参数:
            pianyin (Pianyin): 片音对象
            
        返回:
            Yinyuan: 转换后的音元对象
            
        异常:
            ValueError: 如果音质或音调无效
        """
        if not pianyin.is_valid():
            raise ValueError("Invalid Pianyin: missing required quality or pitch")
            
        #定义音质和音调的变元(变量)
        variable_of_quality = cls._define_variables_for_qualities(pianyin.quality)
        variable_of_pitch = cls._define_variables_for_pitches(pianyin.pitch)
        
        if not variable_of_quality or not variable_of_pitch:
            raise ValueError(f"Unsupported quality '{pianyin.quality}' or pitch '{pianyin.pitch}'")
            
        # 构建音元符号
        notation = f"{variable_of_quality}{variable_of_pitch}"
        if pianyin.duration != "neutral":
            notation += f"_{pianyin.duration}"
        if pianyin.loudness != "neutral":
            notation += f"^{pianyin.loudness}"
            
        # 获取音元代码
        base_notation = f"{variable_of_quality}{variable_of_pitch}"
        code = cls._get_yinyuan_code(base_notation)
        
        return cls(code=code, notation=notation)
    
    def to_pianyin(self) -> 'Pianyin':
        """
        将音元对象转换回片音对象
        
        返回:
            Pianyin: 转换后的片音对象
            
        异常:
            ValueError: 如果音元代码无效
        """
        if self.code is None:
            raise ValueError("Yinyuan code is required for conversion")
            
        from .pianyin import Pianyin
        
        # 从片音代码获取音质和音调
        base_notation = self._get_base_notation_from_code(self.code)
        if not base_notation:
            raise ValueError(f"Invalid Yinyuan code: {self.code}")
            
        quality = base_notation[0]
        pitch = base_notation[1:]
        
        # 解析音长和音强
        duration = "neutral"
        loudness = "neutral"
        
        if "_" in self.notation:
            parts = self.new_method()
            duration = parts[1].split("^")[0] if len(parts) > 1 else "neutral"
        if "^" in self.notation:
            parts = self.notation.split("^")
            loudness = parts[1] if len(parts) > 1 else "neutral"
            
        return Pianyin(quality=quality, pitch=pitch, duration=duration, loudness=loudness)

    def new_method(self):
        parts = self.notation.split("_")
        return parts
        
    @staticmethod
    def _define_variables_for_qualities(quality: str) -> str:
        """定义质元（质位），返回映射中的不同音质对应的质位（音质音位）"""
        quality_mapping = {
            "i": ["i", "ɪ"],
            "u": ["u", "ᴜ"],
            "ʏ": ["ʏ", "y"],
            "ᴀ": ["ᴀ", "a", "æ", "ɑ"],
            "o": ["o", "ɤ", "𐞑"],
            "ᴇ": ["ᴇ", "e", "ə", "ᵊ"],
            "ʅ": ["ʅ", "ɿ"],
            "ɚ": ["ɚ"],
            "m": ["m"],
            "n": ["n"],
            "ŋ": ["ŋ"]
        }
        
        for variable_of_quality, values in quality_mapping.items():
            if quality in values:
                return variable_of_quality
        return ""
        
    @staticmethod
    def _define_variables_for_pitches(pitch: str) -> str:
        """定义调元，返回映射中的不同音调对应的调元（音调音位）"""
        pitch_mapping = {
            "˥": ["˥"],
            "˦": ["˦"],
            "˩": ["˧", "˨", "˩"]
        }
        
        for variable_of_quality, values in pitch_mapping.items():
            if pitch in values:
                return variable_of_quality
        return ""
        
    @staticmethod
    def _get_yinyuan_code(notation: str) -> int:
        """根据音元符号获取对应的代码"""
        code_mapping = {
            "i˥": 23,
            "i˦": 2,
            "i˩": 3,
            "u˥": 21,
            "u˦": 2,
            "u˩": 3,
            "ʏ˥": 11,
            "ʏ˦": 2,
            "ʏ˩": 3,
            "ᴀ˥": 11,
            "ᴀ˦": 6,
            "ᴀ˩": 9,
            "o˥": 11,
            "o˦": 6,
            "o˩": 9,
            "ᴇ˥": 11,
            "ᴇ˦": 6,
            "ᴇ˩": 9,
            "ʅ˥": 5,
            "ʅ˦": 2,
            "ʅ˩": 3,
            "ɚ˥": 5,
            "ɚ˦": 2,
            "ɚ˩": 3,
            "m˥": 5,
            "m˦": 2,
            "m˩": 3,
            "n˥": 21,
            "n˦": 2,
            "n˩": 19,
            "ŋ˥": 21,
            "ŋ˦": 2,
            "ŋ˩": 19
        }
        return code_mapping.get(notation, None)
        
    @staticmethod
    def _get_base_notation_from_code(code: int) -> str:
        """根据音元代码获取基础符号表示"""
        code_mapping = {
            "i˥": 23,
            "i˦": 2,
            "i˩": 3,
            "u˥": 21,
            "u˦": 2,
            "u˩": 3,
            "ʏ˥": 11,
            "ʏ˦": 2,
            "ʏ˩": 3,
            "ᴀ˥": 11,
            "ᴀ˦": 6,
            "ᴀ˩": 9,
            "o˥": 11,
            "o˦": 6,
            "o˩": 9,
            "ᴇ˥": 11,
            "ᴇ˦": 6,
            "ᴇ˩": 9,
            "ʅ˥": 5,
            "ʅ˦": 2,
            "ʅ˩": 3,
            "ɚ˥": 5,
            "ɚ˦": 2,
            "ɚ˩": 3,
            "m˥": 5,
            "m˦": 2,
            "m˩": 3,
            "n˥": 21,
            "n˦": 2,
            "n˩": 19,
            "ŋ˥": 21,
            "ŋ˦": 2,
            "ŋ˩": 19
        }
        # 反转映射，从code找notation
        return next((k for k, v in code_mapping.items() if v == code), None)