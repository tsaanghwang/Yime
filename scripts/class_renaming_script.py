# 在测试文件中添加以下验证
def test_class_renaming():
    from syllable.analysis.slice.yinyuan import UncertainPitchYinyuan
    from syllable.analysis.slice.zaoyin_yinyuan import NoiseYinyuan

    assert UncertainPitchYinyuan.__name__ == "UncertainPitchYinyuan"
    assert NoiseYinyuan.__bases__[0].__name__ == "UncertainPitchYinyuan"
    print("类名重构验证通过")