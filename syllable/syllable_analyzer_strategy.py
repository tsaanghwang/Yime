from syllable_mapper import OnsetRhymeToSegmentMapper, SegmentToOnsetRhymeMapper


class SyllableAnalyzerStrategy:
    def analyze(self, syllable):
        raise NotImplementedError("Subclasses should implement this!")


class OnsetRhymeAnalyzer(SyllableAnalyzerStrategy):
    def analyze(self, syllable):
        # 声韵母分析法实现
        return {'onset': 'b', 'rhyme': ['a', 'n']}


class SegmentAnalyzer(SyllableAnalyzerStrategy):
    def analyze(self, syllable):
        # 音段分析法实现
        return {'segments': ['b', 'a', 'n']}


class Syllable:
    def __init__(self, analyzer: SyllableAnalyzerStrategy):
        self._analyzer = analyzer

    def analyze(self):
        return self._analyzer.analyze(self)

    def convert_to(self, target_format):
        current = self.analyze()
        if isinstance(self._analyzer, OnsetRhymeAnalyzer) and target_format == "segment":
            return OnsetRhymeToSegmentMapper.to_other_format(current)
        elif isinstance(self._analyzer, SegmentAnalyzer) and target_format == "onset_rhyme":
            return SegmentToOnsetRhymeMapper.to_other_format(current)
        return current
