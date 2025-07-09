# syllable/analysis/segment_analyzer.py
from syllable.analysis.segment.processor import SegmentProcessor
from syllable_analyzer_strategy import SyllableAnalyzerStrategy

class SegmentAnalyzer(SyllableAnalyzerStrategy):
    def __init__(self):
        self._processor = SegmentProcessor()
    
    def analyze(self, syllable):
        return self._processor.process_segments(syllable)