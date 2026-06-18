"""干音段编码为三槽乐音音元（呼 / 主 / 末）的结构化结果。"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class GanyinYinyuanSlots:
    """干音段 → 呼音 / 主音 / 末音 三槽音元字符（对应 ``Yinjie`` 的后三槽）。"""

    ganyin_label: str
    huyin: str
    zhuyin: str
    moyin: str

    @property
    def combined(self) -> str:
        """与 ``GanyinEncoder.encode_ganyin`` 返回值一致的三字符串。"""
        return self.huyin + self.zhuyin + self.moyin

    def as_dict(self) -> dict[str, str]:
        return {
            "ganyin_label": self.ganyin_label,
            "huyin": self.huyin,
            "zhuyin": self.zhuyin,
            "moyin": self.moyin,
            "呼音": self.huyin,
            "主音": self.zhuyin,
            "末音": self.moyin,
        }
