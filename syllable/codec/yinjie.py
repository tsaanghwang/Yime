"""四元模型的兼容入口。

canonical 实现已迁入 ``syllable.codec.model_full_code``；本模块保留旧导入路径。
"""

from __future__ import annotations

try:
    from .model_full_code import GanyinSlots, Yinjie, YunyinSlots
except ImportError:
    from model_full_code import GanyinSlots, Yinjie, YunyinSlots

__all__ = ["GanyinSlots", "Yinjie", "YunyinSlots"]
