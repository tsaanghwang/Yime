"""汉语音节音系分析与音元编解码包。

生产编解码见 ``syllable.codec``；音系组件与试验见 ``syllable.analysis``。
包级说明见 ``syllable/README.md``。
"""

from .analysis.syllable import Ganyin, Syllable
from .analysis.syllable_categorizer import SyllableCategorizer
from .analysis.syllable_analyzer import YinjieAnalyzer

__all__ = ["Syllable", "Ganyin", "SyllableCategorizer", "YinjieAnalyzer"]
