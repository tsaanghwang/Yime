"""
干音分析主程序
功能：连接各个模块并生成最终的ganyin.json文件
"""

import os
import sys
from ganyin_analyzer import GanyinAnalyzer


def main():
    try:
        # 获取当前文件路径
        current_file = os.path.abspath(__file__)

        # 初始化分析器
        analyzer = GanyinAnalyzer(current_file)

        # 执行分析并保存结果
        if analyzer.analyze_and_save():
            print("干音分析完成，结果已保存到 ganyin.json")
            return 0
        else:
            print("干音分析失败", file=sys.stderr)
            return 1

    except Exception as e:
        print(f"发生错误: {str(e)}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
