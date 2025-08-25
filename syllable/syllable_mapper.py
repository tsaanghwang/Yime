class SyllableMapper:
    """音节分析映射器基类"""
    @staticmethod
    def to_other_format(analysis_result):
        """将一种分析结果转换为另一种格式"""
        pass


class InitialFinalWithToneToSliceMapper(SyllableMapper):
    @staticmethod
    def to_other_format(initial_final_with_tone_result):
        # 将声母韵母声调分析结果转换为片音分析格式
        slices = []
        if initial_final_with_tone_result['initial']:
            slices.append(initial_final_with_tone_result['initial'])
        slices.extend(initial_final_with_tone_result['final_with_tone'])
        return {'slices': slices}


class SliceToInitialFinalWithToneMapper(SyllableMapper):
    @staticmethod
    def to_other_format(slice_result):
        # 将片音分析结果转换为声母韵母声调格式
        initial = slice_result['slices'][0] if len(
            slice_result['slices']) > 0 else ''
        final_with_tone = slice_result['slices'][1:] if len(
            slice_result['slices']) > 1 else []
        return {'initial': initial, 'final_with_tone': final_with_tone}
