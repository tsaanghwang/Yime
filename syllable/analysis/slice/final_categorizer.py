"""韵母分类工具类。"""

from typing import Final, TypeAlias

FinalSet: TypeAlias = set[str]
FinalsByCategory: TypeAlias = dict[str, FinalSet]
SortedFinalsByCategory: TypeAlias = dict[str, list[str]]
FinalFormInfo: TypeAlias = dict[str, str]
MissingHandlingInfo: TypeAlias = dict[str, str | list[str]]


class FinalCategorizer:
    """根据韵母类型进行分类与排序。"""

    RULE_VARIANT_SURFACE_FORMS: Final[dict[str, tuple[str, ...]]] = {
        'iou': ('iu', 'ou'),
        'uei': ('ui', 'ei'),
        'uen': ('un', 'en'),
        'ue': ('üe', 've'),
        'ueng': ('eng',),
    }

    FINAL_FORM_METADATA: Final[dict[str, FinalFormInfo]] = {
        '_i': {
            'kind': '常规形式',
            'source': '常规韵母定义',
            'detail': '舌尖元音的内部表示形式，用于 zi、ci、si 一类音节的韵母处理。',
        },
        'a': {
            'kind': '常规形式',
            'source': '常规韵母定义',
            'detail': '基础单韵母，直接按标准韵母处理。',
        },
        'e': {
            'kind': '常规形式',
            'source': '常规韵母定义',
            'detail': '基础单韵母，直接按标准韵母处理。',
        },
        'er': {
            'kind': '常规形式',
            'source': '常规韵母定义',
            'detail': '卷舌单韵母，直接按标准韵母处理。',
        },
        'i': {
            'kind': '常规形式',
            'source': '常规韵母定义',
            'detail': '基础单韵母，直接按标准韵母处理。',
        },
        'io': {
            'kind': '特殊形式',
            'source': '词典或输入法收录',
            'detail': '不属于《汉语拼音方案》标准韵母表，但在实际拼写和部分输入法编码中出现。',
        },
        'm': {
            'kind': '特殊形式',
            'source': '特殊音节收录',
            'detail': '独立鼻音节形式，通常只在 hm 一类特殊音节处理中出现。',
        },
        'n': {
            'kind': '特殊形式',
            'source': '特殊音节收录',
            'detail': '独立鼻音节形式，作为特殊音节或感叹音收录。',
        },
        'ng': {
            'kind': '特殊形式',
            'source': '特殊音节收录',
            'detail': '独立鼻音节形式，作为特殊音节或感叹音收录。',
        },
        'o': {
            'kind': '常规形式',
            'source': '常规韵母定义',
            'detail': '基础单韵母，直接按标准韵母处理。',
        },
        'u': {
            'kind': '常规形式',
            'source': '常规韵母定义',
            'detail': '基础单韵母，直接按标准韵母处理。',
        },
        'v': {
            'kind': '规则变体',
            'source': 'ü 替代编码',
            'detail': '输入法和内部编码常用 v 代替 ü，以兼容键盘输入和无变音符环境。',
        },
        'ê': {
            'kind': '特殊形式',
            'source': '特殊韵母收录',
            'detail': '用于保留 ê 韵母的独立记法，属于扩展或特别标注形式。',
        },
        'ü': {
            'kind': '常规形式',
            'source': '常规韵母定义',
            'detail': '基础单韵母，直接按标准韵母处理。',
        },
        'ai': {
            'kind': '常规形式',
            'source': '常规韵母定义',
            'detail': '复合韵母，直接按标准韵母处理。',
        },
        'an': {
            'kind': '常规形式',
            'source': '常规韵母定义',
            'detail': '前鼻尾韵母，直接按标准韵母处理。',
        },
        'ang': {
            'kind': '常规形式',
            'source': '常规韵母定义',
            'detail': '后鼻尾韵母，直接按标准韵母处理。',
        },
        'ao': {
            'kind': '常规形式',
            'source': '常规韵母定义',
            'detail': '复合韵母，直接按标准韵母处理。',
        },
        'ei': {
            'kind': '常规形式',
            'source': '常规韵母定义',
            'detail': '复合韵母，直接按标准韵母处理。',
        },
        'en': {
            'kind': '常规形式',
            'source': '常规韵母定义',
            'detail': '前鼻尾韵母，直接按标准韵母处理。',
        },
        'eng': {
            'kind': '常规形式',
            'source': '常规韵母定义',
            'detail': '后鼻尾韵母，直接按标准韵母处理。',
        },
        'ou': {
            'kind': '常规形式',
            'source': '常规韵母定义',
            'detail': '复合韵母，直接按标准韵母处理。',
        },
        'ia': {
            'kind': '常规形式',
            'source': '常规韵母定义',
            'detail': '介音 i 加主元音的常规组合，直接按标准韵母处理。',
        },
        'ie': {
            'kind': '常规形式',
            'source': '常规韵母定义',
            'detail': '介音 i 加主元音的常规组合，直接按标准韵母处理。',
        },
        'ua': {
            'kind': '常规形式',
            'source': '常规韵母定义',
            'detail': '介音 u 加主元音的常规组合，直接按标准韵母处理。',
        },
        'ue': {
            'kind': '规则变体',
            'source': 'ü 省写形式',
            'detail': '由 üe 在 y、j、q、x 前的省写规则产生，实际拼写中常写作 yue、jue、que、xue。',
        },
        'uo': {
            'kind': '常规形式',
            'source': '常规韵母定义',
            'detail': '介音 u 加主元音的常规组合，直接按标准韵母处理。',
        },
        've': {
            'kind': '规则变体',
            'source': 'üe 的输入法编码',
            'detail': '用 v 代替 ü 的编码写法，对应标准形式 üe。',
        },
        'üe': {
            'kind': '常规形式',
            'source': '常规韵母定义',
            'detail': '带介音 ü 的常规复合韵母，直接按标准韵母处理。',
        },
        'ian': {
            'kind': '常规形式',
            'source': '常规韵母定义',
            'detail': '介音 i 加前鼻尾的常规组合，直接按标准韵母处理。',
        },
        'iang': {
            'kind': '常规形式',
            'source': '常规韵母定义',
            'detail': '介音 i 加后鼻尾的常规组合，直接按标准韵母处理。',
        },
        'iao': {
            'kind': '常规形式',
            'source': '常规韵母定义',
            'detail': '介音 i 的常规三元组合，直接按标准韵母处理。',
        },
        'in': {
            'kind': '常规形式',
            'source': '常规韵母定义',
            'detail': '介音 i 加前鼻尾的常规组合，直接按标准韵母处理。',
        },
        'ing': {
            'kind': '常规形式',
            'source': '常规韵母定义',
            'detail': '介音 i 加后鼻尾的常规组合，直接按标准韵母处理。',
        },
        'iong': {
            'kind': '常规形式',
            'source': '常规韵母定义',
            'detail': '介音 i 的常规三元组合，直接按标准韵母处理。',
        },
        'iou': {
            'kind': '规则变体',
            'source': '标准全拼形式',
            'detail': '《汉语拼音方案》中的完整形式，实际拼写中通常按省写规则记作 iu。',
        },
        'iu': {
            'kind': '常规形式',
            'source': '常规拼写形式',
            'detail': '由 iou 按省写规则得到的实际常用拼写形式。',
        },
        'ong': {
            'kind': '常规形式',
            'source': '常规韵母定义',
            'detail': '后鼻尾三元韵母，直接按标准韵母处理。',
        },
        'uai': {
            'kind': '常规形式',
            'source': '常规韵母定义',
            'detail': '介音 u 的常规三元组合，直接按标准韵母处理。',
        },
        'uan': {
            'kind': '常规形式',
            'source': '常规韵母定义',
            'detail': '介音 u 加前鼻尾的常规组合，直接按标准韵母处理。',
        },
        'uang': {
            'kind': '常规形式',
            'source': '常规韵母定义',
            'detail': '介音 u 加后鼻尾的常规组合，直接按标准韵母处理。',
        },
        'uei': {
            'kind': '规则变体',
            'source': '标准全拼形式',
            'detail': '《汉语拼音方案》中的完整形式，实际拼写中通常按省写规则记作 ui。',
        },
        'uen': {
            'kind': '规则变体',
            'source': '标准全拼形式',
            'detail': '《汉语拼音方案》中的完整形式，实际拼写中通常按省写规则记作 un。',
        },
        'ueng': {
            'kind': '规则变体',
            'source': '标准全拼形式',
            'detail': '理论上保留为完整形式，零声母或实际拼写中通常转写为 weng 等表面形式。',
        },
        'ui': {
            'kind': '常规形式',
            'source': '常规拼写形式',
            'detail': '由 uei 按省写规则得到的实际常用拼写形式。',
        },
        'un': {
            'kind': '常规形式',
            'source': '常规拼写形式',
            'detail': '由 uen 按省写规则得到的实际常用拼写形式。',
        },
        'van': {
            'kind': '规则变体',
            'source': 'üan 的输入法编码',
            'detail': '用 v 代替 ü 的编码写法，对应标准形式 üan。',
        },
        'vn': {
            'kind': '规则变体',
            'source': 'ün 的输入法编码',
            'detail': '用 v 代替 ü 的编码写法，对应标准形式 ün。',
        },
        'üan': {
            'kind': '常规形式',
            'source': '常规韵母定义',
            'detail': '带介音 ü 的前鼻尾常规组合，直接按标准韵母处理。',
        },
        'ün': {
            'kind': '常规形式',
            'source': '常规韵母定义',
            'detail': '带介音 ü 的前鼻尾常规组合，直接按标准韵母处理。',
        },
    }

    SINGLE_QUALITY_FINALS: Final[FinalSet] = {
        '_i', 'a', 'e', 'er', 'i', 'm', 'n', 'ng', 'o', 'u', 'v', 'ê', 'ü'
    }
    FRONT_LONG_FINALS: Final[FinalSet] = {'ai', 'an', 'ang', 'ao', 'ei', 'en', 'eng', 'ou'}
    BACK_LONG_FINALS: Final[FinalSet] = {'ia', 'ie', 'io', 'ua', 'ue', 'uo', 've', 'üe'}
    TRIPLE_QUALITY_FINALS: Final[FinalSet] = {
        'ian', 'iang', 'iao', 'in', 'ing', 'iong', 'iou', 'iu', 'ong',
        'uai', 'uan', 'uang', 'uei', 'uen', 'ueng', 'ui', 'un', 'van',
        'vn', 'üan', 'ün'
    }

    @staticmethod
    def categorize(ganyin: str) -> str:
        """干音根据韵母类型分类。"""
        if not ganyin:
            return "未知类型"

        final = FinalCategorizer._remove_tone_from_ganyin(ganyin)

        if final in FinalCategorizer.SINGLE_QUALITY_FINALS:
            return "单质干音"
        if final in FinalCategorizer.FRONT_LONG_FINALS:
            return "前长干音"
        if final in FinalCategorizer.BACK_LONG_FINALS:
            return "后长干音"
        if final in FinalCategorizer.TRIPLE_QUALITY_FINALS:
            return "三质干音"
        return "未知类型"

    @staticmethod
    def _remove_tone_from_ganyin(ganyin: str) -> str:
        """从干音中提取不带声调的韵母字符串。"""
        if ganyin.startswith('_'):
            prefix = '_'
            final = ganyin[1:]
        else:
            prefix = ''
            final = ganyin

        if final and final[-1].isdigit():
            final = final[:-1]

        tone_mapping = {
            'ā': 'a', 'á': 'a', 'ǎ': 'a', 'à': 'a',
            'ē': 'e', 'é': 'e', 'ě': 'e', 'è': 'e',
            'ī': 'i', 'í': 'i', 'ǐ': 'i', 'ì': 'i',
            'ō': 'o', 'ó': 'o', 'ǒ': 'o', 'ò': 'o',
            'ū': 'u', 'ú': 'u', 'ǔ': 'u', 'ù': 'u',
            'ǖ': 'ü', 'ǘ': 'ü', 'ǚ': 'ü', 'ǜ': 'ü',
            'ń': 'n', 'ň': 'n', 'ǹ': 'n', 'n̄': 'n',
            'ḿ': 'm', 'm̌': 'm', 'm̀': 'm', 'm̄': 'm',
            'ế': 'ê', 'ê̌': 'ê', 'ề': 'ê', 'ê̄': 'ê',
        }

        result = ''.join(tone_mapping.get(char, char) for char in final)
        return prefix + result

    @staticmethod
    def _add_final_to_category(final: str) -> bool:
        """将韵母动态添加到合适的分类中。"""
        if not final:
            return False

        all_finals = (
            FinalCategorizer.SINGLE_QUALITY_FINALS |
            FinalCategorizer.FRONT_LONG_FINALS |
            FinalCategorizer.BACK_LONG_FINALS |
            FinalCategorizer.TRIPLE_QUALITY_FINALS
        )
        if final in all_finals:
            return False

        if FinalCategorizer._should_be_single_quality(final):
            FinalCategorizer.SINGLE_QUALITY_FINALS.add(final)
            return True
        if FinalCategorizer._should_be_front_long(final):
            FinalCategorizer.FRONT_LONG_FINALS.add(final)
            return True
        if FinalCategorizer._should_be_back_long(final):
            FinalCategorizer.BACK_LONG_FINALS.add(final)
            return True
        if FinalCategorizer._should_be_triple_quality(final):
            FinalCategorizer.TRIPLE_QUALITY_FINALS.add(final)
            return True

        FinalCategorizer.SINGLE_QUALITY_FINALS.add(final)
        return True

    @staticmethod
    def _should_be_single_quality(final: str) -> bool:
        pure_final = final[1:] if final.startswith('_') else final
        special_single_finals = {'ü', 'v', 'ê', 'er', 'm', 'n', 'ng'}
        if final == '_i':
            return True
        return len(pure_final) == 1 or pure_final in special_single_finals

    @staticmethod
    def _should_be_front_long(final: str) -> bool:
        if len(final) < 2:
            return False
        if final[0] in {'a', 'e', 'o'} and len(final) == 2:
            return True
        return final.endswith(('n', 'ng')) and final[0] not in {'i', 'u', 'ü'}

    @staticmethod
    def _should_be_back_long(final: str) -> bool:
        return len(final) >= 2 and final[0] in {'i', 'u', 'ü'} and not FinalCategorizer._should_be_triple_quality(final)

    @staticmethod
    def _should_be_triple_quality(final: str) -> bool:
        if len(final) < 3:
            return False
        triple_patterns = {'iao', 'iou', 'uan', 'uen', 'iang', 'uang', 'ueng'}
        return final in triple_patterns or len(final) >= 4

    @staticmethod
    def get_all_categories() -> tuple[str, str, str, str]:
        return ("单质干音", "前长干音", "后长干音", "三质干音")

    @staticmethod
    def get_finals_by_category(category: str) -> FinalSet:
        category_mapping: FinalsByCategory = {
            "单质韵母": FinalCategorizer.SINGLE_QUALITY_FINALS,
            "前长韵母": FinalCategorizer.FRONT_LONG_FINALS,
            "后长韵母": FinalCategorizer.BACK_LONG_FINALS,
            "三质韵母": FinalCategorizer.TRIPLE_QUALITY_FINALS,
        }
        return category_mapping.get(category, set())

    @staticmethod
    def get_all_finals() -> FinalsByCategory:
        return {
            "单质韵母": FinalCategorizer.SINGLE_QUALITY_FINALS,
            "前长韵母": FinalCategorizer.FRONT_LONG_FINALS,
            "后长韵母": FinalCategorizer.BACK_LONG_FINALS,
            "三质韵母": FinalCategorizer.TRIPLE_QUALITY_FINALS,
        }

    @staticmethod
    def get_final_form_info(final: str) -> FinalFormInfo:
        return FinalCategorizer.FINAL_FORM_METADATA.get(
            final,
            {
                'kind': '常规形式',
                'source': '常规韵母定义',
                'detail': '该韵母直接按常规韵母处理，没有额外的规则变体或特殊收录说明。',
            },
        )

    @staticmethod
    def get_all_final_form_metadata() -> dict[str, FinalFormInfo]:
        all_finals = (
            FinalCategorizer.SINGLE_QUALITY_FINALS |
            FinalCategorizer.FRONT_LONG_FINALS |
            FinalCategorizer.BACK_LONG_FINALS |
            FinalCategorizer.TRIPLE_QUALITY_FINALS
        )
        return {final: FinalCategorizer.get_final_form_info(final) for final in sorted(all_finals)}

    @staticmethod
    def get_missing_handling_info(final: str) -> MissingHandlingInfo:
        if final in FinalCategorizer.RULE_VARIANT_SURFACE_FORMS:
            return {
                'status': '拼写规则导致缺失',
                'reason': '理论侧完整形式在实际侧会按拼写规则落到其他表面韵母，属于实际拼写规则导致的数据出入。',
                'surface_forms': list(FinalCategorizer.RULE_VARIANT_SURFACE_FORMS[final]),
            }

        final_info = FinalCategorizer.get_final_form_info(final)
        if final_info['kind'] == '特殊形式':
            return {
                'status': '当前导入过滤导致缺失',
                'reason': '理论侧保留了该特殊形式，但当前实际导入数据未直接收录；这说明当前数据源存在过滤，不代表该形式未来不会出现。',
                'surface_forms': [],
                'source_type': final_info['source'],
            }

        return {
            'status': '真异常缺失',
            'reason': '既不是规则变体，也不是已登记的特殊收录形式，应视为需要排查的数据异常。',
            'surface_forms': [],
        }

    @staticmethod
    def sort_finals_by_category(finals: FinalsByCategory) -> SortedFinalsByCategory:
        sorted_finals: SortedFinalsByCategory = {}

        if "单质韵母" in finals:
            priority_order = ['i', 'u', 'ü', 'v', 'a', 'o', 'e', 'ê', '_i', 'er', 'm', 'n', 'ng']
            sorted_finals["单质韵母"] = sorted(
                finals["单质韵母"],
                key=lambda final: priority_order.index(final) if final in priority_order else len(priority_order),
            )

        if "前长韵母" in finals:
            priority_order = ['i', 'o', 'u', 'n', 'ng']
            sorted_finals["前长韵母"] = sorted(
                finals["前长韵母"],
                key=lambda final: (
                    priority_order.index(final[1]) if len(final) > 1 and final[1] in priority_order else len(priority_order),
                    final[2] if len(final) > 2 else '',
                    final[1] if len(final) > 1 else '',
                    final[0],
                ),
            )

        if "后长韵母" in finals:
            priority_order = ['a', 'o', 'e', 'n', 'ng']
            sorted_finals["后长韵母"] = sorted(
                finals["后长韵母"],
                key=lambda final: (
                    priority_order.index(final[1]) if len(final) > 1 and final[1] in priority_order else len(priority_order),
                    final[2] if len(final) > 2 else '',
                    final[1] if len(final) > 1 else '',
                    0 if final[0] == 'i' else (1 if final[0] == 'u' else (2 if final[0] == 'ü' else 3)),
                    final[0],
                ),
            )

        if "三质韵母" in finals:
            priority_order = ['ai', 'ei', 'i', 'ao', 'ou', 'u', 'an', 'en', 'n', 'ang', 'eng', 'ng', 'ong']
            sorted_finals["三质韵母"] = sorted(
                finals["三质韵母"],
                key=lambda final: (
                    priority_order.index(final[1:]) if len(final) > 1 and final[1:] in priority_order else len(priority_order),
                    final[2] if len(final) > 2 else '',
                    final[1] if len(final) > 1 else '',
                    0 if final[0] == 'i' else (1 if final[0] == 'u' else (2 if final[0] == 'ü' else 3)),
                ),
            )

        return sorted_finals
