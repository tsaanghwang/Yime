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
    """
    音节类
    - 切分音节的首音和干音
    - 提取音节的音调和音质
    """

    def __init__(self, initial: str = None, final: str = None, tone: str = None):
        """
        初始化音节对象

        参数:
            initial (str): 声母部分
            final (str): 韵母部分
            tone (str/int): 声调
        """
        self.initial = initial
        self.final = final
        self.tone = tone

        # 调段部分
        self.shoudiao = None  # 与声母联结的调段
        self.gandiao = tone   # 与韵母联结的调段

    @property
    def quality(self):
        """音质层：由声母和韵母组成"""
        return (self.initial, self.final)

    @property
    def shouyin(self):
        """首音：由声母和与其联结的调段构成"""
        return (self.initial, self.shoudiao)

    @property
    def ganyin(self):
        """干音：由韵母和与其联结的调段构成"""
        return (self.final, self.gandiao)

    def tone(self, shoudiao=None, gandiao=None):
        """
        设置调段信息，并返回调段元组

        参数:
            shoudiao: 与声母联结的调段
            gandiao: 与韵母联结的调段
        """
        self.shoudiao = shoudiao
        self.gandiao = gandiao
        return (self.shoudiao, self.gandiao)

    def __str__(self):
        return f"Syllable(initial={self.initial}, final={self.final}, tone={self.tone})"

    def __repr__(self):
        return self.__str__()
