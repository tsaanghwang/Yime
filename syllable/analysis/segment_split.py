"""首音段 / 干音段切分结果（音段层，对接声韵母分析法）。"""

from __future__ import annotations

from dataclasses import dataclass

try:
    from .syllable import Ganyin, Syllable
except ImportError:
    from syllable import Ganyin, Syllable


def split_ganyin_segment_label(ganyin_label: str) -> tuple[str, str | None]:
    """将干音段标签（如 ``ong1``）拆为韵母与声调数字。"""
    if not ganyin_label:
        return "", None
    if ganyin_label[-1].isdigit():
        return ganyin_label[:-1], ganyin_label[-1]
    return ganyin_label, None


def shouyin_label_to_initial(shouyin_label: str) -> str | None:
    """首音段标签 → 声母（零声母 ``'`` → ``None``）。"""
    if not shouyin_label or shouyin_label == "'":
        return None
    return shouyin_label


@dataclass(frozen=True)
class SegmentSplitResult:
    """音节切分为首音段 / 干音段标签，并可还原 ``Syllable`` / ``Ganyin`` 音段对象。"""

    source: str
    normalized: str
    shouyin_label: str
    ganyin_label: str

    def as_tuple(self) -> tuple[str, str]:
        """兼容 ``analyze_syllable`` 的 ``(首音段, 干音段)`` 元组。"""
        return self.shouyin_label, self.ganyin_label

    def to_syllable(self) -> Syllable:
        """还原声韵母分析法下的 ``Syllable``（声母 / 韵母 / 调）。"""
        final, tone = split_ganyin_segment_label(self.ganyin_label)
        return Syllable(
            initial=shouyin_label_to_initial(self.shouyin_label),
            final=final or None,
            tone=tone,
        )

    def to_ganyin(self) -> Ganyin:
        """还原干音段对象（韵母 + 与韵母联结的调段）。"""
        return Ganyin.from_syllable(self.to_syllable())
