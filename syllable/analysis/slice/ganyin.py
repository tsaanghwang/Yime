"""
定义干音类
功能：该类用于分析干音的特征、成分和类型
要求：
1. 导入syllable\analysis\slice\Syllable.py对干音的定义：
干音：由韵母和与其联结的调段构成，即 Gainyin=Rest_Segment（Final+Tone）
2. 定义一个干音分类工具类 GanyinCategorizer：
- 根据韵母的类型把干音分成四类：
    - 单质干音（Single Quality Ganyin），例如 "ī", "ǒ", "ń", "ǹg", "-ī",  "èr"
- 前长干音（Front Long Ganyin），例如 "āi", "ēi", "āo", "ōu", "ān", "ēn", "āng", "ēng"
    - 后长干音（Back Long Ganyin），例如 "iā", "iē", "iō", "uō", "īn", "īng", "ǖn", "ǖng"
    - 三质干音（Triple Quality Ganyin）, 例如 "iāo", "iōu", "uān", "uēn", "iāng", "uāng", "uēng"    """


class GanyinAnalyzer:
    """干音分析器类"""

    def __init__(self):
        pass

    def analyze(self, ganyin):
        """分析干音特征"""
        return {
            "components": ganyin.components,
            "tone": ganyin.tone
        }
