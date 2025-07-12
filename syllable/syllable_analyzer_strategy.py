from syllable_mapper import OnsetRhymeToSliceMapper, SliceToOnsetRhymeMapper


class SyllableAnalyzerStrategy:
    def analyze(self, syllable):
        raise NotImplementedError("Subclasses should implement this!")


class OnsetRhymeAnalyzer(SyllableAnalyzerStrategy):
    def analyze(self, syllable):
        # 声韵分析法实现
        return {'onset': 'b', 'rhyme': ['a', 'n']}


class SliceAnalyzer(SyllableAnalyzerStrategy):
    def analyze(self, syllable):
        # 片音分析法实现
        return {'slices': ['b', 'a', 'n']}


class Syllable:
    def __init__(self, analyzer: SyllableAnalyzerStrategy):
        self._analyzer = analyzer

    def analyze(self):
        return self._analyzer.analyze(self)

    def convert_to(self, target_format):
        current = self.analyze()
        if isinstance(self._analyzer, OnsetRhymeAnalyzer) and target_format == "slice":
            return OnsetRhymeToSliceMapper.to_other_format(current)
        elif isinstance(self._analyzer, SliceAnalyzer) and target_format == "onset_rhyme":
            return SliceToOnsetRhymeMapper.to_other_format(current)
        return current
