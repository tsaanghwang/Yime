"""
定义干音类
功能：该类用于分析干音的特征、成分和类型
要求：
1. 导入syllable\\analysis\\slice\\Syllable.py对干音的定义：
干音：由韵母和与其联结的调段构成，即 Ganyin=Rest_Segment（Final+Tone）
2. 定义一个干音分类工具类 GanyinCategorizer，根据韵母的类型把干音分成四个子类：
    - 单质干音（Single Quality Ganyin），例如 "ī", "ǒ", "ń", "ǹg", "-ī",  "èr"
    - 前长干音（Front Long Ganyin），例如 "āi", "ēi", "āo", "ōu", "ān", "ēn", "āng", "ēng"
    - 后长干音（Back Long Ganyin），例如 "iā", "iē", "iō", "uō", "īn", "īng", "ǖn", "ǖng"
    - 三质干音（Triple Quality Ganyin）, 例如 "iāo", "iōu", "uān", "uēn", "iāng", "uāng", "uēng"
"""用于分析干音的特征、成分和类型
要求：
1. 导入syllable\analysis\slice\Syllable.py对干音的定义：
干音：由韵母和与其联结的调段构成，即 Ganyin=Rest_Segment（Final+Tone）
2. 定义一个干音分类工具类 GanyinCategorizer，根据韵母的类型把干音分成四个子类：
    - 单质干音（Single Quality Ganyin），例如 "ī", "ǒ", "ń", "ǹg", "-ī",  "èr"
    - 前长干音（Front Long Ganyin），例如 "āi", "ēi", "āo", "ōu", "ān", "ēn", "āng", "ēng"
    - 后长干音（Back Loif __name__ == "__if __name__ ==if __name__ == "__main__":
    print("=== 开始测试韵母分类 ===")
    # 保留原有示例用法
    samples = ["ī", "āi", "iā", "iāo"]
    for final in samples:
        normalized = GanyinCategorizer._normalize_final(final)
        category = GanyinCategorizer.categorize(final)
        print(f"韵母 '{final}' -> 标准化: '{normalized}' -> 分类: {category}")

    print("=== 开始分析和保存 ===")
    # 新增分析执行
    analyzer = GanyinCategorizer.GanyinAnalyzer()
    if analyzer.analyze_and_save():
        print("分析完成，结果已保存到:")
        print(f"- 首音数据: {analyzer.shouyin_path}")
        print(f"- 干音数据: {analyzer.ganyin_path}")
    else:
        print("分析失败，请检查错误信息")  # 保留原有示例用法
    samples = ["ī", "āi", "iā", "iāo"]
    for final in samples:
        normalized = GanyinCategorizer._normalize_final(final)
        category = GanyinCategorizer.categorize(final)
        print(f"韵母 '{final}' -> 标准化: '{normalized}' -> 分类: {category}")

    # 新增分析执行
    analyzer = GanyinCategorizer.GanyinAnalyzer()
    if analyzer.analyze_and_save():
        print("分析完成，结果已保存到:")
        print(f"- 首音数据: {analyzer.shouyin_path}")
        print(f"- 干音数据: {analyzer.ganyin_path}")
    else:
        print("分析失败，请检查错误信息")保留原有示例用法
    samples = ["ī", "āi", "iā", "iāo"]
    for final in samples:
        normalized = GanyinCategorizer._normalize_final(final)
        category = GanyinCategorizer.categorize(final)
        print(f"韵母 '{final}' -> 标准化: '{normalized}' -> 分类: {category}")
        # 调试信息
        if category == "未知类型":
            print(f"  调试: '{normalized}' in SINGLE_QUALITY_FINALS = {'i' in GanyinCategorizer.SINGLE_QUALITY_FINALS}")

    # 新增分析执行
    analyzer = GanyinCategorizer.GanyinAnalyzer()
    if analyzer.analyze_and_save():
        print("分析完成，结果已保存到:")
        print(f"- 首音数据: {analyzer.shouyin_path}")
        print(f"- 干音数据: {analyzer.ganyin_path}")
    else:
        print("分析失败，请检查错误信息")iā", "iē", "iō", "uō", "īn", "īng", "ǖn", "ǖng"
    - 三质干音（Triple Quality Ganyin）, 例如 "iāo", "iōu", "uān", "uēn", "iāng", "uāng", "uēng"
