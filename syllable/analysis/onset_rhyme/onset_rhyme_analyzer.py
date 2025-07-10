# syllable/analysis/onset_rhyme/onset_rhyme_analyzer.py
from syllable.syllable_analyzer_strategy import SyllableAnalyzerStrategy
from .helper import OnsetRhymeAnalysisHelper


class OnsetRhymeAnalyzer(SyllableAnalyzerStrategy):
    def __init__(self):
        self._helper = OnsetRhymeAnalysisHelper()
        if not self._helper.analyze_pinyin_file():
            raise RuntimeError("Failed to initialize pinyin analysis data")

    def analyze(self, syllable):
        # 直接使用预处理好的数据进行分析
        return self._helper.perform_analysis(syllable)
