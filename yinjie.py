# 音节分成首音和干音两段
# 干音分成呼音和韵音两段
# 韵音分成主音和末音两段
# 首音由噪音充当
# 呼音、主音和末音由乐音充当
#  噪音和乐音统称音元

class Yinjie:
    """
    音节类，表示汉语音节的层次结构：
    - 首音(噪音)
    - 干音
      - 呼音(乐音)
      - 韵音
        - 主音(乐音)
        - 末音(乐音)
    """

    def __init__(self, initial=None, ascender=None, peak=None, descender=None):
        """
        初始化音节对象

        参数:
            initial: 首音(噪音)
            ascender: 呼音(乐音)
            peak: 主音(乐音)
            descender: 末音(乐音)
        """
        self.initial = initial  # 首音(音节的首段)
        self.ascender = ascender    # 呼音(韵音、干音和音节的呼段——峰前段)
        self.peak = peak  # 主音(韵音、干音和音节的主段——峰值段)
        self.descender = descender        # 末音(韵音、干音和音节的末段——峰后段)

    @property
    def ganyin(self):
        """干音部分，由呼音和韵音组成"""
        return {
            'ascender': self.ascender,
            'rime': {
                'peak': self.peak,
                'descender': self.descender
            }
        }

    def __str__(self):
        """返回音节的字符串表示"""
        parts = []
        if self.initial:
            parts.append(f"首音: {self.initial}")
        if self.ascender:
            parts.append(f"呼音: {self.ascender}")
        if self.peak:
            parts.append(f"主音: {self.peak}")
        if self.descender:
            parts.append(f"末音: {self.descender}")
        return " | ".join(parts)