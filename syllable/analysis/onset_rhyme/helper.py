# syllable/analysis/onset_rhyme/helper.py
class OnsetRhymeAnalysisHelper:
    """声韵母分析辅助类，封装复杂分析逻辑"""

    def perform_analysis(self, syllable):
        """
        执行实际的声韵母分析
        :param syllable: 待分析的音节对象
        :return: 分析结果字典 {'onset': str, 'rhyme': list}
        """
        # 这里实现具体的分析逻辑
        # 示例实现：
        return {
            'onset': syllable[0] if len(syllable) > 0 else '',
            'rhyme': list(syllable[1:]) if len(syllable) > 1 else []
        }
