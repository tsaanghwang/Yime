"""
定义干音类
功能：该类用于分析干音的特征、成分和类型
要求：
1. 导入音节类对干音的定义：干音由韵母和与其联结的调段构成，即 Ganyin=Rest_Segment = Final+Tone
2. 定义一个干音分类工具类 GanyinCategorizer，根据韵母的类型把干音分成四个子类：
    - 单质干音（Single Quality Ganyin），由单质韵母与声调构成，例如 "ī", "ǒ", "-ī",  "èr", "ń", "ǹg"。
        - 单质韵母是只含有一种音质(或元音或鼻音的音质)的韵母。
    - 前长干音（Front Long Ganyin），由前长二合音质韵母与声调构成，例如 "āi", "ēi", "āo", "ōu", "ān", "ēn", "āng", "ēng"。
        - 前长韵母是由中低元音(a/o/e)的音质与高元音(i/u/ü)或鼻音(n/ng)的音质构成的二合音质韵母。
    - 后长干音（Back Long Ganyin），由后长二合音质韵母与声调构成，例如 "iā", "iē", "iō", "uō", "īn", "īng", "ǖn", "ǖng"。
        - 后长韵母是由高元音(i/u/ü)的音质与中低元音(a/o/e)或鼻音(n/ng)的音质构成的二合音质韵母。
    - 三质干音（Triple Quality Ganyin）由三合音质韵母与声调构成，, 例如 "iāo", "iōu", "uān", "uēn", "iāng", "uāng", "uēng"。
        - 三质韵母是由前面的高元音(i/u/ü)、中间的中低元音(a/o/e)和后面的高元音(i/u/ü)或鼻音(n/ng)的音质三种音质构成的韵母。

"""
from typing import Dict
import sys
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