"""
import json
import os
from collections import defaultdict
from typing import Dict, Tuple

try:
    from .Syllable import Syllable  # When imported as part of a package
except ImportError:
    from Syllable import Syllable  # When run directly as a script


class Ganyin:
    """
    干音类，表示由韵母和与其联结的调段构成的音段
    """

    def __init__(self, final: str, tone_segment: str = None, tone: str = None):
        """
        初始化干音对象

        参数:
            final: 韵母部分
            tone_segment: 与韵母联结的调段
            tone: 声调
        """
        self.final = final
        self.tone_segment = tone_segment
        self.tone = tone

    @classmethod
    def from_syllable(cls, syllable: Syllable):
        """
        从Syllable对象创建Ganyin对象

        参数:
            syllable: Syllable对象

        返回:
            Ganyin对象
        """
        if not isinstance(syllable, Syllable):
            raise TypeError("输入必须是Syllable对象")

        return cls(
            final=syllable.final,
            tone_segment=syllable.final_tone_segment,
            tone=syllable.tone
        )

    def __str__(self):
        return f"Ganyin(final={self.final}, tone_segment={self.tone_segment}, tone={self.tone})"

    def __repr__(self):
        return self.__str__()

    def _generate_ganyin_data(self, pinyin_data: Dict[str, str]) -> Dict[str, str]:
        """生成干音数据(切除首音后的剩余部分)

        参数:
            pinyin_data: 拼音数据字典 {数字标调拼音: 调号标调拼音}

        返回:
            干音数据字典 {数字标调干音: 调号标调干音}
        """
        ganyin_data = {}

        for num_pinyin, tone_pinyin in pinyin_data.items():
            # 切分音节，获取韵母部分
            _, final_with_tone = GanyinCategorizer.split_syllable(num_pinyin)

            # 特殊处理特殊音节
            if GanyinCategorizer._is_special_syllable(num_pinyin):
                final_with_tone = GanyinCategorizer.SPECIAL_SYLLABLES.get(
                    num_pinyin, final_with_tone)

            # 存储干音数据
            ganyin_data[final_with_tone] = final_with_tone

        return ganyin_data


class GanyinCategorizer:
    """
    干音分类工具类，根据韵母类型将干音分类
    """
    # 特殊音节映射
    SPECIAL_SYLLABLES = {
        "ê1": "ê̄", "ê2": "ế", "ê3": "ê̌", "ê4": "ề", "ê5": "ê",
        "m1": "m̄", "m2": "ḿ", "m3": "m̌", "m4": "m̀", "m5": "m",
        "n1": "n̄", "n2": "ń", "n3": "ň", "n4": "ǹ", "n5": "n",
        "ng1": "n̄g", "ng2": "ńg", "ng3": "ňg", "ng4": "ǹg", "ng5": "ng"
    }
    
    # 创建反向映射：从调号标调到数字标调
    REVERSE_SPECIAL_SYLLABLES = {v: k for k, v in SPECIAL_SYLLABLES.items()}
    
    # 四类韵母定义
    SINGLE_QUALITY_FINALS = {'i', 'u', 'ü', 'a', 'o', 'e', 'er', 'n', 'ng', 'm', 'ê'}
    FRONT_LONG_FINALS = {'ai', 'ei', 'ao', 'ou', 'an', 'en', 'ang', 'eng'}
    BACK_LONG_FINALS = {'ia', 'ie', 'io', 'uo', 'in', 'ing', 'ün', 'üng'}
    TRIPLE_QUALITY_FINALS = {'iao', 'iou', 'uan', 'uen', 'iang', 'uang', 'ueng'}

    @staticmethod
    def _is_special_syllable(syllable: str) -> bool:
        """判断是否为特殊音节（支持数字标调和调号标调）"""
        return (syllable in GanyinCategorizer.SPECIAL_SYLLABLES or 
                syllable in GanyinCategorizer.REVERSE_SPECIAL_SYLLABLES)

    @staticmethod
    def categorize(final: str) -> str:
        """
        根据韵母类型分类干音

        参数:
            final: 韵母字符串

        返回:
            干音类型字符串
        """
        if not final:
            return "未知类型"

        # 标准化处理，去除声调标记
        normalized = GanyinCategorizer._normalize_final(final)

        # 使用类常量进行分类
        if normalized in GanyinCategorizer.SINGLE_QUALITY_FINALS:
            return "单质干音"
        elif normalized in GanyinCategorizer.FRONT_LONG_FINALS:
            return "前长干音"
        elif normalized in GanyinCategorizer.BACK_LONG_FINALS:
            return "后长干音"
        elif normalized in GanyinCategorizer.TRIPLE_QUALITY_FINALS:
            return "三质干音"
        else:
            return "未知类型"

    @staticmethod
    def _normalize_final(final: str) -> str:
        """
        标准化韵母字符串，去除声调标记

        参数:
            final: 原始韵母字符串

        返回:
            标准化后的韵母字符串
        """
        # 去除声调数字
        if final and final[-1].isdigit():
            return final[:-1]
        
        # 声调符号到基本字符的映射
        tone_mapping = {
            'ā': 'a', 'á': 'a', 'ǎ': 'a', 'à': 'a',
            'ē': 'e', 'é': 'e', 'ě': 'e', 'è': 'e',
            'ī': 'i', 'í': 'i', 'ǐ': 'i', 'ì': 'i',
            'ō': 'o', 'ó': 'o', 'ǒ': 'o', 'ò': 'o',
            'ū': 'u', 'ú': 'u', 'ǔ': 'u', 'ù': 'u',
            'ǖ': 'ü', 'ǘ': 'ü', 'ǚ': 'ü', 'ǜ': 'ü',
            'ń': 'n', 'ň': 'n', 'ǹ': 'n', 'n̄': 'n',
            'ḿ': 'm', 'm̌': 'm', 'm̀': 'm', 'm̄': 'm',
            'ế': 'ê', 'ê̌': 'ê', 'ề': 'ê', 'ê̄': 'ê'
        }
        
        # 转换带调号的字符
        result = ''
        for char in final:
            result += tone_mapping.get(char, char)
        
        return result

    @staticmethod
    def get_all_categories() -> Tuple[str, str, str, str]:
        """
        获取所有干音分类类型

        返回:
            包含所有分类类型的元组
        """
        return ("单质干音", "前长干音", "后长干音", "三质干音")

    @staticmethod
    def get_finals_by_category(category: str) -> set:
        """
        根据分类获取对应的韵母集合

        参数:
            category: 分类名称

        返回:
            对应分类的韵母集合
        """
        category_mapping = {
            "单质干音": GanyinCategorizer.SINGLE_QUALITY_FINALS,
            "前长干音": GanyinCategorizer.FRONT_LONG_FINALS,
            "后长干音": GanyinCategorizer.BACK_LONG_FINALS,
            "三质干音": GanyinCategorizer.TRIPLE_QUALITY_FINALS
        }
        return category_mapping.get(category, set())

    @staticmethod
    def get_all_finals() -> Dict[str, set]:
        """
        获取所有韵母分类数据

        返回:
            包含所有分类及其韵母的字典
        """
        return {
            "单质干音": GanyinCategorizer.SINGLE_QUALITY_FINALS,
            "前长干音": GanyinCategorizer.FRONT_LONG_FINALS,
            "后长干音": GanyinCategorizer.BACK_LONG_FINALS,
            "三质干音": GanyinCategorizer.TRIPLE_QUALITY_FINALS
        }

    @staticmethod
    def split_syllable(syllable: str) -> Tuple[str, str]:
        """切分音节为首音和干音部分

        参数:
            syllable: 拼音字符串 (如 "zhang1" 或 "zhāng")
        返回:
            元组 (首音部分, 干音部分)
        """
        if not syllable:
            return "", ""

        # 处理特殊音节（数字标调形式）
        if syllable in GanyinCategorizer.SPECIAL_SYLLABLES:
            return "'", GanyinCategorizer.SPECIAL_SYLLABLES[syllable]
            
        # 处理特殊音节（调号标调形式）
        if syllable in GanyinCategorizer.REVERSE_SPECIAL_SYLLABLES:
            return "'", syllable

        # 零声母处理 (适用于数字标调和调号标调)
        if syllable[0] in {'a', 'o', 'e', 'ê', 'ā', 'ō', 'ē', 'ế', 'à', 'ò', 'è', 'ǎ', 'ǒ', 'ě', 'á', 'ó', 'é'}:
            return "'", syllable

        # 双字母声母 (zh, ch, sh) - 检查调号标调情况
        if len(syllable) >= 2:
            initial_candidate = syllable[:2].lower()
            if initial_candidate in {'zh', 'ch', 'sh'}:
                return initial_candidate, syllable[2:]

        # 默认处理：第一个字母作为声母
        return syllable[0], syllable[1:] if len(syllable) > 1 else ""

    @staticmethod
    def generate_shouyin_data(pinyin_data: Dict[str, str]) -> Dict[str, str]:
        """生成首音数据字典

        参数:
            pinyin_data: 拼音数据字典 {数字标调拼音: 调号标调拼音}

        返回:
            首音数据字典 {"首音": "首音"}
        """
        shouyin_data = {}

        for num_pinyin, tone_pinyin in pinyin_data.items():
            # 从调号标调拼音中切分首音
            initial, _ = GanyinCategorizer.split_syllable(tone_pinyin)

            # 存储首音数据
            if initial not in shouyin_data:
                shouyin_data[initial] = initial

        return shouyin_data

    class GanyinAnalyzer:
        """干音分析器，用于处理文件输入输出和批量分析"""

        def __init__(self):
            self.input_path = os.path.normpath(os.path.join(
                os.path.dirname(__file__),
                '..', '..', '..', 'pinyin', 'hanzi_pinyin', 'pinyin_normalized.json'
            ))
            self.shouyin_path = os.path.join(
                os.path.dirname(__file__), 'shouyin.json'
            )
            self.ganyin_path = os.path.join(
                os.path.dirname(__file__), 'ganyin.json'
            )

        def _generate_ganyin_data(self, pinyin_data: Dict[str, str]) -> Dict[str, str]:
            """生成干音数据(切除首音后的剩余部分)

            参数:
                pinyin_data: 拼音数据字典 {数字标调拼音: 调号标调拼音}

            返回:
                干音数据字典 {数字标调干音: 调号标调干音}
            """
            ganyin_data = {}

            for num_pinyin, tone_pinyin in pinyin_data.items():
                # 切分数字标调拼音，获取干音部分
                _, num_final = GanyinCategorizer.split_syllable(num_pinyin)

                # 切分调号标调拼音，获取干音部分
                _, tone_final = GanyinCategorizer.split_syllable(tone_pinyin)

                # 特殊处理特殊音节
                if GanyinCategorizer._is_special_syllable(num_pinyin):
                    # 保持数字标调形式作为键
                    num_final = num_pinyin  # 特殊音节本身就是干音
                    tone_final = GanyinCategorizer.SPECIAL_SYLLABLES.get(
                        num_pinyin, tone_final)

                # 存储干音数据 - 数字标调干音作键，调号标调干音作值
                ganyin_data[num_final] = tone_final

            return ganyin_data

        def analyze_and_save(self):
            """分析拼音数据并保存结果"""
            try:
                with open(self.input_path, 'r', encoding='utf-8') as f:
                    pinyin_data = json.load(f)

                # 生成首音数据，使用静态方法确保一致性
                shouyin_data = GanyinCategorizer.generate_shouyin_data(pinyin_data)

                # 生成干音数据
                ganyin_data = self._generate_ganyin_data(pinyin_data)

                # 转换为要求的输出格式
                output_shouyin = {"shouyin": dict(
                    sorted(shouyin_data.items()))}
                output_ganyin = {"ganyin": dict(sorted(ganyin_data.items()))}

                # 保存文件
                with open(self.shouyin_path, 'w', encoding='utf-8') as f:
                    json.dump(output_shouyin, f, ensure_ascii=False, indent=2)

                with open(self.ganyin_path, 'w', encoding='utf-8') as f:
                    json.dump(output_ganyin, f, ensure_ascii=False, indent=2)

                return True

            except Exception as e:
                print(f"分析过程中出错: {e}")
                return False


if __name__ == "__main__":
    # 保留原有示例用法
    samples = ["ī", "āi", "iā", "iāo"]
    for final in samples:
        category = GanyinCategorizer.categorize(final)
        print(f"韵母 '{final}' 的分类是: {category}")

    # 新增分析执行
    analyzer = GanyinCategorizer.GanyinAnalyzer()
    if analyzer.analyze_and_save():
        print("分析完成，结果已保存到:")
        print(f"- 首音数据: {analyzer.shouyin_path}")
        print(f"- 干音数据: {analyzer.ganyin_path}")
    else:
        print("分析失败，请检查错误信息")
