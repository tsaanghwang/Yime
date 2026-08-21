from unicodedata import category


def is_pua_char(ch: str) -> bool:
    cp = ord(ch)
    return (0xE000 <= cp <= 0xF8FF) or (0xF0000 <= cp <= 0xFFFFD) or (0x100000 <= cp <= 0x10FFFD)


def is_allowed_code_char(ch: str) -> bool:
    """
    允许用于自定义音码的字符判定：
    - 先允许 PUA 字符；
    - 排除 Unicode 控制类 (Cc) 与未分配类 (Cn)；
    - 允许其它所有字符（字母/数字/标点/符号等）。
    """
    if not ch or len(ch) != 1:
        return False
    try:
        if is_pua_char(ch):
            return True
    except Exception:
        pass
    cat = category(ch)
    if cat.startswith("C"):
        return False
    return True
