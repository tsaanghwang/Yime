"""
定义一个音节类，用于提取音节的特征
1. 音节的声调（Tone）和音质（Quality）
2. 音质层的声母（Initial）和韵母（Final）
3. 音调层的与声母联结的调段和与韵母联结的调段
4. 音节的首音和干音：
- 首音（Initial）指由声母和与其联结的调段构成的音段，实际就是声母（Initial consonant）
- 干音（Rest）指由韵母和与其联结的调段构成的音段，实际就是带调韵母(声调与韵母构成的音段 （Final with tone））
"""


class Syllable:
    def __init__(self, initial=None, final=None, tone=None):
        """
        初始化音节对象

        参数:
            initial (str): 声母部分
            final (str): 韵母部分
            tone (str/int): 声调
        """
        self.initial = initial  # 声母
        self.final = final      # 韵母
        self.tone = tone        # 声调

        # 调段部分
        self.initial_tone_segment = None  # 与声母联结的调段
        self.final_tone_segment = None    # 与韵母联结的调段

    @property
    def quality(self):
        """音质层：由声母和韵母组成"""
        return (self.initial, self.final)

    @property
    def initial_segment(self):
        """首音：由声母和与其联结的调段构成"""
        return (self.initial, self.initial_tone_segment)

    @property
    def rest_segment(self):
        """干音：由韵母和与其联结的调段构成"""
        return (self.final, self.final_tone_segment)

    def set_tone_segments(self, initial_tone=None, final_tone=None):
        """
        设置调段信息

        参数:
            initial_tone: 与声母联结的调段
            final_tone: 与韵母联结的调段
        """
        self.initial_tone_segment = initial_tone
        self.final_tone_segment = final_tone

    def __str__(self):
        return f"Syllable(initial={self.initial}, final={self.final}, tone={self.tone})"

    def __repr__(self):
        return self.__str__()
