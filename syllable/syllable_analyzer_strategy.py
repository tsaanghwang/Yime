from syllable_mapper import InitialFinalWithToneToSliceMapper, SliceToInitialFinalWithToneMapper


class SyllableAnalyzerStrategy:
    def analyze(self, syllable):
        raise NotImplementedError("Subclasses should implement this!")


class InitialFinalWithToneAnalyzer(SyllableAnalyzerStrategy):
    def analyze(self, syllable):
        # 声母等韵分析法实现
        return {'initial': 'b', 'final_with_tone': ['a', 'n']}


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
        if isinstance(self._analyzer, InitialFinalWithToneAnalyzer) and target_format == "slice":
            return InitialFinalWithToneToSliceMapper.to_other_format(current)
        elif isinstance(self._analyzer, SliceAnalyzer) and target_format == "initial_final_with_tone":
            return SliceToInitialFinalWithToneMapper.to_other_format(current)
        return current
