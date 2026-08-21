"""噪音类片音的细分类。

本模块保留旧类名作为兼容入口；共享的顶层类别由
``syllable.pianyin.ZaoyinPianyin`` 唯一定义。
"""

from typing import Optional

from .pianyin import ZaoyinPianyin


class ClearPianyin(ZaoyinPianyin):
    """不记录音高的清音片音。"""

    def __init__(self, quality: str, duration: str = "", loudness: str = ""):
        super().__init__(
            quality=quality,
            pitch=None,
            duration=duration,
            loudness=loudness,
        )


class VoicedZaoyinPianyin(ZaoyinPianyin):
    """可记录非辨义音高现象的浊辅音片音。"""

    def __init__(self, quality: str, pitch: Optional[str] = None,
                 duration: str = "", loudness: str = ""):
        super().__init__(
            quality=quality,
            pitch=pitch,
            duration=duration,
            loudness=loudness,
        )


# 兼容旧代码。新代码使用 ZaoyinPianyin / VoicedZaoyinPianyin。
UnpitchedPianyin = ZaoyinPianyin
VoicedUnpitchedPianyin = VoicedZaoyinPianyin
