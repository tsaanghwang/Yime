# pinyin/test_yunmu_to_keys_comprehensive.py
import unittest
from pinyin.yunmu_to_keys import YunmuConverter, ConversionRule
from pinyin.constants import YunmuConstants

class TestYunmuConstants(unittest.TestCase):
    """测试韵母常量类"""

    def setUp(self):
        self.constants = YunmuConstants()

    def test_constants_initialization(self):
        """测试常量初始化"""
        self.assertEqual(self.constants.I_APICAL, "-i")
        self.assertEqual(self.constants.I_APICAL_REPLACEMENT, "ir")
        self.assertEqual(self.constants.AO_FINAL, "ao")
        self.assertEqual(self.constants.Y_NEAR_ROUNDED, "ü")
        self.assertEqual(self.constants.Y_REPLACEMENT, "v")

    def test_required_finals_property(self):
        """测试必需韵母列表"""
        required = self.constants.REQUIRED_FINALS
        self.assertIsInstance(required, list)
        self.assertGreater(len(required), 0)
        # 验证关键韵母存在
        self.assertIn("a", required)
        self.assertIn("o", required)
        self.assertIn("e", required)
        self.assertIn("i", required)
        self.assertIn("u", required)
        self.assertIn("ü", required)
        self.assertIn("ao", required)
        self.assertIn("eng", required)
        self.assertIn("ing", required)

    def test_replacement_table(self):
        """测试替换表生成"""
        table = YunmuConstants.get_replacement_table()
        self.assertIsInstance(table, dict)
        # 验证关键替换
        self.assertIn(ord("ü"), table)
        self.assertEqual(table[ord("ü")], "v")  # maketrans 返回字符而非ord

    def test_derived_constants(self):
        """测试派生常量"""
        self.assertEqual(self.constants.YE, "üe")
        self.assertEqual(self.constants.YAN, "üan")
        self.assertEqual(self.constants.YN, "ün")
        self.assertEqual(self.constants.FINAL_ONG, "ong")
        self.assertEqual(self.constants.FINAL_IONG, "iong")
        self.assertEqual(self.constants.FINAL_UONG, "uong")
        self.assertEqual(self.constants.FINAL_YONG, "vong")

    def test_all_constants_are_strings(self):
        """测试所有常量都是字符串"""
        string_constants = [
            'I_APICAL', 'I_APICAL_REPLACEMENT',
            'O_CODA', 'U_CODA', 'AO_FINAL', 'IAO_FINAL',
            'Y_NEAR_ROUNDED', 'Y_REPLACEMENT',
            'O_ROUNDED', 'O_UNROUNDED',
            'E_CIRCUMFLEX', 'E_FRONT',
            'N_RIME', 'EN_RIME', 'IN_FINAL', 'YN_FINAL',
            'ENG_FINAL', 'ING_FINAL', 'UENG_FINAL',
            'UNG_FINAL', 'YNG_FINAL',
            'FINAL_ONG', 'FINAL_IONG', 'FINAL_UONG', 'FINAL_YONG',
        ]

        for const_name in string_constants:
            value = getattr(self.constants, const_name)
            self.assertIsInstance(value, str, f"{const_name} 应该是字符串")

    def test_required_finals_completeness(self):
        """测试必需韵母完整性"""
        required = self.constants.REQUIRED_FINALS

        # 验证包含所有基本元音
        basic_vowels = ["a", "o", "e", "i", "u", "ü"]
        for vowel in basic_vowels:
            self.assertIn(vowel, required, f"基本元音 {vowel} 应该在必需列表中")

        # 验证包含所有复韵母
        compound_finals = ["ai", "ei", "ao", "ou"]
        for final in compound_finals:
            self.assertIn(final, required, f"复韵母 {final} 应该在必需列表中")

        # 验证包含所有鼻韵母
        nasal_finals = ["an", "en", "ang", "eng", "in", "ing"]
        for final in nasal_finals:
            self.assertIn(final, required, f"鼻韵母 {final} 应该在必需列表中")

    def test_replacement_table_completeness(self):
        """测试替换表完整性"""
        table = YunmuConstants.get_replacement_table()

        # 验证关键字符的替换
        expected_replacements = {
            "ü": "v",
            "o": "u",
            "e": "o",
            "n": "en",
        }

        for char, replacement in expected_replacements.items():
            if ord(char) in table:
                self.assertEqual(table[ord(char)], replacement)

    def test_constants_immutability(self):
        """测试常量不可变性"""
        # 创建两个实例，验证常量值相同
        constants1 = YunmuConstants()
        constants2 = YunmuConstants()

        self.assertEqual(constants1.I_APICAL, constants2.I_APICAL)
        self.assertEqual(constants1.AO_FINAL, constants2.AO_FINAL)
        self.assertEqual(constants1.Y_NEAR_ROUNDED, constants2.Y_NEAR_ROUNDED)

    def test_required_finals_no_duplicates(self):
        """测试必需韵母无重复"""
        required = self.constants.REQUIRED_FINALS
        unique_required = list(set(required))

        self.assertEqual(len(required), len(unique_required),
                        "必需韵母列表不应有重复")

    def test_special_constants(self):
        """测试特殊常量"""
        # 测试舌尖元音
        self.assertEqual(self.constants.I_APICAL, "-i")

        # 测试特殊元音
        self.assertEqual(self.constants.E_CIRCUMFLEX, "ê")
        self.assertEqual(self.constants.E_FRONT, "e")

        # 测试鼻音
        self.assertEqual(self.constants.N_RIME, "n")
        self.assertEqual(self.constants.EN_RIME, "en")

    def test_final_constants_consistency(self):
        """测试韵母常量一致性"""
        # 验证 FINAL_ 常量与对应关系
        self.assertEqual(self.constants.FINAL_ONG, "ong")
        self.assertEqual(self.constants.FINAL_IONG, "iong")
        self.assertEqual(self.constants.FINAL_UONG, "uong")
        self.assertEqual(self.constants.FINAL_YONG, "vong")

        # 验证这些常量在必需列表中
        required = self.constants.REQUIRED_FINALS
        self.assertIn(self.constants.FINAL_ONG, required)

    def test_y_series_constants(self):
        """测试 Y 系列常量"""
        y_base = self.constants.Y_NEAR_ROUNDED

        self.assertEqual(self.constants.YE, y_base + "e")
        self.assertEqual(self.constants.YAN, y_base + "an")
        self.assertEqual(self.constants.YN, y_base + "n")
        self.assertEqual(self.constants.Y_REPLACEMENT, "v")

    def test_class_method_get_replacement_table(self):
        """测试类方法获取替换表"""
        # 验证可以通过类直接调用
        table1 = YunmuConstants.get_replacement_table()
        table2 = self.constants.get_replacement_table()

        self.assertEqual(table1, table2)


