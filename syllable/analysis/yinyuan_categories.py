"""共享的片音 / 音元类别轴。

本模块只表达跨层共享的“噪音 / 乐音”类别，不承载片音到音元的归并规则，
也不承载结构段（首音 / 干音 / 呼音 / 主音 / 末音）信息。
"""

from __future__ import annotations

from enum import Enum


class YinyuanCategory(str, Enum):
    """片音层与音元层共享的类别轴。"""

    ZAOYIN = "zaoyin"
    YUEYIN = "yueyin"


def category_from_legacy_pitch_marker(pitch: object) -> YinyuanCategory:
    """读取旧数据时，把历史 ``pitch`` 标记解释成项目类别。

    这不是分类定义。新对象必须显式声明类别，不能根据是否存在物理音高
    或 ``pitch`` 字段来推断 zaoyin / yueyin。
    """
    if pitch is None or isinstance(pitch, bool):
        return YinyuanCategory.ZAOYIN
    return YinyuanCategory.YUEYIN


# 兼容旧调用；新代码不得依赖这个名称建立分类。
infer_category_from_pitch = category_from_legacy_pitch_marker
