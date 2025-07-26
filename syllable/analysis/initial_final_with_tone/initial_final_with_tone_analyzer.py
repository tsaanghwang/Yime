# syllable/analysis/initial_final_with_tone/initial_final_with_tone_analyzer.py
from .analysis_executor import InitialFinalWithToneAnalysisExecutor
from syllable.syllable_analyzer_strategy import SyllableAnalyzerStrategy


class InitialFinalWithToneAnalyzer(SyllableAnalyzerStrategy):
    def __init__(self):
        self._helper = InitialFinalWithToneAnalysisExecutor()
        if not self._helper.analyze_pinyin_file():
            raise RuntimeError("Failed to initialize pinyin analysis data")

    def analyze(self, syllable):
        # 直接使用预处理好的数据进行分析
        return self._helper.perform_analysis(syllable)
