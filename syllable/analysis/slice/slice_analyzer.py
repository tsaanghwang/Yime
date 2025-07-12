# syllable/analysis/slice/slice_analyzer.py
from syllable_analyzer_strategy import SyllableAnalyzerStrategy
from syllable.analysis.slice.slicer import Slicer

class SliceAnalyzer(SyllableAnalyzerStrategy):
    def __init__(self):
        self._Slicer = Slicer()

    def analyze(self, syllable):
        return self._Slicer.process_slices(syllable)
