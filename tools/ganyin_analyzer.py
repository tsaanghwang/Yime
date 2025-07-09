"""GanyinAnalyzer模块，用于分析干音特征"""

class GanyinAnalyzer:
    """干音分析器类"""
    
    def __init__(self):
        pass
        
    def analyze(self, ganyin):
        """分析干音特征"""
        return {
            "components": ganyin.components,
            "tone": ganyin.tone
        }