class GanyinCategorizer:
    """
    干音分类工具类，干音根据韵母类型分类
    """
    # 特殊音节映射
    SPECIAL_SYLLABLES = {
        "ê1": "ê̄", "ê2": "ế", "ê3": "ê̌", "ê4": "ề", "ê5": "ê",
        "m1": "m̄", "m2": "ḿ", "m3": "m̌", "m4": "m̀", "m5": "m",
        "n1": "n̄", "n2": "ń", "n3": "ň", "n4": "ǹ", "n5": "n",
        "ng1": "n̄g", "ng2": "ńg", "ng3": "ňg", "ng4": "ǹg", "ng5": "ng",
    }
    # 创建反向映射：从调号标调到数字标调
    REVERSE_SPECIAL_SYLLABLES = {v: k for k, v in SPECIAL_SYLLABLES.items()}

    # 四类韵母定义（使用可变集合，支持动态添加）
    SINGLE_QUALITY_FINALS = {'i', 'u', 'ü', 'v', 'a', 'o', 'e', 'ê', '_i', 'er', 'm', 'n', 'ng'}
    FRONT_LONG_FINALS = {'ai', 'ei', 'ao', 'ou', 'an', 'en', 'ang', 'eng'}
    BACK_LONG_FINALS = {'ia', 'ua', 'ie', 'ue', 've', 'io', 'uo'}
    TRIPLE_QUALITY_FINALS = {'iao', 'iou', 'iu', 'uai', 'uei', 'ui', 'ian', 'uan', 'üan',
                             'van', 'iang', 'uang', 'in', 'uen', 'un', 'ün', 'ing', 'ueng', 'ong', 'iong'}

    @staticmethod
    def _is_special_syllable(syllable: str) -> bool:
        """判断是否为特殊音节（支持数字标调和调号标调）"""
        return (syllable in GanyinCategorizer.SPECIAL_SYLLABLES or
                syllable in GanyinCategorizer.REVERSE_SPECIAL_SYLLABLES)

    @staticmethod
    def categorize(ganyin: str) -> str:
        """
        干音根据韵母类型分类

        参数:
            ganyin: 干音字符串

        返回:
            干音类型字符串
        """
        if not ganyin:
            return "未知类型"

        # 提取韵母，去除声调标记
        final = GanyinCategorizer._remove_tone_from_ganyin(ganyin)

        # 使用类常量进行分类
        if final in GanyinCategorizer.SINGLE_QUALITY_FINALS:
            return "单质干音"
        elif final in GanyinCategorizer.FRONT_LONG_FINALS:
            return "前长干音"
        elif final in GanyinCategorizer.BACK_LONG_FINALS:
            return "后长干音"
        elif final in GanyinCategorizer.TRIPLE_QUALITY_FINALS:
            return "三质干音"
        else:
            return "未知类型"

    @staticmethod
    def _remove_tone_from_ganyin(ganyin: str) -> str:
        """
        从干音中提取韵母字符串，去除声调标记

        参数:
            ganyin: final with tone segment (e.g., "āi", "iā", "_i")

        返回:
            final: 韵母字符串
        """
        # 处理带占位符的韵母（如"_i"开头的）
        if ganyin.startswith('_'):
            prefix = '_'
            final = ganyin[1:]
        else:
            prefix = ''
            final = ganyin

        # 去除声调数字
        if final and final[-1].isdigit():
            final = final[:-1]

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

        return prefix + result

    @staticmethod
    def extract_final(pinyin: str) -> str:
        """从拼音中提取韵母部分

        参数:
            pinyin: 拼音字符串 (如 "zhang1" 或 "zhāng")

        返回:
            final: 韵母字符串
        """
        if not pinyin:
            return ""

        # 切分音节，获取干音部分
        _, ganyin = GanyinCategorizer.split_syllable(pinyin)

        # 提取韵母，去除声调标记
        final = GanyinCategorizer._remove_tone_from_ganyin(ganyin)

        return final

    @staticmethod
    def _add_final_to_category(final: str) -> bool:
        """
        将韵母动态添加到合适的分类中

        参数:
            final: 韵母字符串

        返回:
            是否成功添加韵母
        """
        if not final:
            return False

        # 检查是否已存在于任何分类中
        all_finals = (GanyinCategorizer.SINGLE_QUALITY_FINALS |
                      GanyinCategorizer.FRONT_LONG_FINALS |
                      GanyinCategorizer.BACK_LONG_FINALS |
                      GanyinCategorizer.TRIPLE_QUALITY_FINALS)

        if final in all_finals:
            return False  # 已存在，不需要添加

        # 根据韵母特征进行分类判断
        if GanyinCategorizer._should_be_single_quality(final):
            GanyinCategorizer.SINGLE_QUALITY_FINALS.add(final)
            return True
        elif GanyinCategorizer._should_be_front_long(final):
            GanyinCategorizer.FRONT_LONG_FINALS.add(final)
            return True
        elif GanyinCategorizer._should_be_back_long(final):
            GanyinCategorizer.BACK_LONG_FINALS.add(final)
            return True
        elif GanyinCategorizer._should_be_triple_quality(final):
            GanyinCategorizer.TRIPLE_QUALITY_FINALS.add(final)
            return True
        else:
            # 默认添加到单质干音类别
            GanyinCategorizer.SINGLE_QUALITY_FINALS.add(final)
            return True

    @staticmethod
    def _should_be_single_quality(final: str) -> bool:
        """判断是否应该归为单质干音"""
        # 去除下划线前缀进行判断
        pure_final = final[1:] if final.startswith('_') else final

        # 特殊韵母集合
        special_single_finals = {'ü', 'v', 'ê', 'er', 'm', 'n', 'ng'}

        # 仅限 _i 本身为单质干音
        if final == '_i':
            return True

        # 其他情况按原规则判断
        return (len(pure_final) == 1  # 仅限单字符
                or pure_final in special_single_finals)

    @staticmethod
    def _should_be_front_long(final: str) -> bool:
        """判断是否应该归为前长干音"""
        # 以 a, e, o 开头的复合韵母，或以 n, ng 结尾但不以 i, u, ü 开头
        if len(final) >= 2:
            if final[0] in {'a', 'e', 'o'} and len(final) == 2:
                return True
            if final.endswith(('n', 'ng')) and not final[0] in {'i', 'u', 'ü'}:
                return True
        return False

    @staticmethod
    def _should_be_back_long(final: str) -> bool:
        """判断是否应该归为后长干音"""
        # 以 i, u, ü 开头的复合韵母（但不是三质干音）
        if len(final) >= 2 and final[0] in {'i', 'u', 'ü'}:
            # 检查不是三质干音
            if not GanyinCategorizer._should_be_triple_quality(final):
                return True
        return False

    @staticmethod
    def _should_be_triple_quality(final: str) -> bool:
        """判断是否应该归为三质干音"""
        # 长度为3或4的复合韵母，通常包含三个音质成分
        if len(final) >= 3:
            # 典型的三质韵母模式
            triple_patterns = ['iao', 'iou', 'uan',
                               'uen', 'iang', 'uang', 'ueng']
            if final in triple_patterns:
                return True
            # 其他长复合韵母也可能是三质
            if len(final) >= 4:
                return True
        return False

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
            "单质韵母": GanyinCategorizer.SINGLE_QUALITY_FINALS,
            "前长韵母": GanyinCategorizer.FRONT_LONG_FINALS,
            "后长韵母": GanyinCategorizer.BACK_LONG_FINALS,
            "三质韵母": GanyinCategorizer.TRIPLE_QUALITY_FINALS
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
            "单质韵母": GanyinCategorizer.SINGLE_QUALITY_FINALS,
            "前长韵母": GanyinCategorizer.FRONT_LONG_FINALS,
            "后长韵母": GanyinCategorizer.BACK_LONG_FINALS,
            "三质韵母": GanyinCategorizer.TRIPLE_QUALITY_FINALS
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
        tongue_tip_initials = {'z', 'c', 's', 'zh', 'ch', 'sh', 'r'}

        if len(syllable) >= 2:
            initial_candidate = syllable[:2].lower()
            if initial_candidate in {'zh', 'ch', 'sh'}:
                # 处理舌尖音后接 "i" 的情况
                if len(syllable) > 2 and syllable[2] == 'i':
                    return initial_candidate, '_' + syllable[2:]
                return initial_candidate, syllable[2:]

        # 单字母声母 (z, c, s, r) - 检查后接 "i" 的情况
        if syllable[0] in {'z', 'c', 's', 'r'} and len(syllable) > 1 and syllable[1] == 'i':
            return syllable[0], '_' + syllable[1:]

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
    def __init__(self):
        # 修正输入文件路径
        base_dir = os.path.dirname(os.path.dirname(
            os.path.dirname(os.path.dirname(__file__))))
        self.input_path = os.path.join(
            base_dir, 'pinyin', 'hanzi_pinyin', 'pinyin_normalized.json')
        self.shouyin_path = os.path.join(
            os.path.dirname(__file__), 'shouyin.json')
        self.ganyin_path = os.path.join(
            os.path.dirname(__file__), 'ganyin.json')

        # 打印路径用于调试
        print(f"输入文件路径: {self.input_path}")
        print(f"首音输出路径: {self.shouyin_path}")
        print(f"干音输出路径: {self.ganyin_path}")

    def analyze_and_save(self):
        """分析拼音数据并保存分类后的结果"""
        try:
            # 检查输入文件是否存在
            if not os.path.exists(self.input_path):
                raise FileNotFoundError(f"输入文件不存在: {self.input_path}")

            # 读取并验证JSON数据
            with open(self.input_path, 'r', encoding='utf-8') as f:
                pinyin_data = json.load(f)

            if not isinstance(pinyin_data, dict):
                raise ValueError("输入JSON数据格式不正确，应为字典类型")

            if not pinyin_data:
                raise ValueError("输入JSON数据为空")

            # 生成首音数据
            shouyin_data = GanyinCategorizer.generate_shouyin_data(pinyin_data)
            if not shouyin_data:
                raise ValueError("生成的首音数据为空")

            # 生成干音数据并分类
            ganyin_data = self._generate_ganyin_data(pinyin_data)
            if not ganyin_data:
                raise ValueError("生成的干音数据为空")

            categorized_ganyin = self.categorize_ganyin_data(ganyin_data)

            # 转换为要求的输出格式
            output_shouyin = {"shouyin": dict(sorted(shouyin_data.items()))}
            output_ganyin = {"ganyin": categorized_ganyin}

            # 确保输出目录存在
            os.makedirs(os.path.dirname(self.shouyin_path), exist_ok=True)
            os.makedirs(os.path.dirname(self.ganyin_path), exist_ok=True)

            # 保存文件
            with open(self.shouyin_path, 'w', encoding='utf-8') as f:
                json.dump(output_shouyin, f, ensure_ascii=False, indent=2)

            with open(self.ganyin_path, 'w', encoding='utf-8') as f:
                json.dump(output_ganyin, f, ensure_ascii=False, indent=2)

            print("分析完成，结果已保存到:")
            print(f"- 首音数据: {self.shouyin_path}")
            print(f"- 干音数据: {self.ganyin_path}")
            return True

        except Exception as e:
            print(f"分析过程中出错: {str(e)}", file=sys.stderr)
            return False

    def categorize_ganyin_data(self, ganyin_data: Dict[str, str]) -> Dict[str, Dict[str, str]]:
        """
        按干音分类整理干音数据

        参数:
            ganyin_data: {数字标调干音: 调号标调干音}

        返回:
            分类后的干音数据 {分类名: {数字标调干音: 调号标调干音}}
        """
        categorized = {
            "single quality ganyin": {},
            "front long ganyin": {},
            "back long ganyin": {},
            "triple quality ganyin": {}
        }
        category_map = {
            "单质干音": "single quality ganyin",
            "前长干音": "front long ganyin",
            "后长干音": "back long ganyin",
            "三质干音": "triple quality ganyin"
        }

        for num_final, tone_final in ganyin_data.items():
            # 提取韵母仅用于分类，不影响存储的键值对
            final = GanyinCategorizer._remove_tone_from_ganyin(num_final)
            category_cn = GanyinCategorizer.categorize(final)
            category_en = category_map.get(
                category_cn, "single quality ganyin")
            categorized[category_en][num_final] = tone_final

        # 对每个分类中的条目按拼音排序
        for category in categorized:
            categorized[category] = dict(sorted(categorized[category].items()))

        return categorized

    def _generate_ganyin_data(self, pinyin_data: Dict[str, str]) -> Dict[str, str]:
        """生成干音数据

        参数:
            pinyin_data: {数字标调拼音: 调号标调拼音}
            # 生成干音数据
            # 输入: {数字标调拼音: 调号标调拼音}
            # 输出: {数字标调干音: 调号标调干音}
            ganyin_data = {}
            tongue_tip_initials = {'z', 'c', 's', 'zh', 'ch', 'sh', 'r'}

            for num_pinyin, tone_pinyin in pinyin_data.items():
                # 处理特殊音节
                if GanyinCategorizer._is_special_syllable(num_pinyin):
                ganyin_data[num_pinyin] = GanyinCategorizer.SPECIAL_SYLLABLES.get(num_pinyin, tone_pinyin)
                continue

        返回:
            {数字标调干音: 调号标调干音}
        """
        ganyin_data = {}
        tongue_tip_initials = {'z', 'c', 's', 'zh', 'ch', 'sh', 'r'}

        for num_pinyin, tone_pinyin in pinyin_data.items():
            # 处理特殊音节（不包括 "_i" 相关的）
            if GanyinCategorizer._is_special_syllable(num_pinyin):
                ganyin_data[num_pinyin] = GanyinCategorizer.SPECIAL_SYLLABLES.get(
                    num_pinyin, tone_pinyin)
                continue

            # 从数字标调拼音中提取干音部分
            initial, num_final = GanyinCategorizer.split_syllable(num_pinyin)
            # 从调号标调拼音中提取干音部分
            _, tone_final = GanyinCategorizer.split_syllable(tone_pinyin)

            # 处理舌尖音：当声母为 z, c, s, zh, ch, sh, r 且韵母为"i"时，添加占位符"_"
            if num_final and tone_final:
                if initial in tongue_tip_initials and num_final == 'i':
                    num_final = '_' + num_final
                    # 处理调号标调的情况
                    if tone_final[0] in {'i', 'ī', 'í', 'ǐ', 'ì'}:
                        tone_final = '_' + tone_final

                ganyin_data[num_final] = tone_final

        return ganyin_data


if __name__ == "__main__":
    print("=== 测试干音分类功能 ===")
    samples = ["ī", "āi", "iā", "iāo"]
    for final in samples:
        final = GanyinCategorizer._remove_tone_from_ganyin(final)
        category = GanyinCategorizer.categorize(final)
        print(f"干音对象 '{final}' -> 韵母类型: '{final}' -> 干音类型: {category}")

    print("\n=== 从干音中提取的四类干音的韵母 ===")
    all_finals = GanyinCategorizer.get_all_finals()
    for category, finals in all_finals.items():
        print(f"{category}: {sorted(finals)}")

    print("\n=== 开始分析和保存 ===")
    analyzer = GanyinAnalyzer()
    if not analyzer.analyze_and_save():
        print("分析失败，请检查错误信息")
