"""
干音分类工具类
功能：根据韵母类型将干音分为四类（单质、前长、后长、三质）
"""
from ganyin import Ganyin  # 改为相对导入
from typing import Dict, Tuple, Set


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
    SINGLE_QUALITY_FINALS = {'_i', 'a', 'e', 'er', 'i', 'm', 'n', 'ng', 'o', 'u', 'v', 'ê', 'ü'}
    FRONT_LONG_FINALS = {'ai', 'an', 'ang', 'ao', 'ei', 'en', 'eng', 'ou'}
    BACK_LONG_FINALS = {'ia', 'ie', 'io', 'ua', 'ue', 'uo', 've', 'üe'}
    TRIPLE_QUALITY_FINALS = {'ian', 'iang', 'iao', 'in', 'ing', 'iong', 'iou', 'iu', 'ong', 'uai', 'uan', 'uang', 'uei', 'uen', 'ueng', 'ui', 'un', 'van', 'vn', 'üan', 'ün'}

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
            pinyin: 拼音字符串

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
            syllable: 拼音字符串
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

        # 处理 ju, qu, xu, yu 的情况
        if len(syllable) >= 2 and syllable[0].lower() in {'j', 'q', 'x', 'y'} and syllable[1].lower() == 'u':
            initial = syllable[0]
            # 将干音中的 u 改为 ü
            final = 'ü' + syllable[2:] if len(syllable) > 2 else 'ü'
            return initial, final

        # 默认处理：第一个字母作为声母
        return syllable[0], syllable[1:] if len(syllable) > 1 else ""

    @staticmethod
    def generate_shouyin_data(pinyin_data: Dict[str, str]) -> Dict[str, str]:
        """生成首音数据字典

        参数:
            pinyin_data: 拼音数据字典 {数字标调拼音: 调号标调拼音}

        返回:
            首音数据字典 {"首音": "首音"}，按预定义顺序排序
        """
        # 预定义的首音顺序
        initial_order = [
            'b', 'p', 'f', 'm',
            'd', 't', 'l', 'n',
            'g', 'k', 'h',
            'z', 'c', 's',
            'zh', 'ch', 'sh', 'r',
            'j', 'q', 'x'
        ]

        shouyin_data = {}
        ordered_shouyin_data = {}

        for num_pinyin, tone_pinyin in pinyin_data.items():
            # 从调号标调拼音中切分首音
            initial, _ = GanyinCategorizer.split_syllable(tone_pinyin)

            # 存储首音数据
            if initial not in shouyin_data:
                shouyin_data[initial] = initial

        # 按照预定义顺序排序
        for initial in initial_order:
            if initial in shouyin_data:
                ordered_shouyin_data[initial] = shouyin_data[initial]

        # 添加可能遗漏的首音（如零声母"'")
        for initial in shouyin_data:
            if initial not in ordered_shouyin_data:
                ordered_shouyin_data[initial] = shouyin_data[initial]

        return ordered_shouyin_data

    @staticmethod
    def sort_finals_by_category(finals: Dict[str, set]) -> Dict[str, list]:
        """按类别对韵母进行排序

        参数:
            finals: 包含各类韵母的字典，格式为 {"分类名": set(韵母)}

        返回:
            排序后的韵母字典 {"分类名": [排序后的韵母列表]}
        """
        sorted_finals = {}

        # 单质韵母排序规则
        if "单质韵母" in finals:
            priority_order = ['i', 'u', 'ü', 'v', 'a', 'o', 'e', 'ê', '_i', 'er', 'm', 'n', 'ng']
            single_quality = sorted(finals["单质韵母"],
                                key=lambda x: (
                                    priority_order.index(x) if x in priority_order else len(priority_order)
                                ))
            sorted_finals["单质韵母"] = single_quality

        # 前长韵母排序规则
        if "前长韵母" in finals:
            priority_order = ['i', 'o', 'u', 'n', 'ng']
            front_long = sorted(finals["前长韵母"],
                            key=lambda x: (
                                priority_order.index(x[1]) if len(x) > 1 and x[1] in priority_order else len(priority_order),
                                x[2] if len(x) > 2 else '',
                                x[1] if len(x) > 1 else '',
                                x[0]
                            ))
            sorted_finals["前长韵母"] = front_long

        # 后长韵母排序规则
        if "后长韵母" in finals:
            priority_order = ['a', 'o', 'e', 'n', 'ng']
            back_long = sorted(finals["后长韵母"],
                            key=lambda x: (
                                priority_order.index(x[1]) if len(x) > 1 and x[1] in priority_order else len(priority_order),
                                x[2] if len(x) > 2 else '',
                                x[1] if len(x) > 1 else '',
                                0 if x[0] == 'i' else (1 if x[0] == 'u' else (2 if x[0] == 'ü' else 3)),
                                x[0]
                            ))
            sorted_finals["后长韵母"] = back_long

        # 三质韵母排序规则
        if "三质韵母" in finals:
            priority_order = ['ai', 'ei', 'i', 'ao', 'ou', 'u', 'an', 'en', 'n', 'ang', 'eng', 'ng', 'ong']
            triple_quality = sorted(finals["三质韵母"],
                                key=lambda x: (
                                    priority_order.index(x[1:]) if len(x) > 1 and x[1:] in priority_order else len(priority_order),
                                    x[2] if len(x) > 2 else '',
                                    x[1] if len(x) > 1 else '',
                                    0 if x[0] == 'i' else (1 if x[0] == 'u' else (2 if x[0] == 'ü' else 3)),
                                ))
            sorted_finals["三质韵母"] = triple_quality

        return sorted_finals
