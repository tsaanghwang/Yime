# syllable/analysis/initial_divrhyme/initial_divisional_rhyme_analyzer.py
from .helper import InitialDivisionalRhymeAnalysisExecutor
from syllable.syllable_analyzer_strategy import SyllableAnalyzerStrategy


class InitialDivisionalRhymeAnalyzer(SyllableAnalyzerStrategy):
    def __init__(self):
        self._helper = InitialDivisionalRhymeAnalysisExecutor()
        if not self._helper.analyze_pinyin_file():
            raise RuntimeError("Failed to initialize pinyin analysis data")

    def analyze(self, syllable):
        # 直接使用预处理好的数据进行分析
        return self._helper.perform_analysis(syllable)
