class SyllableMapper:
    """音节分析映射器基类"""
    @staticmethod
    def to_other_format(analysis_result):
        """将一种分析结果转换为另一种格式"""
        pass


class OnsetRhymeToSliceMapper(SyllableMapper):
    @staticmethod
    def to_other_format(onset_rhyme_result):
        # 将声母韵母声调分析结果转换为片音分析格式
        slices = []
        if onset_rhyme_result['onset']:
            slices.append(onset_rhyme_result['onset'])
        slices.extend(onset_rhyme_result['rhyme'])
        return {'slices': slices}


class SliceToOnsetRhymeMapper(SyllableMapper):
    @staticmethod
    def to_other_format(slice_result):
        # 将片音分析结果转换为声母韵母声调格式
        onset = slice_result['slices'][0] if len(
            slice_result['slices']) > 0 else ''
        rhyme = slice_result['slices'][1:] if len(
            slice_result['slices']) > 1 else []
        return {'onset': onset, 'rhyme': rhyme}
