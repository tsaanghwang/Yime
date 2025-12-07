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
            'rime': self.rime  # 引用新定义的rime属性
        }

    @property
    def rime(self):
        """韵音部分，由主音和末音组成"""
        return {
            'peak': self.peak,
            'descender': self.descender
        }

    def classify_phonemes(self):
        """
        分类音元为噪音和乐音
        返回: (noise_phonemes, musical_phonemes)
        """
        noise_phonemes = []
        musical_phonemes = []

        if self.initial:
            noise_phonemes.append(self.initial)

        if self.ascender:
            musical_phonemes.append(self.ascender)

        if self.peak:
            musical_phonemes.append(self.peak)

        if self.descender:
            musical_phonemes.append(self.descender)

        return noise_phonemes, musical_phonemes

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

    def merge_duplicate_phonemes(self):
        """
        合并连续相同的音元，返回新的Yinjie实例
        规则：连续2个或3个相同音元合并为1个
        """
        # 获取当前所有音元
        phonemes = [
            self.initial,  # 首音
            self.ascender,  # 呼音
            self.peak,  # 主音
            self.descender  # 末音
        ]

        # 合并连续相同的音元
        merged_phonemes = []
        prev_phoneme = None
        for phoneme in phonemes:
            if phoneme is None:
                continue
            if phoneme == prev_phoneme:
                continue  # 跳过连续相同的音元
            merged_phonemes.append(phoneme)
            prev_phoneme = phoneme

        # 根据合并后的音元创建新实例
        # 注意：这里假设合并后的音元顺序与原始结构一致
        # 可能需要根据实际业务逻辑调整
        new_initial = merged_phonemes[0] if len(merged_phonemes) > 0 else None
        new_ascender = merged_phonemes[1] if len(merged_phonemes) > 1 else None
        new_peak = merged_phonemes[2] if len(merged_phonemes) > 2 else None
        new_descender = merged_phonemes[3] if len(merged_phonemes) > 3 else None

        return Yinjie(
            initial=new_initial,
            ascender=new_ascender,
            peak=new_peak,
            descender=new_descender
        )
