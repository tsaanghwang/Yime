"""
定义音节类
功能：切分音节的首音和干音
要求：
1. 提取音节的声调(Tone)和音质(Quality)
2. 提取音质层的声母(Initial)和韵母(Final)
3. 提取音调层的与声母联结的调段和与韵母联结的调段
4. 切分音节的首音和干音：
- 首音(Shouyin)指由声母和与其联结的调段构成的音段，实际就是声母(Initial consonant)
- 干音(Ganyin)指由韵母和与其联结的调段构成的音段，实际就是带调韵母(声调与韵母构成的音段 (Final with tone))
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
        self.shouyin_de_tone  = None  # 首音的音调 = 与声母联结的调段
        self.ganyin_de_tone  = None  # 干音的音调 = 与韵母联结的调段

    @property
    def quality(self):
        """音质层：由声母和韵母组成"""
        return (self.initial, self.final)

    @property
    def first_segment(self):
        """首音：由声母和与其联结的调段构成"""
        return (self.initial, self.shouyin_de_tone )

    @property
    def rest_segment(self):
        """干音：由韵母和与其联结的调段构成"""
        return (self.final, self.ganyin_de_tone )

    def set_tone_segments(self, first_tonal_segment=None, rest_tonal_segment=None):
        """
        设置调段信息

        参数:
            first_tonal_segment: 与声母联结的调段
            rest_tonal_segment: 与韵母联结的调段
        """
        self.shouyin_de_tone  = first_tonal_segment
        self.ganyin_de_tone  = rest_tonal_segment
    def __str__(self):
        return f"Syllable(initial={self.initial}, final={self.final}, tone={self.tone})"

    def __repr__(self):
        return self.__str__()
