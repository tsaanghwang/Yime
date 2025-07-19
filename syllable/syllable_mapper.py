class SyllableMapper:
    """音节分析映射器基类"""
    @staticmethod
    def to_other_format(analysis_result):
        """将一种分析结果转换为另一种格式"""
        pass


class InitialDivRhymeToSliceMapper(SyllableMapper):
    @staticmethod
    def to_other_format(initial_divrhyme_result):
        # 将声母韵母声调分析结果转换为片音分析格式
        slices = []
        if initial_divrhyme_result['initial']:
            slices.append(initial_divrhyme_result['initial'])
        slices.extend(initial_divrhyme_result['divrhyme'])
        return {'slices': slices}


class SliceToInitialDivRhymeMapper(SyllableMapper):
    @staticmethod
    def to_other_format(slice_result):
        # 将片音分析结果转换为声母韵母声调格式
        initial = slice_result['slices'][0] if len(
            slice_result['slices']) > 0 else ''
        divrhyme = slice_result['slices'][1:] if len(
            slice_result['slices']) > 1 else []
        return {'initial': initial, 'divrhyme': divrhyme}