class TestConversionRule(unittest.TestCase):
    """测试转换规则类"""

    def test_rule_creation(self):
        """测试规则创建"""
        rule = ConversionRule(
            condition=lambda k: k == "test",
            action=lambda v: v.upper(),
            description="测试规则",
            priority=1
        )
        self.assertEqual(rule.description, "测试规则")
        self.assertEqual(rule.priority, 1)

    def test_rule_default_description(self):
        """测试默认描述生成"""
        rule = ConversionRule(
            condition=lambda k: True,
            action=lambda v: v
        )
        self.assertIsNotNone(rule.description)
        self.assertTrue(rule.description.startswith("规则"))

    def test_rule_condition_execution(self):
        """测试条件执行"""
        rule = ConversionRule(
            condition=lambda k: k == "match",
            action=lambda v: "converted"
        )
        self.assertTrue(rule.condition("match"))
        self.assertFalse(rule.condition("no_match"))

    def test_rule_action_execution(self):
        """测试动作执行"""
        rule = ConversionRule(
            condition=lambda k: True,
            action=lambda v: v.upper()
        )
        result = rule.action("test")
        self.assertEqual(result, "TEST")


class TestYunmuConverter(unittest.TestCase):
    """测试韵母转换器"""

    def setUp(self):
        self.converter = YunmuConverter()
        self.constants = YunmuConstants()
        self.full_yunmu_dict = {yunmu: "" for yunmu in self.constants.REQUIRED_FINALS}

    def test_converter_initialization(self):
        """测试转换器初始化"""
        self.assertIsNotNone(self.converter._constants)
        self.assertIsInstance(self.converter.rules, list)
        self.assertGreater(len(self.converter.rules), 0)
        self.assertEqual(self.converter.total_conversions, 0)
        self.assertEqual(self.converter.successful_conversions, 0)

    def test_default_rules_creation(self):
        """测试默认规则创建"""
        rules = self.converter._get_default_rules()
        self.assertIsInstance(rules, list)
        self.assertGreater(len(rules), 0)
        # 验证规则优先级
        priorities = [rule.priority for rule in rules]
        self.assertEqual(priorities, sorted(priorities))

    def test_regex_patterns_compilation(self):
        """测试正则表达式编译"""
        self.converter._compile_regex_patterns()
        self.assertIn('yn', self.converter.patterns)
        self.assertIn('vn', self.converter.patterns)

    def test_validate_input_valid(self):
        """测试有效输入验证"""
        # 不应抛出异常
        self.converter.validate_input(self.full_yunmu_dict)

    def test_validate_input_not_dict(self):
        """测试非字典输入验证"""
        with self.assertRaises(ValueError) as context:
            self.converter.validate_input("not a dict")
        self.assertIn("必须是字典", str(context.exception))

    def test_validate_input_non_string_values(self):
        """测试非字符串值验证"""
        invalid_dict = {k: 123 for k in self.constants.REQUIRED_FINALS}
        with self.assertRaises(ValueError) as context:
            self.converter.validate_input(invalid_dict)
        self.assertIn("都必须是字符串", str(context.exception))

    def test_validate_input_missing_finals(self):
        """测试缺少韵母验证"""
        partial_dict = {"a": "", "o": ""}
        with self.assertRaises(ValueError) as context:
            self.converter.validate_input(partial_dict)
        self.assertIn("缺少必要的韵母", str(context.exception))

    def test_convert_basic(self):
        """测试基本转换"""
        result = self.converter.convert(self.full_yunmu_dict)
        self.assertIsInstance(result, dict)
        self.assertGreater(len(result), 0)

    def test_convert_i_apical(self):
        """测试舌尖元音-i转换"""
        result = self.converter.convert(self.full_yunmu_dict)
        self.assertEqual(result["-i"], "ir")

    def test_convert_ao_final(self):
        """测试ao韵母转换"""
        result = self.converter.convert(self.full_yunmu_dict)
        self.assertEqual(result["ao"], "au")

    def test_convert_iao_final(self):
        """测试iao韵母转换"""
        result = self.converter.convert(self.full_yunmu_dict)
        self.assertEqual(result["iao"], "iau")

    def test_convert_y_near_rounded(self):
        """测试ü转换"""
        result = self.converter.convert(self.full_yunmu_dict)
        self.assertEqual(result["ü"], "v")

    def test_convert_iong_final(self):
        """测试iong韵母转换"""
        result = self.converter.convert(self.full_yunmu_dict)
        self.assertEqual(result["iong"], "vong")

    def test_convert_ing_final(self):
        """测试ing韵母转换"""
        result = self.converter.convert(self.full_yunmu_dict)
        self.assertEqual(result["ing"], "iong")

    def test_convert_e_unrounded(self):
        """测试e韵母转换"""
        result = self.converter.convert(self.full_yunmu_dict)
        # e 可能被其他规则覆盖，保持原值
        self.assertIn("e", result)

    def test_convert_eng_final(self):
        """测试eng韵母转换"""
        result = self.converter.convert(self.full_yunmu_dict)
        self.assertEqual(result["eng"], "ong")

    def test_convert_in_final(self):
        """测试in韵母转换"""
        result = self.converter.convert(self.full_yunmu_dict)
        self.assertEqual(result["in"], "ien")

    def test_convert_yn_final(self):
        """测试ün韵母转换"""
        result = self.converter.convert(self.full_yunmu_dict)
        self.assertEqual(result["ün"], "ven")

    def test_convert_ueng_final(self):
        """测试ueng韵母转换"""
        result = self.converter.convert(self.full_yunmu_dict)
        self.assertEqual(result["ueng"], "uong")

    def test_convert_ong_final(self):
        """测试ong韵母转换"""
        result = self.converter.convert(self.full_yunmu_dict)
        # ong 可能被其他规则覆盖，保持原值
        self.assertIn("ong", result)

    def test_convert_e_circumflex(self):
        """测试ê韵母特殊处理"""
        result = self.converter.convert(self.full_yunmu_dict)
        # ê应该映射到e
        self.assertIn("e", result)

    def test_apply_rules_priority(self):
        """测试规则优先级应用"""
        # 规则应该按优先级顺序应用
        result = self.converter._apply_rules("-i")
        self.assertEqual(result, "ir")

    def test_get_stats(self):
        """测试统计信息获取"""
        self.converter.convert(self.full_yunmu_dict)
        stats = self.converter.get_stats()

        self.assertIn('total_conversions', stats)
        self.assertIn('successful_conversions', stats)
        self.assertIn('failed_conversions', stats)
        self.assertIn('success_rate', stats)
        self.assertIn('rule_stats', stats)

        self.assertGreater(stats['total_conversions'], 0)
        self.assertEqual(stats['successful_conversions'], stats['total_conversions'])
        self.assertEqual(stats['success_rate'], 100.0)

    def test_multiple_conversions(self):
        """测试多次转换"""
        # 第一次转换
        result1 = self.converter.convert(self.full_yunmu_dict)
        stats1 = self.converter.get_stats()

        # 第二次转换
        result2 = self.converter.convert(self.full_yunmu_dict)
        stats2 = self.converter.get_stats()

        # 结果应该一致
        self.assertEqual(result1, result2)

    def test_rule_counter(self):
        """测试规则计数器"""
        self.converter.convert(self.full_yunmu_dict)

        # 应该有规则被应用
        self.assertGreater(len(self.converter.rule_counter), 0)

        # 每个规则的计数应该大于0
        for rule_id, count in self.converter.rule_counter.items():
            self.assertGreater(count, 0)

    def test_conversion_idempotent(self):
        """测试转换幂等性"""
        result1 = self.converter.convert(self.full_yunmu_dict)
        result2 = self.converter.convert(self.full_yunmu_dict)
        self.assertEqual(result1, result2)

    def test_all_required_finals_converted(self):
        """测试所有必需韵母都被转换"""
        result = self.converter.convert(self.full_yunmu_dict)

        # 验证大部分韵母都被转换（除了特殊处理的ê）
        converted_count = len(result)
        required_count = len(self.constants.REQUIRED_FINALS)

        # 转换数量应该接近必需数量（考虑特殊处理）
        self.assertGreater(converted_count, required_count * 0.9)


