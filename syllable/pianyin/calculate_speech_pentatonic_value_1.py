import math


def sigmoid(x, center=0.5, steepness=10):
    """Sigmoid函数实现平滑过渡"""
    return 1 / (1 + math.exp(-steepness * (x - center)))


def calculate_speech_pentatonic_value(f_current, f_min, f_max, gender=None):
    """
    计算符合五声调式五度制映射的话语调域五度值(改进版)
    改进点:
    - 使用Sigmoid函数实现平滑过渡
    - 增加性别参数适应不同基频范围

    规则: 
    - 使用对数划分，更符合五声调式的频率感知特性
    - 通过Sigmoid函数实现五度值之间的平滑过渡
    - 性别参数可调整划分边界(默认无差别)

    :param f_current: 当前语音频率值(Hz)
    :param f_min: 话语调域最低频率值(Hz)
    :param f_max: 话语调域最高频率值(Hz)
    :param gender: 性别参数('male'/'female'/None)，用于调整划分边界
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

    # 计算对数位置(更符合人耳对音高的感知)
    log_min = math.log(f_min)
    log_max = math.log(f_max)
    log_current = math.log(f_current)
    position = (log_current - log_min) / (log_max - log_min)

    # 根据性别调整划分边界(女声整体偏高，男声整体偏低)
    if gender == 'female':
        boundaries = [0.15, 0.35, 0.55, 0.75]  # 女声边界调整
    elif gender == 'male':
        boundaries = [0.25, 0.45, 0.65, 0.85]  # 男声边界调整
    else:
        boundaries = [0.20, 0.40, 0.60, 0.80]  # 默认边界

    # 使用Sigmoid函数计算各度数的权重
    w5 = sigmoid(position, boundaries[3])  # 5度权重
    w4 = sigmoid(position, boundaries[2]) - w5  # 4度权重
    w3 = sigmoid(position, boundaries[1]) - (w5 + w4)  # 3度权重
    w2 = sigmoid(position, boundaries[0]) - (w5 + w4 + w3)  # 2度权重
    w1 = 1 - (w5 + w4 + w3 + w2)  # 1度权重

    # 加权计算最终五度值
    return 1 * w1 + 2 * w2 + 3 * w3 + 4 * w4 + 5 * w5


# 示例使用
if __name__ == "__main__":
    # 示例参数
    f_min = 100  # 最低频率(Hz)
    f_max = 400  # 最高频率(Hz)

    # 测试不同频率点
    test_frequencies = [100, 120, 150, 200, 250, 300, 350, 400]

    print("默认(无性别参数):")
    for freq in test_frequencies:
        try:
            result = calculate_speech_pentatonic_value(freq, f_min, f_max)
            print(f"频率 {freq}Hz 的五度值: {result:.2f}")
        except ValueError as e:
            print(f"频率 {freq}Hz 计算错误: {e}")

    print("\n女声:")
    for freq in test_frequencies:
        try:
            result = calculate_speech_pentatonic_value(
                freq, f_min, f_max, 'female')
            print(f"频率 {freq}Hz 的五度值: {result:.2f}")
        except ValueError as e:
            print(f"频率 {freq}Hz 计算错误: {e}")

    print("\n男声:")
    for freq in test_frequencies:
        try:
            result = calculate_speech_pentatonic_value(
                freq, f_min, f_max, 'male')
            print(f"频率 {freq}Hz 的五度值: {result:.2f}")
        except ValueError as e:
            print(f"频率 {freq}Hz 计算错误: {e}")
