# 可以添加以下验证代码
def test_renaming():
    from syllable.analysis.slice.yinyuan import UncertainPitchYinyuan
    from syllable.analysis.slice.zaoyin_yinyuan import NoiseYinyuan

    assert issubclass(NoiseYinyuan, UncertainPitchYinyuan)
    assert UncertainPitchYinyuan.__name__ == "UncertainPitchYinyuan"