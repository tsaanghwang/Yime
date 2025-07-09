import math


def calculate_pentatonic_value(f, f_min, f_max):
    """
    计算调域五度值
    :param f: 当前频率值(Hz)
    :param f_min: 频率最小值(Hz)
    :param f_max: 频率最大值(Hz)
    :return: 五度值(1-5)
    """
    if f_min <= 0 or f_max <= 0 or f <= 0:
        raise ValueError("频率值必须大于0")
    if f < f_min or f > f_max:
        raise ValueError("当前频率必须在最小和最大频率范围内")

    numerator = math.log(f) - math.log(f_min)
    denominator = math.log(f_max) - math.log(f_min)
    pentatonic_value = 5 * (numerator / denominator)

    return pentatonic_value


# 示例参数
f_max = 202        # 最大频率
f_min = 101        # 最小频率
f_current = 202    # 当前频率

# 计算五度值
try:
    result = calculate_pentatonic_value(f_current, f_min, f_max)
    print(f"五度值为: {result:.2f}")
except ValueError as e:
    print(f"计算错误: {e}")

# 示例参数
f_max = 202        # 最大频率
f_min = 101        # 最小频率
f_current = 175.8    # 当前频率

# 计算五度值
try:
    result = calculate_pentatonic_value(f_current, f_min, f_max)
    print(f"五度值为: {result:.2f}")
except ValueError as e:
    print(f"计算错误: {e}")

# 示例参数
f_max = 202        # 最大频率
f_min = 101        # 最小频率
f_current = 153    # 当前频率

# 计算五度值
try:
    result = calculate_pentatonic_value(f_current, f_min, f_max)
    print(f"五度值为: {result:.2f}")
except ValueError as e:
    print(f"计算错误: {e}")

# 示例参数
f_max = 202        # 最大频率
f_min = 101        # 最小频率
f_current = 133.3    # 当前频率

# 计算五度值
try:
    result = calculate_pentatonic_value(f_current, f_min, f_max)
    print(f"五度值为: {result:.2f}")
except ValueError as e:
    print(f"计算错误: {e}")

# 示例参数
f_max = 202        # 最大频率
f_min = 101        # 最小频率
f_current = 116    # 当前频率

# 计算五度值
try:
    result = calculate_pentatonic_value(f_current, f_min, f_max)
    print(f"五度值为: {result:.2f}")
except ValueError as e:
    print(f"计算错误: {e}")
