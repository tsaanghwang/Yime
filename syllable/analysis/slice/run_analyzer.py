"""
干音分析主程序
功能：连接各个模块并生成最终的ganyin.json文件
"""

import os
import sys
from ganyin_analyzer import GanyinAnalyzer
from ganyin_categorizer import GanyinCategorizer


def analyze_syllable(syllable: str) -> tuple:
    """
    切分单个音节为首音和干音
    
    参数:
        syllable: 要分析的音节字符串
    
    返回:
        元组 (首音部分, 干音部分)
    """
    # 使用 GanyinCategorizer 的 split_syllable 方法进行切分
    shouyin, ganyin = GanyinCategorizer.split_syllable(syllable)
    
    # 处理特殊音节情况
    if ganyin.startswith('_'):
        # 对于舌尖音后的i，保留_前缀
        return shouyin, ganyin
    elif ganyin in GanyinCategorizer.SPECIAL_SYLLABLES:
        # 处理特殊音节
        return shouyin, GanyinCategorizer.SPECIAL_SYLLABLES[ganyin]
    
    return shouyin, ganyin


def main():
    try:
        # 获取当前文件路径
        current_file = os.path.abspath(__file__)

        # 初始化分析器
        analyzer = GanyinAnalyzer(current_file)

        # 执行分析并保存结果
        if analyzer.analyze_and_save():
            # print("音节分析完成，结果已保存到 shouyin.json和ganyin.json")
            return 0
        else:
            # print("音节分析失败", file=sys.stderr)
            return 1

    except Exception as e:
        print(f"发生错误: {str(e)}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())