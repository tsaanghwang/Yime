"""干音分类工具类。"""

try:
    from .final_categorizer import FinalCategorizer
    from .syllable_splitter import SyllableSplitter
except ImportError:
    from final_categorizer import FinalCategorizer
    from syllable_splitter import SyllableSplitter


class GanyinCategorizer(FinalCategorizer, SyllableSplitter):
    """负责干音与音节切分相关的规则。"""

    @classmethod
    def extract_final(cls, pinyin: str) -> str:
        """从拼音中提取韵母部分

        参数:
            pinyin: 拼音字符串

        返回:
            final: 韵母字符串
        """
        if not pinyin:
            return ""

        _, ganyin = cls.split_syllable(pinyin)
        return cls._remove_tone_from_ganyin(ganyin)

