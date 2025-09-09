import json

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

    @staticmethod
    def get_phoneme_key_mapping():
        """
        返回音元到物理按键的默认映射关系
        噪音音元映射到数字键(1-9)
        乐音音元映射到字母键(a-z)
        """
        return {
            # 噪音音元默认映射到数字
            '\U00100000': '1',
            '\U00100001': '2',
            '\U00100002': '3',
            '\U00100003': '4',
            '\U00100004': '5',
            '\U00100005': '6',
            '\U00100006': '7',
            '\U00100007': '8',
            '\U00100008': '9',

            # 乐音音元默认映射到字母
            '\U00100010': 'a',
            '\U00100011': 'b',
            '\U00100012': 'c',
            '\U00100013': 'd',
            '\U00100014': 'e',
            '\U00100015': 'f',
            '\U00100016': 'g',
            '\U00100017': 'h',
            '\U00100018': 'i',
            '\U00100019': 'j',
            '\U00100020': 'k',
            '\U00100021': 'l',
            '\U00100022': 'm',
            '\U00100023': 'n',
            '\U00100024': 'o',
            '\U00100025': 'p',
            '\U00100026': 'q',
            '\U00100027': 'r',
            '\U00100028': 's',
            '\U00100029': 't',
            # 可以继续添加更多映射...
        }