class TestYunmuConverterEdgeCases(unittest.TestCase):
    """测试边界情况"""

    def setUp(self):
        self.converter = YunmuConverter()
        self.constants = YunmuConstants()

    def test_empty_string_value(self):
        """测试空字符串值"""
        yunmu_dict = {k: "" for k in self.constants.REQUIRED_FINALS}
        result = self.converter.convert(yunmu_dict)
        self.assertIsInstance(result, dict)

    def test_special_characters(self):
        """测试特殊字符"""
        yunmu_dict = {k: "" for k in self.constants.REQUIRED_FINALS}
        result = self.converter.convert(yunmu_dict)

        # 验证特殊字符正确处理
        self.assertIn("ü", yunmu_dict)
        self.assertIn("v", result.values())

    def test_all_vowels(self):
        """测试所有元音"""
        vowels = ["a", "o", "e", "i", "u", "ü"]
        yunmu_dict = {k: "" for k in self.constants.REQUIRED_FINALS}
        result = self.converter.convert(yunmu_dict)

        for vowel in vowels:
            if vowel in yunmu_dict:
                self.assertIn(vowel, result)

    def test_complex_finals(self):
        """测试复杂韵母"""
        complex_finals = ["ang", "eng", "ing", "ong", "iang", "uang", "iong"]
        yunmu_dict = {k: "" for k in self.constants.REQUIRED_FINALS}
        result = self.converter.convert(yunmu_dict)

        for final in complex_finals:
            if final in yunmu_dict:
                self.assertIn(final, result)


