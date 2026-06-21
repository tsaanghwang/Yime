"""早期可变长编码串切分（非 ``yinjie_code.json`` 固定四码语义）。

生产编解码与 IME 查词请使用 ``Yinjie.from_code`` / ``Yinjie.to_code``。
本模块仅保留历史演示与 compat 解码器用的宽松切分。
"""

from __future__ import annotations

from syllable.codec.yinjie import Yinjie


def split_loose_encoded_string(encoded_syllable: str) -> Yinjie:
    """将任意非空编码串按首音 + 干音 + 韵音层次切分为 ``Yinjie``。

    ``descender`` 字段可能包含多个字符（``yunyin[1:]`` 剩余段），与固定四音元位不同。
    """
    if not encoded_syllable:
        raise ValueError("编码音节不能为空")

    initial = encoded_syllable[0]
    ganyin = encoded_syllable[1:]
    ascender = ganyin[0] if ganyin else None
    yunyin = ganyin[1:]
    peak = yunyin[0] if yunyin else None
    descender = yunyin[1:] if len(yunyin) > 1 else None

    return Yinjie(
        initial=initial,
        ascender=ascender,
        peak=peak,
        descender=descender,
    )


def from_legacy_pinyin_chars(pinyin: str) -> Yinjie:
    """按字符索引切分拼音串（早期 demo 遗留，不是音元编码语义）。"""
    return Yinjie(
        initial=pinyin[0] if len(pinyin) > 0 else None,
        ascender=pinyin[1] if len(pinyin) > 1 else None,
        peak=pinyin[2] if len(pinyin) > 2 else None,
        descender=pinyin[3] if len(pinyin) > 3 else None,
    )
