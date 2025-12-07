# yinyuan_classifier.py
from tools.yinyuan import Yinyuan

class YinyuanClassifier:
    """音元分类器，用于区分噪音类和乐音类音元"""

    UNPITCHED_YINYUAN_TYPES = ['t', 'ʦ', 's']  # 噪音类音元
    PITCHED_YINYUAN_TYPES = ['i', 'u', 'ʏ', 'ᴀ', 'o', 'ᴇ', 'ʅ', 'ɚ']  # 乐音类音元

    def __init__(self):
        self.yinyuan_dict = {
            'unpitched_yinyuan': {},  # 噪音类音元字典
            'pitched_yinyuan': {}  # 乐音类音元字典
        }

    def classify_yinyuan(self, yinyuan: Yinyuan) -> str:
        """分类音元类型"""
        base_notation = yinyuan._get_base_notation_from_code(yinyuan.code)
        if not base_notation:
            raise ValueError("Invalid Yinyuan code")

        quality = base_notation[0]  # 获取音质部分

        if quality in self.UNPITCHED_YINYUAN_TYPES:
            return 'unpitched_yinyuan'
        elif quality in self.PITCHED_YINYUAN_TYPES:
            return 'pitched_yinyuan'
        else:
            raise ValueError(f"Unknown quality type: {quality}")

    def add_to_dict(self, yinyuan: Yinyuan):
        """将音元添加到对应分类的字典中"""
        yinyuan_type = self.classify_yinyuan(yinyuan)
        self.yinyuan_dict[yinyuan_type][yinyuan.notation] = yinyuan

    def get_combined_dict(self) -> dict:
        """获取合并后的音元字典"""
        return {
            **self.yinyuan_dict['unpitched_yinyuan'],
            **self.yinyuan_dict['pitched_yinyuan']
        }

    @classmethod
    def from_pianyin_list(cls, pianyin_list: list) -> 'YinyuanClassifier':
        """从片音列表创建分类器实例"""
        classifier = cls()
        for pianyin in pianyin_list:
            yinyuan = Yinyuan.from_pianyin(pianyin)
            classifier.add_to_dict(yinyuan)
        return classifier