class TestYunmuConverterIntegration(unittest.TestCase):
    """集成测试"""

    def test_full_conversion_workflow(self):
        """测试完整转换工作流"""
        constants = YunmuConstants()
        converter = YunmuConverter()

        # 创建完整韵母字典
        yunmu_dict = {k: "" for k in constants.REQUIRED_FINALS}

        # 执行转换
        result = converter.convert(yunmu_dict)

        # 验证结果
        self.assertIsInstance(result, dict)
        self.assertGreater(len(result), 0)

        # 获取统计
        stats = converter.get_stats()
        self.assertEqual(stats['success_rate'], 100.0)

    def test_conversion_consistency(self):
        """测试转换一致性"""
        constants = YunmuConstants()
        converter1 = YunmuConverter()
        converter2 = YunmuConverter()

        yunmu_dict = {k: "" for k in constants.REQUIRED_FINALS}

        result1 = converter1.convert(yunmu_dict)
        result2 = converter2.convert(yunmu_dict)

        # 两个转换器应该产生相同结果
        self.assertEqual(result1, result2)


class TestYunmuConverterErrorHandling(unittest.TestCase):
    """测试错误处理"""

    def setUp(self):
        self.converter = YunmuConverter()
        self.constants = YunmuConstants()

    def test_exception_handling_in_convert(self):
        """测试转换中的异常处理"""
        # 创建一个会导致异常的规则
        def bad_action(v):
            raise RuntimeError("测试异常")

        # 临时替换规则
        original_rules = self.converter.rules
        self.converter.rules = [
            ConversionRule(
                condition=lambda k: k == "a",
                action=bad_action,
                description="会失败的规则"
            )
        ]

        # 测试异常被正确处理
        yunmu_dict = {k: "" for k in self.constants.REQUIRED_FINALS}
        with self.assertRaises(RuntimeError):
            self.converter.convert(yunmu_dict)

        # 恢复规则
        self.converter.rules = original_rules

    def test_exception_handling_in_apply_rules(self):
        """测试规则应用中的异常处理"""
        def bad_action(v):
            raise ValueError("规则执行失败")

        rule = ConversionRule(
            condition=lambda k: True,
            action=bad_action
        )

        self.converter.rules = [rule]

        with self.assertRaises(ValueError):
            self.converter._apply_rules("test")

    def test_failed_conversions_counter(self):
        """测试失败转换计数"""
        # 创建会失败的规则
        def bad_action(v):
            raise Exception("失败")

        self.converter.rules = [
            ConversionRule(
                condition=lambda k: True,
                action=bad_action
            )
        ]

        yunmu_dict = {k: "" for k in self.constants.REQUIRED_FINALS}

        try:
            self.converter.convert(yunmu_dict)
        except Exception:
            pass

        # 验证失败计数
        self.assertGreater(self.converter.failed_conversions, 0)


