from pathlib import Path
from typing import Any

from .utils_charfilter import is_allowed_code_char, is_pua_char
from syllable_codec.yinjie_decoder import YinjieDecoder

try:
    from yime.syllable_structure import SyllableStructure
except Exception:
    try:
        from syllable_structure import SyllableStructure
    except Exception:
        SyllableStructure = None


def _normalize_split(res):
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
    """兼容壳：复用根级 YinjieDecoder 主实现，并补足旧调用面的辅助方法。"""

    def __init__(self, code_file: str | Path | None = None):
        if code_file is None:
            code_file = Path(__file__).resolve().parents[1] / "syllable_codec" / "yinjie_code.json"
        super().__init__(code_file=code_file)

    def _load_code_map(self) -> dict[str, str]:
        """兼容旧行为：文件不存在或 JSON 无效时返回空映射。"""
        if not self.code_file.exists():
            return {}
        try:
            return super()._load_code_map()
        except Exception:
            return {}

    def _get_code(self, key: str) -> Any:
        """返回与拼音对应的编码（或 None）。"""
        if key in self.code_map:
            return self.code_map[key]
        for _, value in self.code_map.items():
            if value == key:
                return value
        return None

    def split_encoded_syllable(self, encoded: str):
        """统一入口：优先使用 SyllableStructure.split_encoded_syllable，失败时回退本地解析。"""
        if SyllableStructure is not None and hasattr(SyllableStructure, "split_encoded_syllable"):
            try:
                return SyllableStructure.split_encoded_syllable(encoded)
            except Exception:
                pass

        if not encoded:
            raise ValueError("encoded syllable required")

        initial = encoded[0] if len(encoded) > 0 else None
        ganyin = encoded[1:] if len(encoded) > 1 else ""
        ascender = ganyin[0] if len(ganyin) > 0 else None
        yunyin = ganyin[1:] if len(ganyin) > 1 else ""
        peak = yunyin[0] if len(yunyin) > 0 else None
        descender = yunyin[1:] if len(yunyin) > 1 else None

        if SyllableStructure is not None:
            return SyllableStructure(
                initial=initial,
                ascender=ascender,
                peak=peak,
                descender=descender,
            )

        class _S:
            def __init__(self, i, a, p, d):
                self.initial = i
                self.ascender = a
                self.peak = p
                self.descender = d

            def get_full_code(self):
                return ''.join(x for x in (self.initial or '', self.ascender or '', self.peak or '', self.descender or ''))

            def get_ganyin_code(self):
                return (self.ascender or '') + (self.peak or '') + (self.descender or '')

            def get_jianyin_code(self):
                return (self.ascender or '') + (self.peak or '')

            def get_abbreviation(self):
                return (self.initial or '') + ((self.ascender or '')[:1] if (self.ascender or '') else '')

        return _S(initial, ascender, peak, descender)

    def get_ganyin(self, code_or_input: str) -> str:
        """兼容旧接口：返回干音（简化）。"""
        code = self._get_code(code_or_input) or code_or_input
        return (code[0] if code else "") if isinstance(code, str) else ""

    def get_yunyin(self, code_or_input: str) -> str:
        """兼容旧接口：返回韵音（简化）。"""
        code = self._get_code(code_or_input) or code_or_input
        return (code[-1] if code else "") if isinstance(code, str) else ""

    def get_jianyin_code(self, code_or_input: str) -> str:
        """兼容旧接口：返回简拼（非常简单的缩写）。"""
        code = self._get_code(code_or_input) or code_or_input
        if not isinstance(code, str) or not code:
            return ""
        return code[:2]

    @staticmethod
    def run_example():
        """兼容旧示例入口：转发到根级解码器示例入口。"""
        return YinjieDecoder.run_example()


def main() -> None:
    """兼容 CLI 入口：转发到根级解码器示例入口。"""
    YinjieDecoder.run_example()


if __name__ == "__main__":
    main()
