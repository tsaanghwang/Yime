"""
tone_statistics_analyzer.py
五度标调法调域统计分析工具
增强版：包含数据验证、统计指标计算和加权支持
"""

import math
from typing import List, Optional


class ToneStatisticsAnalyzer:
    """
    五度标调法调域统计分析工具
    提供调值中值、调类中值、调系中值计算，以及调域范围、标准差等统计指标
    """

    MIN_TONE_LEVEL = 1
    MAX_TONE_LEVEL = 5

    @staticmethod
    def validate_pitch_levels(pitch_levels: List[int]) -> None:
        """
        验证五度值是否在有效范围内(1-5)
        :param pitch_levels: 调值列表
        :raises ValueError: 如果调值不在1-5范围内
        """
        if not pitch_levels:
            raise ValueError("调值列表不能为空")

        for level in pitch_levels:
            if not (ToneStatisticsAnalyzer.MIN_TONE_LEVEL <= level <= ToneStatisticsAnalyzer.MAX_TONE_LEVEL):
                raise ValueError(
                    f"五度值必须在{ToneStatisticsAnalyzer.MIN_TONE_LEVEL}-{ToneStatisticsAnalyzer.MAX_TONE_LEVEL}之间，当前值: {level}")

    @staticmethod
    def calculate_tone_value_stats(pitch_levels: List[int], weights: Optional[List[float]] = None) -> dict:
        """
        计算单个调值的统计指标(中值、范围、标准差)
        :param pitch_levels: 调值列表
        :param weights: 可选权重列表(用于加权计算)
        :return: 包含统计指标的字典
        """
        ToneStatisticsAnalyzer.validate_pitch_levels(pitch_levels)

        if weights and len(weights) != len(pitch_levels):
            raise ValueError("权重列表长度必须与调值列表相同")

        n = len(pitch_levels)

        if weights:
            # 加权计算
            weighted_sum = sum(t * w for t, w in zip(pitch_levels, weights))
            total_weight = sum(weights)
            mean = weighted_sum / total_weight

            # 加权标准差
            variance = sum(w * (t - mean)**2 for t,
                           w in zip(pitch_levels, weights)) / total_weight
        else:
            # 普通计算
            mean = sum(pitch_levels) / n
            variance = sum((t - mean)**2 for t in pitch_levels) / n

        return {
            'median': mean,
            'range': max(pitch_levels) - min(pitch_levels),
            'std_dev': math.sqrt(variance),
            'min': min(pitch_levels),
            'max': max(pitch_levels)
        }

    @staticmethod
    def calculate_tone_category_stats(tone_values_stats: List[dict], weights: Optional[List[float]] = None) -> dict:
        """
        计算调类统计指标
        :param tone_values_stats: 该调类的多个调值统计指标列表
        :param weights: 可选权重列表
        :return: 调类统计指标
        """
        if not tone_values_stats:
            raise ValueError("调值统计指标列表不能为空")

        medians = [stat['median'] for stat in tone_values_stats]

        if weights:
            if len(weights) != len(medians):
                raise ValueError("权重列表长度必须与调值统计指标列表相同")

            weighted_sum = sum(m * w for m, w in zip(medians, weights))
            total_weight = sum(weights)
            category_median = weighted_sum / total_weight
        else:
            category_median = sum(medians) / len(medians)

        return {
            'median': category_median,
            'range': max(medians) - min(medians),
            'std_dev': math.sqrt(sum((m - category_median)**2 for m in medians) / len(medians))
        }

    @staticmethod
    def calculate_tone_system_stats(category_stats: List[dict]) -> dict:
        """
        计算调系统计指标
        :param category_stats: 各调类统计指标列表
        :return: 调系统计指标
        """
        if not category_stats:
            raise ValueError("调类统计指标列表不能为空")

        medians = [stat['median'] for stat in category_stats]
        system_median = sum(medians) / len(medians)

        return {
            'median': system_median,
            'range': max(medians) - min(medians),
            'std_dev': math.sqrt(sum((m - system_median)**2 for m in medians) / len(medians))
        }

    @staticmethod
    def calculate_variation_coefficient(values):
        """计算变异系数（标准差/均值）评估离散程度"""
        mean = sum(values) / len(values)
        std_dev = (sum((x - mean)**2 for x in values) / len(values))**0.5
        return std_dev / mean

    # 应用示例
    shangsheng_vc = calculate_variation_coefficient(
        [1.33, 4.00, 2.33])  # 上声变异系数
    qusheng_vc = calculate_variation_coefficient([3.33, 4.00])  # 去声变异系数


