import math


def calculate_speech_pentatonic_value(f_current, f_min, f_max):
    """
    计算话语调域五度值
    :param f_current: 当前语音频率值(Hz)
    :param f_min: 话语调域最低频率值(Hz)
    :param f_max: 话语调域最高频率值(Hz)
    :return: 五度值(1-5)
    :raises ValueError: 如果输入参数无效
    """
    # 验证输入参数
    if f_min <= 0 or f_max <= 0 or f_current <= 0:
        raise ValueError("频率值必须大于0")
    if f_min >= f_max:
        raise ValueError("最低频率必须小于最高频率")
    if f_current < f_min or f_current > f_max:
        raise ValueError("当前频率必须在调域范围内")

    # 计算五度值
    log_range = math.log(f_max) - math.log(f_min)
    position = (math.log(f_current) - math.log(f_min)) / log_range
    pentatonic_value = 1 + 4 * position  # 映射到1-5范围

    return pentatonic_value


def analyze_speech_range(speech_samples):
    """
    分析语音样本，获取调域范围
    :param speech_samples: 语音频率样本列表(Hz)
    :return: (f_min, f_max) 调域范围
    :raises ValueError: 如果样本数据无效
    """
    if not speech_samples:
        raise ValueError("语音样本不能为空")

    return min(speech_samples), max(speech_samples)


# 示例使用
if __name__ == "__main__":
    # 示例1: 已知调域范围
    try:
        f_min = 85   # 正常话语调域最低值示例(Hz)
        f_max = 255  # 正常话语调域最高值示例(Hz)
        current_pitch = 194  # 当前语音频率

        result = calculate_speech_pentatonic_value(current_pitch, f_min, f_max)
        print(f"五度值: {result:.2f}")
    except ValueError as e:
        print(f"计算错误: {e}")

    # 示例2: 从语音样本分析
    try:
        speech_samples = [85, 112, 148, 194, 255]  # 实际语音频率样本
        f_min, f_max = analyze_speech_range(speech_samples)

        for sample in speech_samples:
            result = calculate_speech_pentatonic_value(sample, f_min, f_max)
            print(f"频率 {sample}Hz 的五度值: {result:.2f}")
    except ValueError as e:
        print(f"分析错误: {e}")
