"""``yime.syllable_decoder`` — 主链 ``syllable.codec.yinjie_decoder`` 的兼容入口。

关联关系：

- **编解码真源**：``syllable.codec.yinjie_decoder.YinjieDecoder``
- **结构模型**：``syllable.codec.yinjie.Yinjie``
- **本模块**：``SyllableDecoder`` 继承 ``YinjieDecoder``，仅保留旧脚本需要的
  宽容码表加载（缺失 JSON → 空映射）与历史方法名（``split_encoded_syllable`` 等）

新代码请直接使用 ``from syllable.codec.yinjie_decoder import YinjieDecoder``。
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

try:
    from yime.utils.charfilter import is_allowed_code_char, is_pua_char
except Exception:
    from utils_charfilter import is_allowed_code_char, is_pua_char

from syllable.codec.paths import YINJIE_CODE_PATH
from syllable.codec.yinjie import Yinjie
from syllable.codec.yinjie_decoder import (
    DEFAULT_PHONEME_REPORT,
    YinjieDecoder,
    YinjieDecoderRunResult,
)


def _normalize_split(res: object) -> tuple | None:
    """把不同实现的返回值归一化为 (initial, None, (ascender,yunyin), (peak,descender))。"""
    if not res:
        return None
    if isinstance(res, (list, tuple)):
        if len(res) == 4:
            return tuple(res)
        if len(res) >= 3:
            initial = res[0]
            third = res[2] if len(res) > 2 else ("", "")
            fourth = res[3] if len(res) > 3 else ("", "")
            return (initial, None, tuple(third), tuple(fourth))
    return None


def is_pua_string(s: str) -> bool:
    """判断是否全由 PUA 字符构成（仅用于区分 PUA，不据此拒绝其它编码）。"""
    return bool(s) and all(is_pua_char(ch) for ch in s)


def is_valid_encoded_string(s: str) -> bool:
    """允许任意非控制字符；使用统一判定函数以兼容自定义音码。"""
    return bool(s) and all(is_allowed_code_char(ch) for ch in s)


class SyllableDecoder(YinjieDecoder):
    """``YinjieDecoder`` 兼容子类：历史 import 名，行为委托主链实现。"""

    def __init__(self, code_file: str | Path | None = None):
        super().__init__(code_file or YINJIE_CODE_PATH)

    def _load_code_map(self) -> dict[str, str]:
        """兼容旧行为：文件不存在或 JSON 无效时返回空映射。"""
        if not self.code_file.exists():
            return {}
        try:
            return super()._load_code_map()
        except Exception:
            return {}

    def _get_code(self, key: str) -> Any:
        """兼容旧名：同 ``resolve_code``。"""
        return self.resolve_code(key)

    def split_encoded_syllable(self, encoded: str) -> Yinjie:
        """兼容旧名：同 ``YinjieDecoder.split_encoded_string``。"""
        return self.split_encoded_string(encoded)

    def get_ganyin(self, code_or_input: str) -> str:
        """兼容旧接口：返回干音（简化）。"""
        code = self.resolve_code(code_or_input) or code_or_input
        return (code[0] if code else "") if isinstance(code, str) else ""

    def get_yunyin(self, code_or_input: str) -> str:
        """兼容旧接口：返回韵音（简化）。"""
        code = self.resolve_code(code_or_input) or code_or_input
        return (code[-1] if code else "") if isinstance(code, str) else ""

    def get_jianyin_code(self, code_or_input: str) -> str:
        """兼容旧接口：返回简拼（非常简单的缩写）。"""
        code = self.resolve_code(code_or_input) or code_or_input
        if not isinstance(code, str) or not code:
            return ""
        return code[:2]

    @staticmethod
    def run_example() -> YinjieDecoderRunResult:
        """兼容旧示例入口：转发到主链 ``YinjieDecoder.run_example``。"""
        return YinjieDecoder.run_example()


def main() -> None:
    """CLI 入口：与 ``syllable.codec.yinjie_decoder.main`` 相同。"""
    YinjieDecoder.run_example()


__all__ = [
    "DEFAULT_PHONEME_REPORT",
    "SyllableDecoder",
    "YinjieDecoder",
    "YinjieDecoderRunResult",
    "_normalize_split",
    "is_pua_string",
    "is_valid_encoded_string",
    "main",
]


if __name__ == "__main__":
    main()
