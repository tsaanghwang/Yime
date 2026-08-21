"""输入省键层的中调省略规则。

这一层不改变变长音元码与字词的映射关系，只提供输入时可归一化的省键形式。
"""

from __future__ import annotations

from typing import Any, Mapping


def omit_middle_tone_if_same_quality_run(
    symbols: list[str],
    ganyin_symbol_metadata: Mapping[str, Mapping[str, Any]],
) -> tuple[list[str], bool]:
    """对同音质高-中-低或低-中-高三连乐音执行省中调化简。"""
    if len(symbols) != 3:
        return list(symbols), False

    meta = [ganyin_symbol_metadata.get(symbol) for symbol in symbols]
    if not all(item is not None for item in meta):
        return list(symbols), False

    quality_groups = {int(item["quality_group"]) for item in meta}
    tone_pattern = [str(item["tone_level"]) for item in meta]
    if len(quality_groups) != 1:
        return list(symbols), False
    if tone_pattern not in (["high", "mid", "low"], ["low", "mid", "high"]):
        return list(symbols), False

    return [symbols[0], symbols[2]], True


__all__ = ["omit_middle_tone_if_same_quality_run"]
