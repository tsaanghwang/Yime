"""Public shim for the character-filter helpers."""

from yime.utils.charfilter import is_allowed_code_char, is_pua_char

__all__ = ["is_allowed_code_char", "is_pua_char", "main"]


def main() -> int:
    # 简单测试：a, 中, U+E000 (PUA), 换行
    tests = ['a', '中', '\uE000', '\n']
    for t in tests:
        print(repr(t), is_allowed_code_char(t), is_pua_char(t))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
