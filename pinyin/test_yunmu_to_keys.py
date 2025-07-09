import pytest
from pinyin.yunmu_to_keys import YunmuConverter
from pinyin.constants import YunmuConstants

def test_conversion_rules():
    """测试所有转换规则"""
    converter = YunmuConverter()
    constants = YunmuConstants()

    # 创建包含所有必需韵母的完整字典
    full_yunmu_dict = {k: "" for k in constants.REQUIRED_FINALS}

    # 测试完整字典转换
    result = converter.convert(full_yunmu_dict)

    # 调整断言条件，考虑FRONT_E和E_CIRCUMFLEX的特殊处理
    expected_length = len(full_yunmu_dict) - 1  # 因为E_CIRCUMFLEX不会出现在结果中
    assert len(result) == expected_length

    # 验证所有其他韵母都被正确转换
    for yunmu in full_yunmu_dict:
        if yunmu != constants.E_CIRCUMFLEX:
            assert yunmu in result


def test_invalid_input():
    """测试无效输入"""
    converter = YunmuConverter()

    # 测试非字典输入
    with pytest.raises(TypeError):
        converter.convert("not a dict")

    # 测试缺少必要韵母
    with pytest.raises(ValueError):
        converter.convert({"a": "", "o": ""})

    # 测试非字符串键值
    with pytest.raises(ValueError):
        converter.convert({1: 2, "a": "b"})


def test_statistics():
    """测试统计功能"""
    converter = YunmuConverter()
    constants = YunmuConstants()
    full_yunmu_dict = {k: "" for k in constants.REQUIRED_FINALS}
    converter.convert(full_yunmu_dict)

    stats = converter.get_stats()
    assert stats["total_conversions"] == len(full_yunmu_dict)
    assert stats["failed_conversions"] == 0
    assert stats["success_rate"] == 100.0
    assert "DefaultRulesPlugin" in stats["plugin_stats"]
    assert len(stats["rule_stats"]) > 0
