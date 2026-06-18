# 音节分成首音和干音两段
# 干音分成呼音和韵音两段
# 韵音分成主音和末音两段
# 首音由噪音充当
# 呼音、主音和末音由乐音充当
#  噪音和乐音统称音元
#
# 权威结构定义（禁止改层级、禁止干音=乐音）：docs/TERMINOLOGY_INDEX.md §音节结构

"""音节结构模型（音元槽位层）。

本模块的 ``Yinjie`` 描述 **四槽音元编码** 下的递归结构树，与音段层 ``syllable.analysis.syllable``
（传统 **声母 / 韵母 + 调段** → **首音段 / 干音段**）分工不同：

+---------------------------+------------------------------------------+
| 层次                      | 模块 / 对象                              |
+===========================+==========================================+
| 音段层（声韵母分析法）    | ``Syllable``, ``Ganyin``                 |
|                           | 首音段 = 声母 + 联结调段                 |
|                           | 干音段 = 韵母 + 联结调段（如 ``ong1``）  |
+---------------------------+------------------------------------------+
| 音元槽位层（编解码链）    | 本模块 ``Yinjie``                        |
|                           | 首音槽 ← 噪音类音元                      |
|                           | 干音槽 → 呼音槽 + 韵音槽 → 主音 + 末音   |
|                           | 槽内值为 **音元字符**，不是拼音段标签    |
+---------------------------+------------------------------------------+

递归分解（与文件头注释一致）::

    音节 → (首音 + 干音)
    干音 → (呼音 + 韵音)
    韵音 → (主音 + 末音)

``initial`` / ``ascender`` / ``peak`` / ``descender`` 为历史英文字段名，编解码 JSON 仍使用此顺序；
请优先使用术语属性 ``shouyin`` / ``huyin`` / ``zhuyin`` / ``moyin`` 阅读结构。
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class YunyinSlots:
    """韵音槽：主音 + 末音（峰段 + 峰后段）。"""

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
    """干音槽：呼音 + 韵音。"""

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
    音节类：音元槽位层的递归结构（编解码用）。

    四槽顺序与 ``yinjie_code.json`` 四字符编码一致::

        [首音槽, 呼音槽, 主音槽, 末音槽]

    与 ``Syllable``（声母/韵母音段层）的对应关系见模块 docstring；勿将槽内音元字符
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

            initial: 首音槽 — 噪音类音元
            ascender: 呼音槽 — 乐音类音元（峰前段）
            peak: 主音槽 — 乐音类音元（峰段）
            descender: 末音槽 — 乐音类音元（峰后段）
        """
        self.initial = initial
        self.ascender = ascender
        self.peak = peak
        self.descender = descender

    # --- 术语属性（与 TERMINOLOGY_INDEX / yinjie.py 峰位注释一致）---

    @property
    def shouyin(self) -> str | None:
        """首音槽（填充首音段的音元）。"""
        return self.initial

    @property
    def huyin(self) -> str | None:
        """呼音槽（峰前段）。"""
        return self.ascender

    @property
    def zhuyin(self) -> str | None:
        """主音槽（峰段）。"""
        return self.peak

    @property
    def moyin(self) -> str | None:
        """末音槽（峰后段）。"""
        return self.descender

    @property
    def yunyin(self) -> YunyinSlots:
        """韵音槽：主音 + 末音。"""
        return YunyinSlots(zhuyin=self.peak, moyin=self.descender)

    @property
    def ganyin(self) -> GanyinSlots:
        """干音槽：呼音 + 韵音。"""
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
        """导出四字符音元编码串（空槽以空字符占位，与历史行为一致）。"""
        return (
            (self.initial or "")
            + (self.ascender or "")
            + (self.peak or "")
            + (self.descender or "")
        )

    def classify_phonemes(self) -> tuple[list[str], list[str]]:
        """
        分类音元为噪音和乐音。
        返回: (noise_phonemes, musical_phonemes)
        """
        noise_phonemes: list[str] = []
        musical_phonemes: list[str] = []

        if self.initial:
            noise_phonemes.append(self.initial)

        for slot in (self.ascender, self.peak, self.descender):
            if slot:
                musical_phonemes.append(slot)

        return noise_phonemes, musical_phonemes

    def classify_codes(self) -> tuple[list[str], list[str]]:
        """兼容旧名：同 ``classify_phonemes``。"""
        return self.classify_phonemes()

    def get_full_code(self) -> str:
        """兼容旧名：同 ``to_code``。"""
        return self.to_code()

    def get_ganyin_code(self) -> str:
        """干音三槽拼接字符串。"""
        return self.ganyin_code

    def get_jianyin_code(self) -> str:
        """首音与末音之间的音元（呼音 + 主音）。"""
        return (self.ascender or "") + (self.peak or "")

    def get_yunyin_code(self) -> str:
        """韵音两槽拼接字符串。"""
        return (self.peak or "") + (self.descender or "")

    def __str__(self) -> str:
        parts = []
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
        合并连续相同的音元，返回新的 Yinjie 实例。
        规则：连续 2 个或 3 个相同音元合并为 1 个。
        """
        phonemes = [self.initial, self.ascender, self.peak, self.descender]

        merged_phonemes: list[str] = []
        prev_phoneme: str | None = None
        for phoneme in phonemes:
            if phoneme is None:
                continue
            if phoneme == prev_phoneme:
                continue
            merged_phonemes.append(phoneme)
            prev_phoneme = phoneme

        new_initial = merged_phonemes[0] if len(merged_phonemes) > 0 else None
        new_ascender = merged_phonemes[1] if len(merged_phonemes) > 1 else None
        new_peak = merged_phonemes[2] if len(merged_phonemes) > 2 else None
        new_descender = merged_phonemes[3] if len(merged_phonemes) > 3 else None

        return Yinjie(
            initial=new_initial,
            ascender=new_ascender,
            peak=new_peak,
            descender=new_descender,
        )
