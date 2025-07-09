class ToneMedianCalculator:
    """
    五度标调法调域中值计算器
    1. 计调单个调值中值：
    2. 计算单个调类中值：
    3. 计算整个调系中值：
    """

    @staticmethod
    def calculate_tone_value_median(pitch_levels):
        """
        计算单个调值中值
        :param pitch_levels: 调值列表，如[5,5,5]代表阴平
        :return: 调值中值
        """
        if not pitch_levels:
            raise ValueError("调值列表不能为空")
        return sum(pitch_levels) / len(pitch_levels)

    @staticmethod
    def calculate_tone_category_median(tone_values_medians):
        """
        计算单个调类中值
        :param tone_values_medians: 该调类的多个调值中值列表
        :return: 调类中值
        """
        if not tone_values_medians:
            raise ValueError("调值中值列表不能为空")
        return sum(tone_values_medians) / len(tone_values_medians)

    @staticmethod
    def calculate_tone_system_median(category_medians):
        """
        计算整个调系中值
        :param category_medians: 各调类中值列表
        :return: 调系中值
        """
        if not category_medians:
            raise ValueError("调类中值列表不能为空")
        return sum(category_medians) / len(category_medians)

    @staticmethod
    def calculate_variation_coefficient(values):
        """计算变异系数（标准差/均值）评估离散程度"""
        mean = sum(values) / len(values)
        std_dev = (sum((x - mean)**2 for x in values) / len(values))**0.5
        return std_dev / mean

    # 应用示例
    low_tone_vc = calculate_variation_coefficient(
        [1.33, 4.00, 2.33])  # 上声变异系数
    falling_tone_vc = calculate_variation_coefficient([3.33, 4.00])  # 去声变异系数


# 示例使用
if __name__ == "__main__":
    # 1. 计算各调值中值
    high_tone = ToneMedianCalculator.calculate_tone_value_median([5, 5, 5])  # 阴平
    rising_tone = ToneMedianCalculator.calculate_tone_value_median([
                                                                3, 4, 5])  # 阳平
    low_tone1 = ToneMedianCalculator.calculate_tone_value_median([
                                                                   2, 1, 1])  # 上声1
    low_tone2 = ToneMedianCalculator.calculate_tone_value_median([
                                                                   3, 4, 5])  # 上声2
    low_tone3 = ToneMedianCalculator.calculate_tone_value_median([
                                                                   2, 1, 4])  # 上声3
    falling_tone1 = ToneMedianCalculator.calculate_tone_value_median([
                                                                5, 4, 1])  # 去声1
    falling_tone2 = ToneMedianCalculator.calculate_tone_value_median([
                                                                5, 4, 3])  # 去声2

    print(f"阴平调值中值: {high_tone:.2f}")
    print(f"阳平调值中值: {rising_tone:.2f}")
    print(f"上声1调值中值: {low_tone1:.2f}")
    print(f"上声2调值中值: {low_tone2:.2f}")
    print(f"上声3调值中值: {low_tone3:.2f}")
    print(f"去声1调值中值: {falling_tone1:.2f}")
    print(f"去声2调值中值: {falling_tone2:.2f}")

    # 2. 计算各调类中值
    high_tone_median = ToneMedianCalculator.calculate_tone_category_median([
                                                                         high_tone])
    rising_tone_median = ToneMedianCalculator.calculate_tone_category_median([
                                                                          rising_tone])
    low_tone_median = ToneMedianCalculator.calculate_tone_category_median(
        [low_tone1, low_tone2, low_tone3])
    falling_tone_median = ToneMedianCalculator.calculate_tone_category_median([
                                                                         falling_tone1, falling_tone2])

    print(f"\n阴平调类中值: {high_tone_median:.2f}")
    print(f"阳平调类中值: {rising_tone_median:.2f}")
    print(f"上声调类中值: {low_tone_median:.2f}")
    print(f"去声调类中值: {falling_tone_median:.2f}")

    # 3. 计算调系中值
    system_median = ToneMedianCalculator.calculate_tone_system_median([
        high_tone_median, rising_tone_median, low_tone_median, falling_tone_median
    ])

    print(f"\n调系调域中值: {system_median:.2f}")
