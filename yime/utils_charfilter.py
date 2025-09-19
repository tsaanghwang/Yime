from unicodedata import category

def is_pua_char(ch: str) -> bool:
    cp = ord(ch)
    return (0xE000 <= cp <= 0xF8FF) or (0xF0000 <= cp <= 0xFFFFD) or (0x100000 <= cp <= 0x10FFFD)

def is_allowed_code_char(ch: str) -> bool:
    """
    允许用于你自定义音码的字符判定：
    - 先允许 PUA 字符；
    - 排除 Unicode 控制类 (Cc) 与未分配类 (Cn)；
    - 允许其它所有字符（字母/数字/标点/符号等）。
    """
    if not ch or len(ch) != 1:
        return False
    # 先允许 PUA
    try:
        if is_pua_char(ch):
            return True
    except Exception:
        # ord 可能抛异常（超出范围等），继续按常规处理
        pass
    cat = category(ch)
    # 排除控制字符与未分配（但已排除了 PUA）
    if cat.startswith("C"):
        return False
    # 允许一切其他字符（包括字母、数字、标点等）
    return True

if __name__ == "__main__":
    # 简单测试：a, 中, U+E000 (PUA), 换行
    tests = ['a', '中', '\uE000', '\n']
    for t in tests:
        print(repr(t), is_allowed_code_char(t), is_pua_char(t))
