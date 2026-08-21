from __future__ import annotations


def standardize_numeric_pinyin(pinyin: str) -> str:
    """将兼容输入法式数字拼音规范为主链标准数字拼音。"""
    text = str(pinyin or "").strip()
    if not text:
        return text

    body = text[:-1] if text[-1].isdigit() else text
    suffix = text[-1] if text[-1].isdigit() else ""

    normalized: list[str] = []
    for index, char in enumerate(body):
        if char != "v":
            normalized.append(char)
            continue

        previous = body[index - 1].lower() if index > 0 else ""
        if previous in {"j", "q", "x", "y"}:
            normalized.append("u")
        else:
            normalized.append("ü")

    return "".join(normalized) + suffix
