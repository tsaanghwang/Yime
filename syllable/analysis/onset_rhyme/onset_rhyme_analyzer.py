# syllable/analysis/onset_rhyme_analyzer.py
from syllable.syllable_analyzer_strategy import SyllableAnalyzerStrategy
from .helper import OnsetRhymeAnalysisHelper  # 在onset_rhyme_analyzer.py中使用


class OnsetRhymeAnalyzer(SyllableAnalyzerStrategy):
    def __init__(self):
        self._helper = OnsetRhymeAnalysisHelper()  # 复杂逻辑放在辅助类中

    def analyze(self, syllable):
        return self._helper.perform_analysis(syllable)