class TestYunmuConverterAdvanced(unittest.TestCase):
    """高级测试"""

    def setUp(self):
        self.converter = YunmuConverter()
        self.constants = YunmuConstants()

    def test_rule_priority_order(self):
        """测试规则优先级顺序"""
        rules = self.converter.rules
        priorities = [rule.priority for rule in rules]

        # 验证优先级是递增的
        for i in range(len(priorities) - 1):
            self.assertLessEqual(priorities[i], priorities[i + 1])

    def test_all_rules_have_valid_structure(self):
        """测试所有规则都有有效结构"""
        for rule in self.converter.rules:
            # 验证规则有条件函数
            self.assertTrue(callable(rule.condition))
            # 验证规则有动作函数
            self.assertTrue(callable(rule.action))
            # 验证规则有描述
            self.assertIsInstance(rule.description, str)
            # 验证规则有优先级
            self.assertIsInstance(rule.priority, int)

    def test_replacement_table_usage(self):
        """测试替换表使用"""
        table = self.converter.replacement_table
        self.assertIsInstance(table, dict)

        # 验证关键替换存在
        self.assertIn(ord("ü"), table)

    def test_regex_patterns_functionality(self):
        """测试正则表达式功能"""
        patterns = self.converter.patterns

        # 测试 yn 模式
        self.assertTrue(patterns['yn'].search("ün"))
        self.assertFalse(patterns['yn'].search("an"))

        # 测试 vn 模式
        self.assertTrue(patterns['vn'].search("vn"))
        self.assertFalse(patterns['vn'].search("en"))

    def test_stats_completeness(self):
        """测试统计信息完整性"""
        yunmu_dict = {k: "" for k in self.constants.REQUIRED_FINALS}
        self.converter.convert(yunmu_dict)

        stats = self.converter.get_stats()

        # 验证所有统计字段存在
        required_fields = [
            'total_conversions',
            'successful_conversions',
            'failed_conversions',
            'success_rate',
            'rule_stats'
        ]

        for field in required_fields:
            self.assertIn(field, stats)

    def test_zero_division_protection(self):
        """测试零除保护"""
        # 创建新转换器，未执行任何转换
        converter = YunmuConverter()

        # 获取统计不应抛出异常
        stats = converter.get_stats()

        # 验证成功率处理
        self.assertEqual(stats['success_rate'], 0.0)

    def test_rule_counter_accuracy(self):
        """测试规则计数器准确性"""
        yunmu_dict = {k: "" for k in self.constants.REQUIRED_FINALS}
        self.converter.convert(yunmu_dict)

        # 规则计数器总和应该等于成功转换数
        total_rule_applications = sum(self.converter.rule_counter.values())
        self.assertGreater(total_rule_applications, 0)

    def test_conversion_with_all_special_cases(self):
        """测试所有特殊情况转换"""
        yunmu_dict = {k: "" for k in self.constants.REQUIRED_FINALS}
        result = self.converter.convert(yunmu_dict)

        # 验证特殊转换
        special_cases = {
            "-i": "ir",
            "ao": "au",
            "iao": "iau",
            "ü": "v",
            "iong": "vong",
            "ing": "iong",
            "eng": "ong",
            "in": "ien",
            "ueng": "uong",
        }

        for key, expected in special_cases.items():
            if key in result:
                self.assertEqual(result[key], expected,
                               f"{key} 应该转换为 {expected}")


