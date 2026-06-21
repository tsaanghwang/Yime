# 音节分成首音和干音两段
# 干音分成呼音和韵音两段
# 韵音分成主音和末音两段
# 首音由噪音充当
# 呼音、主音和末音由乐音充当
#  噪音和乐音统称音元
#
# 权威结构定义（禁止改层级、禁止干音=乐音）：docs/TERMINOLOGY_INDEX.md §音节结构

"""音节结构模型（四音元位编解码层）。

本模块的 ``Yinjie`` 描述 **四音元位编码** 下的递归结构树，与音段层 ``syllable.analysis.syllable``
（传统 **声母 / 韵母 + 调段** → **首音段 / 干音段**）分工不同：

+---------------------------+------------------------------------------+
| 层次                      | 模块 / 对象                              |
+===========================+==========================================+
| 音段层（声韵母分析法）    | ``Syllable``, ``Ganyin``                 |
|                           | 首音段 = 声母 + 联结调段                 |
|                           | 干音段 = 韵母 + 联结调段（如 ``ong1``）  |
+---------------------------+------------------------------------------+
| 四音元位层（编解码链）    | 本模块 ``Yinjie``                        |
|                           | 第 1 至第 4 音元位依次存放 首音元 / 呼音元 / 主音元 / 末音元 |
|                           | 干音段在编码上对应 呼音元 + 主音元 + 末音元 |
|                           | 韵音段在编码上对应 主音元 + 末音元        |
|                           | 位内值为 **音元字符**，不是拼音段标签    |
+---------------------------+------------------------------------------+

递归分解（与文件头注释一致）::

    音节 → (首音 + 干音)
    干音 → (呼音 + 韵音)
    韵音 → (主音 + 末音)

``initial`` / ``ascender`` / ``peak`` / ``descender`` 为历史英文字段名，编解码 JSON 仍使用此顺序；
中文说明请优先区分 **结构段**（首音 / 干音 / 呼音 / 韵音 / 主音 / 末音）、
**音元**（首音元 / 呼音元 / 主音元 / 末音元）与 **音元位**（四字符中的第 1 至第 4 位），
不要把“音元位”简写成“音位”，也不要统称为“槽”。
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class YunyinSlots:
    """韵音段：主音 + 末音（峰段 + 峰后段）。"""

    zhuyin: str | None = None
    moyin: str | None = None

    @property
    def peak(self) -> str | None:
        """兼容旧名：主音 / 峰段。"""
        return self.zhuyin

    @property
    def descender(self) -> str | None:
        """兼容旧名：末音 / 峰后段。"""
        return self.moyin

    def as_dict(self) -> dict[str, str | None]:
        return {
            "zhuyin": self.zhuyin,
            "moyin": self.moyin,
            "peak": self.zhuyin,
            "descender": self.moyin,
        }


@dataclass(frozen=True)
class GanyinSlots:
    """干音段内部视图：呼音 + 韵音。"""

    huyin: str | None = None
    yunyin: YunyinSlots | None = None

    @property
    def ascender(self) -> str | None:
        """兼容旧名：呼音 / 峰前段。"""
        return self.huyin

    def as_dict(self) -> dict[str, Any]:
        yunyin_dict = self.yunyin.as_dict() if self.yunyin else None
        return {
            "huyin": self.huyin,
            "yunyin": yunyin_dict,
            "ascender": self.huyin,
            "rime": yunyin_dict,
        }


class Yinjie:
    """
    音节类：四音元位编解码层的递归结构（编解码用）。

    四音元位顺序与 ``yinjie_code.json`` 四字符编码一致::

        [首音元, 呼音元, 主音元, 末音元]

    与 ``Syllable``（声母/韵母音段层）的对应关系见模块 docstring；勿将四位中的音元字符
    与 ``SplitSyllableResult`` 中的首音段 / 干音段拼音标签混为一谈。
    """

    __slots__ = ("initial", "ascender", "peak", "descender")

    def __init__(
        self,
        initial: str | None = None,
        ascender: str | None = None,
        peak: str | None = None,
        descender: str | None = None,
    ):
        """
        参数（历史英文名，编解码保持不变）:

            initial: 首音元 — 填入首音段的噪音类音元字符
            ascender: 呼音元 — 填入呼音段的乐音类音元字符（峰前段）
            peak: 主音元 — 填入主音段的乐音类音元字符（峰段）
            descender: 末音元 — 填入末音段的乐音类音元字符（峰后段）
        """
        self.initial = initial
        self.ascender = ascender
        self.peak = peak
        self.descender = descender

    # --- 术语属性（与 TERMINOLOGY_INDEX / yinjie.py 峰位注释一致）---

    @property
    def shouyin(self) -> str | None:
        """首音元字符（填充首音段）。"""
        return self.initial

    @property
    def huyin(self) -> str | None:
        """呼音元字符（对应呼音段 / 峰前段）。"""
        return self.ascender

    @property
    def zhuyin(self) -> str | None:
        """主音元字符（对应主音段 / 峰段）。"""
        return self.peak

    @property
    def moyin(self) -> str | None:
        """末音元字符（对应末音段 / 峰后段）。"""
        return self.descender

    @property
    def yunyin(self) -> YunyinSlots:
        """韵音段视图：主音 + 末音。"""
        return YunyinSlots(zhuyin=self.peak, moyin=self.descender)

    @property
    def ganyin(self) -> GanyinSlots:
        """干音段视图：呼音 + 韵音。"""
        return GanyinSlots(huyin=self.ascender, yunyin=self.yunyin)

    @property
    def ganyin_code(self) -> str:
        """干音三音元位字符拼接（字符串，非 ``GanyinSlots`` 对象）。"""
        return (self.ascender or "") + (self.peak or "") + (self.descender or "")

    @property
    def rime(self) -> dict[str, str | None]:
        """兼容旧接口：韵音 dict（peak / descender）。"""
        return self.yunyin.as_dict()

    @classmethod
    def from_code(cls, code: str) -> Yinjie:
        """由四字符音元编码串构造（与 ``YinjieDecoder.decode`` 一致）。"""
        if len(code) != 4:
            raise ValueError(f"编码长度应为 4，实际为 {len(code)}: {code!r}")
        return cls(
            initial=code[0],
            ascender=code[1],
            peak=code[2],
            descender=code[3],
        )

    def to_code(self) -> str:
        """导出四字符音元编码串（空位以空字符占位，与历史行为一致）。"""
        return (
            (self.initial or "")
            + (self.ascender or "")
            + (self.peak or "")
            + (self.descender or "")
        )

    def classify_phonemes(self) -> tuple[list[str], list[str]]:
        """
        兼容旧名：按音元类别分出噪音侧与乐音侧字符。

        返回: (zaoyin_chars, yueyin_chars)
        """
        zaoyin_chars: list[str] = []
        yueyin_chars: list[str] = []

        if self.initial:
            zaoyin_chars.append(self.initial)

        for yinyuan_char in (self.ascender, self.peak, self.descender):
            if yinyuan_char:
                yueyin_chars.append(yinyuan_char)

        return zaoyin_chars, yueyin_chars

    def classify_codes(self) -> tuple[list[str], list[str]]:
        """兼容旧名：同 ``classify_phonemes``。"""
        return self.classify_phonemes()

    def get_full_code(self) -> str:
        """兼容旧名：同 ``to_code``。"""
        return self.to_code()

    def get_ganyin_code(self) -> str:
        """干音三音元位拼接字符串。"""
        return self.ganyin_code

    def get_jianyin_code(self) -> str:
        """首音与末音之间的音元（呼音 + 主音）。"""
        return (self.ascender or "") + (self.peak or "")

    def get_yunyin_code(self) -> str:
        """韵音两音元位拼接字符串。"""
        return (self.peak or "") + (self.descender or "")

    def __str__(self) -> str:
        parts: list[str] = []
        if self.initial:
            parts.append(f"首音: {self.initial}")
        if self.ascender:
            parts.append(f"呼音: {self.ascender}")
        if self.peak:
            parts.append(f"主音: {self.peak}")
        if self.descender:
            parts.append(f"末音: {self.descender}")
        return " | ".join(parts)

    def merge_duplicate_phonemes(self) -> Yinjie:
        """
        兼容旧名：合并连续相同的音元，返回新的 Yinjie 实例。

        规则：连续 2 个或 3 个相同音元合并为 1 个。
        """
        yinyuan_chars = [self.initial, self.ascender, self.peak, self.descender]

        merged_yinyuan_chars: list[str] = []
        previous_char: str | None = None
        for yinyuan_char in yinyuan_chars:
            if yinyuan_char is None:
                continue
            if yinyuan_char == previous_char:
                continue
            merged_yinyuan_chars.append(yinyuan_char)
            previous_char = yinyuan_char

        new_initial = merged_yinyuan_chars[0] if len(merged_yinyuan_chars) > 0 else None
        new_ascender = merged_yinyuan_chars[1] if len(merged_yinyuan_chars) > 1 else None
        new_peak = merged_yinyuan_chars[2] if len(merged_yinyuan_chars) > 2 else None
        new_descender = merged_yinyuan_chars[3] if len(merged_yinyuan_chars) > 3 else None

        return Yinjie(
            initial=new_initial,
            ascender=new_ascender,
            peak=new_peak,
            descender=new_descender,
        )
