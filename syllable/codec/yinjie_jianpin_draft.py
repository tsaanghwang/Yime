"""音元简拼草稿（未完成，非 IME 输入链）。

完整三条简拼规则（虚首音省略、干音去重、同音质中调省略）见
``tools/generate_efficiency_baseline_report.py``；将来统一迁入
``syllable.codec.yinjie_jianpin``。当前仅保留干音内部相邻音元重复合并，供历史
调用面与测试占位。
"""

from __future__ import annotations

from syllable.codec.yinjie import Yinjie
from syllable.codec.yinjie_loose_split import split_loose_encoded_string


def simplify_ganyin_repeats(full_code: str | list[str] | tuple[str, ...] | None) -> str:
    """将全拼码串化简为草稿简拼（仅合并干音部分相邻重复音元）。"""
    if full_code is None:
        return ""

    if isinstance(full_code, (list, tuple)):
        seq = [str(x) for x in full_code]
    else:
        seq = list(str(full_code))

    if not seq:
        return ""

    if len(seq) == 4:
        head = seq[0]
        ganyin_seq = seq[1:4]
        has_head = True
    elif len(seq) == 3:
        head = None
        ganyin_seq = seq[0:3]
        has_head = False
    else:
        head = seq[0] if len(seq) > 1 else None
        ganyin_seq = seq[1:] if len(seq) > 1 else []
        has_head = head is not None

    simple_ganyin: list[str] = []
    prev: str | None = None
    for item in ganyin_seq:
        if prev is not None and item == prev:
            continue
        simple_ganyin.append(item)
        prev = item

    parts: list[str] = []
    if has_head and head is not None:
        parts.append(str(head))
    parts.extend(str(x) for x in simple_ganyin)
    return "".join(parts)


def simplify_loose_structure(yinjie: Yinjie) -> Yinjie:
    """全拼化简后再按宽松规则切回 ``Yinjie``（草稿简拼，非四码 canonical）。"""
    simplified = simplify_ganyin_repeats(yinjie.to_code())
    return split_loose_encoded_string(simplified)