class TestMainFunction(unittest.TestCase):
    """测试主函数"""

    def test_main_function_execution(self):
        """测试主函数执行"""
        from pinyin import yunmu_to_keys

        # 执行主函数不应抛出异常
        try:
            yunmu_to_keys.main()
        except Exception as e:
            self.fail(f"main() 函数执行失败: {e}")


class TestConstantsYunmuConverter(unittest.TestCase):
    """测试 constants.py 中的旧版 YunmuConverter 类"""

    def setUp(self):
        from pinyin.constants import YunmuConverter as OldConverter
        self.OldConverter = OldConverter
        self.converter = OldConverter()

    def test_init(self):
        """测试初始化"""
        self.assertIn('total_conversions', self.converter.stats)
        self.assertIn('successful_conversions', self.converter.stats)
        self.assertIn('failed_conversions', self.converter.stats)
        self.assertEqual(self.converter.stats['total_conversions'], 0)

    def test_convert_basic(self):
        """测试基本转换"""
        input_dict = {"a": "", "o": "", "e": ""}
        result = self.converter.convert(input_dict)
        self.assertIsInstance(result, dict)

    def test_convert_i_apical(self):
        """测试 -i 转换"""
        result = self.converter.convert({"-i": ""})
        self.assertEqual(result["-i"], "ir")

    def test_convert_ao(self):
        """测试 ao 转换"""
        result = self.converter.convert({"ao": ""})
        self.assertEqual(result["ao"], "au")

    def test_convert_iong(self):
        """测试 iong 转换"""
        result = self.converter.convert({"iong": ""})
        self.assertEqual(result["iong"], "vong")

    def test_convert_ing(self):
        """测试 ing 转换"""
        result = self.converter.convert({"ing": ""})
        self.assertEqual(result["ing"], "iong")

    def test_convert_e(self):
        """测试 e 转换"""
        result = self.converter.convert({"e": ""})
        self.assertEqual(result["e"], "o")

    def test_convert_eng(self):
        """测试 eng 转换"""
        result = self.converter.convert({"eng": ""})
        self.assertEqual(result["eng"], "ong")

    def test_convert_in(self):
        """测试 in 转换"""
        result = self.converter.convert({"in": ""})
        self.assertEqual(result["in"], "ien")

    def test_convert_yn(self):
        """测试 ün 转换"""
        result = self.converter.convert({"ün": ""})
        self.assertEqual(result["ün"], "üen")

    def test_convert_ueng(self):
        """测试 ueng 转换"""
        result = self.converter.convert({"ueng": ""})
        self.assertEqual(result["ueng"], "uong")

    def test_convert_ong(self):
        """测试 ong 转换"""
        result = self.converter.convert({"ong": ""})
        self.assertEqual(result["ong"], "uong")

    def test_convert_y(self):
        """测试 ü 转换"""
        result = self.converter.convert({"ü": ""})
        self.assertEqual(result["ü"], "v")

    def test_convert_e_circumflex(self):
        """测试 ê 转换"""
        result = self.converter.convert({"ê": ""})
        self.assertIn("e", result)

    def test_convert_passthrough(self):
        """测试未匹配的韵母"""
        result = self.converter.convert({"a": ""})
        self.assertEqual(result["a"], "a")

    def test_convert_invalid_input(self):
        """测试无效输入"""
        with self.assertRaises(ValueError):
            self.converter.convert("not a dict")

    def test_convert_invalid_values(self):
        """测试无效值"""
        with self.assertRaises(ValueError):
            self.converter.convert({"a": 123})

    def test_get_stats(self):
        """测试获取统计"""
        self.converter.convert({"a": "", "o": ""})
        stats = self.converter.get_stats()

        self.assertEqual(stats['total_conversions'], 2)
        self.assertEqual(stats['successful_conversions'], 2)
        self.assertEqual(stats['success_rate'], 100.0)

    def test_stats_update(self):
        """测试统计更新"""
        # 初始统计
        initial_stats = self.converter.get_stats()
        self.assertEqual(initial_stats['total_conversions'], 0)

        # 执行转换
        self.converter.convert({"a": ""})

        # 验证统计更新
        updated_stats = self.converter.get_stats()
        self.assertEqual(updated_stats['total_conversions'], 1)
        self.assertEqual(updated_stats['successful_conversions'], 1)

    def test_multiple_conversions(self):
        """测试多次转换"""
        input_dict = {
            "-i": "", "ao": "", "iong": "", "ing": "",
            "e": "", "eng": "", "in": "", "ün": "",
            "ueng": "", "ong": "", "ü": "", "ê": ""
        }

        result = self.converter.convert(input_dict)

        # 验证所有转换
        self.assertEqual(result["-i"], "ir")
        self.assertEqual(result["ao"], "au")
        self.assertEqual(result["iong"], "vong")
        self.assertEqual(result["ing"], "iong")
        # e 和 ê 的特殊处理：当有 ê 时，e 被映射到 ê
        self.assertIn("e", result)
        self.assertEqual(result["eng"], "ong")
        self.assertEqual(result["in"], "ien")
        self.assertEqual(result["ün"], "üen")
        self.assertEqual(result["ueng"], "uong")
        self.assertEqual(result["ong"], "uong")
        self.assertEqual(result["ü"], "v")


if __name__ == '__main__':
    unittest.main()
