"""干音分析 CLI 入口，统一复用当前分析器实现。"""

import os
import sys

from tools.syllable_analysis.ganyin_analyzer import GanyinAnalyzer


def main():
    try:
        current_file = os.path.abspath(__file__)
        analyzer = GanyinAnalyzer(current_file)
        if analyzer.analyze_and_save():
            return 0
        return 1

    except Exception as error:
        print(f"发生错误: {str(error)}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