# 示例使用
if __name__ == "__main__":
    print("五度标调法调域统计分析示例\n")

    # 1. 计算各调值统计指标
    yinping = ToneStatisticsAnalyzer.calculate_tone_value_stats([5, 5, 5])
    yangping = ToneStatisticsAnalyzer.calculate_tone_value_stats([3, 4, 5])
    shangsheng1 = ToneStatisticsAnalyzer.calculate_tone_value_stats([2, 1, 1])
    shangsheng2 = ToneStatisticsAnalyzer.calculate_tone_value_stats([3, 4, 5])
    shangsheng3 = ToneStatisticsAnalyzer.calculate_tone_value_stats([2, 1, 4])
    qusheng1 = ToneStatisticsAnalyzer.calculate_tone_value_stats([5, 4, 1])
    qusheng2 = ToneStatisticsAnalyzer.calculate_tone_value_stats([5, 4, 3])

    print("=== 调值统计 ===")
    print(
        f"阴平[555]: 中值={yinping['median']:.2f}, 范围={yinping['range']}, 标准差={yinping['std_dev']:.2f}")
    print(
        f"阳平[345]: 中值={yangping['median']:.2f}, 范围={yangping['range']}, 标准差={yangping['std_dev']:.2f}")
    print(
        f"上声1[211]: 中值={shangsheng1['median']:.2f}, 范围={shangsheng1['range']}, 标准差={shangsheng1['std_dev']:.2f}")
    print(
        f"上声2[345]: 中值={shangsheng2['median']:.2f}, 范围={shangsheng2['range']}, 标准差={shangsheng2['std_dev']:.2f}")
    print(
        f"上声3[214]: 中值={shangsheng3['median']:.2f}, 范围={shangsheng3['range']}, 标准差={shangsheng3['std_dev']:.2f}")
    print(
        f"去声1[541]: 中值={qusheng1['median']:.2f}, 范围={qusheng1['range']}, 标准差={qusheng1['std_dev']:.2f}")
    print(
        f"去声2[543]: 中值={qusheng2['median']:.2f}, 范围={qusheng2['range']}, 标准差={qusheng2['std_dev']:.2f}")

    # 2. 计算各调类统计指标
    yinping_stats = ToneStatisticsAnalyzer.calculate_tone_category_stats([
                                                                         yinping])
    yangping_stats = ToneStatisticsAnalyzer.calculate_tone_category_stats([
                                                                          yangping])
    shangsheng_stats = ToneStatisticsAnalyzer.calculate_tone_category_stats(
        [shangsheng1, shangsheng2, shangsheng3])
    qusheng_stats = ToneStatisticsAnalyzer.calculate_tone_category_stats([
                                                                         qusheng1, qusheng2])

    print("\n=== 调类统计 ===")
    print(
        f"阴平: 中值={yinping_stats['median']:.2f}, 范围={yinping_stats['range']:.2f}, 标准差={yinping_stats['std_dev']:.2f}")
    print(
        f"阳平: 中值={yangping_stats['median']:.2f}, 范围={yangping_stats['range']:.2f}, 标准差={yangping_stats['std_dev']:.2f}")
    print(
        f"上声: 中值={shangsheng_stats['median']:.2f}, 范围={shangsheng_stats['range']:.2f}, 标准差={shangsheng_stats['std_dev']:.2f}")
    print(
        f"去声: 中值={qusheng_stats['median']:.2f}, 范围={qusheng_stats['range']:.2f}, 标准差={qusheng_stats['std_dev']:.2f}")

    # 3. 计算调系统计指标
    system_stats = ToneStatisticsAnalyzer.calculate_tone_system_stats([
        yinping_stats, yangping_stats, shangsheng_stats, qusheng_stats
    ])

    print("\n=== 调系统计 ===")
    print(f"调系中值: {system_stats['median']:.2f}")
    print(f"调域范围: {system_stats['range']:.2f}")
    print(f"标准差: {system_stats['std_dev']:.2f}")
