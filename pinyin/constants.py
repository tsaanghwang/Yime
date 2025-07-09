# pinyin/constants.py
from dataclasses import dataclass
from typing import List


@dataclass
class YunmuConstants:
    """韵母转换常量定义"""
    I_APICAL: str = "-i"
    I_APICAL_REPLACEMENT: str = "ir"

    O_CODA: str = "o"
    U_CODA: str = "u"
    AO_FINAL: str = "ao"
    IAO_FINAL: str = "iao"

    Y_NEAR_ROUNDED: str = "ü"       # "ü" 近似圆唇元音[ʏ]
    YE: str = Y_NEAR_ROUNDED + "e"     # "üe"
    YAN: str = Y_NEAR_ROUNDED + "an"   # "üan"
    YN: str = Y_NEAR_ROUNDED + "n"     # "ün"
    Y_REPLACEMENT: str = "v"

    O_ROUNDED: str = "o"
    O_UNROUNDED: str = "e"

    E_CIRCUMFLEX: str = "ê"
    E_FRONT: str = "e"

    N_RIME: str = "n"        # 特指分布在"in"和"ün"中的n, 是韵基en在e弱化或省略后的形式
    EN_RIME: str = "en"
    IN_FINAL: str = "in"
    YN_FINAL: str = YN      # "ün"

    ENG_FINAL: str = "eng"
    ING_FINAL: str = "ing"
    UENG_FINAL: str = "ueng"
    UNG_FINAL: str = "ong"      # ong[ᴜ𐞑ŋ]
    YNG_FINAL: str = "iong"     # iong[y𐞑ŋ]

    FINAL_ONG: str = "ong"      # eng[ɤŋ]
    FINAL_IONG: str = "iong"        # ing[i𐞑ŋ]
    FINAL_UONG: str = "uong"        # ueng[uɤŋ], ong[ᴜ𐞑ŋ]
    FINAL_YONG: str = "vong"        # iong[y𐞑ŋ]

    @property
    def REQUIRED_FINALS(self) -> List[str]:
        """必需包含的所有韵母"""
        return [
            "i", "u", self.Y_NEAR_ROUNDED, "a", self.O_ROUNDED, self.O_UNROUNDED, self.E_CIRCUMFLEX,
            self.I_APICAL, "er", "m", "n", "ng", "ia", "ua", "io", "uo", "ie", self.YE,
            "ai", "ei", self.AO_FINAL, "ou", "an", "en", "ang", self.ENG_FINAL, self.IAO_FINAL,
            "iou", "uai", "uei", "ian", "uan", self.YAN, self.IN_FINAL, "uen", self.YN,
            "iang", "uang", self.ING_FINAL, self.UENG_FINAL, self.UNG_FINAL, self.YNG_FINAL
        ]

    @classmethod
    def get_replacement_table(cls) -> dict:
        """获取批量替换转换表"""
        return str.maketrans({
            cls.Y_NEAR_ROUNDED: cls.Y_REPLACEMENT,
            cls.O_CODA: cls.U_CODA,
            cls.O_UNROUNDED: cls.O_ROUNDED,
            cls.N_RIME: cls.EN_RIME,
            "v": "v"  # 保持v不变，只替换后面的n
        })


class YunmuConverter:
    def __init__(self):
        self.stats = {
            "total_conversions": 0,
            "successful_conversions": 0,
            "failed_conversions": 0,
            "success_rate": 0.0,
            "plugin_stats": {},
            "rule_stats": {}
        }

    def convert(self, input_dict):
        if not isinstance(input_dict, dict):
            raise ValueError("Input must be a dictionary")
        
        result = {}
        for key, value in input_dict.items():
            if not isinstance(value, str):
                raise ValueError("Dictionary values must be strings")
                
            # Implement your conversion rules here
            if key == "-i":
                result[key] = "ir"
            elif key == "ao":
                result[key] = "au"
            elif key == "iong":
                result[key] = "vong"
            elif key == "ing":
                result[key] = "iong"
            elif key == "e":
                result[key] = "o"
            elif key == "eng":
                result[key] = "ong"
            elif key == "in":
                result[key] = "ien"
            elif key == "ün":
                result[key] = "üen"
            elif key == "ueng":
                result[key] = "uong"
            elif key == "ong":
                result[key] = "uong"
            elif key == "ü":
                result[key] = "v"
            elif key == "ê":
                result["e"] = key
            else:
                result[key] = key

            self.stats["total_conversions"] += 1
            self.stats["successful_conversions"] += 1
            
        self.stats["success_rate"] = (self.stats["successful_conversions"] / self.stats["total_conversions"]) * 100
        return result

    def get_stats(self):
        return self.stats