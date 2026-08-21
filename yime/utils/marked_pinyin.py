from __future__ import annotations

import unicodedata

ACCENTED_VOWEL_MAP: dict[str, tuple[str, int]] = {
    "ā": ("a", 1),
    "á": ("a", 2),
    "ǎ": ("a", 3),
    "à": ("a", 4),
    "ē": ("e", 1),
    "é": ("e", 2),
    "ě": ("e", 3),
    "è": ("e", 4),
    "ḗ": ("ê", 2),
    "ế": ("ê", 2),
    "ề": ("ê", 4),
    "ī": ("i", 1),
    "í": ("i", 2),
    "ǐ": ("i", 3),
    "ì": ("i", 4),
    "ō": ("o", 1),
    "ó": ("o", 2),
    "ǒ": ("o", 3),
    "ò": ("o", 4),
    "ū": ("u", 1),
    "ú": ("u", 2),
    "ǔ": ("u", 3),
    "ù": ("u", 4),
    "ǖ": ("ü", 1),
    "ǘ": ("ü", 2),
    "ǚ": ("ü", 3),
    "ǜ": ("ü", 4),
    "ń": ("n", 2),
    "ň": ("n", 3),
    "ǹ": ("n", 4),
    "ḿ": ("m", 2),
}

SPECIAL_COMBINING_TONES: dict[str, tuple[str, int]] = {
    "ê̄": ("ê", 1),
    "ê̌": ("ê", 3),
    "ề": ("ê", 4),
    "m̄": ("m", 1),
    "m̌": ("m", 3),
    "m̀": ("m", 4),
    "n̄": ("n", 1),
    "ň": ("n", 3),
    "ǹ": ("n", 4),
    "n̄g": ("ng", 1),
    "ňg": ("ng", 3),
    "ǹg": ("ng", 4),
    "hm̄": ("hm", 1),
    "hm̌": ("hm", 3),
    "hm̀": ("hm", 4),
    "hn̄": ("hn", 1),
    "hň": ("hn", 3),
    "hǹ": ("hn", 4),
    "hn̄g": ("hng", 1),
    "hňg": ("hng", 3),
    "hǹg": ("hng", 4),
}


def marked_syllable_to_numeric(syllable: str) -> str:
    syllable = unicodedata.normalize("NFC", syllable.strip().lower())
    if syllable == "r":
        # 《汉语拼音方案》允许儿化后的 er 省写为 r；编码边界恢复完整音节。
        return "er5"
    special = SPECIAL_COMBINING_TONES.get(syllable)
    if special is not None:
        return f"{special[0]}{special[1]}"

    tone = 5
    base_chars: list[str] = []
    for char in syllable:
        mapped = ACCENTED_VOWEL_MAP.get(char)
        if mapped is None:
            base_chars.append(char)
            continue
        base, tone = mapped
        base_chars.append(base)

    base_syllable = "".join(base_chars).lower().replace("u:", "ü")
    if not base_syllable:
        return base_syllable
    return f"{base_syllable}{tone}"


def marked_pinyin_to_numeric(marked_pinyin: str) -> str:
    syllables = [segment for segment in marked_pinyin.strip().split() if segment]
    return " ".join(marked_syllable_to_numeric(segment) for segment in syllables)
