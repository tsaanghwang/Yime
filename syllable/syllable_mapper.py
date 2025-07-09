class SyllableMapper:
    """音节分析映射器基类"""
    @staticmethod
    def to_other_format(analysis_result):
        """将一种分析结果转换为另一种格式"""
        pass


class OnsetRhymeToSegmentMapper(SyllableMapper):
    @staticmethod
    def to_other_format(onset_rhyme_result):
        # 将声韵母分析结果转换为音段分析格式
        segments = []
        if onset_rhyme_result['onset']:
            segments.append(onset_rhyme_result['onset'])
        segments.extend(onset_rhyme_result['rhyme'])
        return {'segments': segments}


class SegmentToOnsetRhymeMapper(SyllableMapper):
    @staticmethod
    def to_other_format(segment_result):
        # 将音段分析结果转换为声韵母格式
        onset = segment_result['segments'][0] if len(
            segment_result['segments']) > 0 else ''
        rhyme = segment_result['segments'][1:] if len(
            segment_result['segments']) > 1 else []
        return {'onset': onset, 'rhyme': rhyme}
