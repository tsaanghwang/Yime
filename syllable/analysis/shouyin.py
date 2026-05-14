"""
定义首音类
功能：表示音节的首音
要求：
导入音节类对首音的定义：首音由韵母和与其联结的调段构成，即 Shouyin = Initial_Segment = Initial +Shoudiao
"""


class Shouyin():
    def __init__(self, initial, shoudiao: str = None):
        self.initial = initial
        self.shoudiao = shoudiao

    def __str__(self):
        return self.initial + self.shoudiao


class Initial(Shouyin):
    pass
