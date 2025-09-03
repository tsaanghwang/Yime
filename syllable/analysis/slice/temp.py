import unicodedata

# 基础字符和声调符号
BASE_CHARS = ['i', 'u', 'ü', 'a', 'o', 'e', 'ê', '_i', 'er', 'm', 'n', 'ng']
TONE_MARKS = {
    '\u0304': '̄',  # 高调
    '\u0301': '́',  # 升调
    '\u030C': '̌',  # 低调
    '\u0300': '̀',  # 降调
    '': ''         # 中性调(轻声调)
}
TONE_ORDER = ['\u0304', '\u0301', '\u030C', '\u0300', '']

# 预组合字符及其主字符映射
PRECOMPOSED_CHARS = {
    'ê': ('e', '\u0302'),  # 'ê' = 'e' + '\u0302'
    'ü': ('u', '\u0308'),  # 'ü' = 'u' + '\u0308'
}

def get_base_and_tone(char):
    """
    返回字符的主字符和调号：
    - 如果是预组合字符（如 'ê'），返回其主字符和默认调号（如 'e' + '\u0302'）。
    - 如果是复合字符（如 '_i'、'er'、'ng'），返回主字符和调号位置。
    """
    if char in PRECOMPOSED_CHARS:
        main_char, default_tone = PRECOMPOSED_CHARS[char]
        return (main_char, default_tone)
    elif char == '_i':
        return ('i', None, 1)  # 调号标在 'i' 上（索引 1）
    elif char == 'er':
        return ('e', None, 0)  # 调号标在 'e' 上（索引 0）
    elif char == 'ng':
        return ('n', None, 0)  # 调号标在 'n' 上（索引 0）
    else:
        return (char, None, 0)  # 单一字符，调号标在字符上

def normalize_char(char, tone_mark):
    """
    规范化字符并标调：
    - 如果是预组合字符（如 'ê'），优先使用预组合带调字符（如 'ế' = 'e' + '\u0301' 的预组合形式）。
    - 否则按分解形式标调。
    """
    if char in PRECOMPOSED_CHARS:
        main_char, default_tone = PRECOMPOSED_CHARS[char]
        if tone_mark:
            # 尝试构造带调的预组合字符（如 'e' + '\u0301' → 'é'）
            composed = unicodedata.normalize('NFC', main_char + tone_mark)
            if composed != main_char + tone_mark:  # 如果存在预组合形式
                return composed
            else:
                return main_char + tone_mark  # 否则用分解形式
        else:
            return char  # 无声调时直接返回原字符
    elif char == '_i':
        return '_i'[:1] + (tone_mark if tone_mark else '') + '_i'[1:]
    elif char == 'er':
        return 'e' + (tone_mark if tone_mark else '') + 'r'
    elif char == 'ng':
        return 'n' + (tone_mark if tone_mark else '') + 'g'
    else:
        return char + (tone_mark if tone_mark else '')

def compose_decomposed_chars():
    """生成所有基础字符与声调符号的分解组合（NFD形式）"""
    decomposed_chars = []
    for base in BASE_CHARS:
        main_info = get_base_and_tone(base)
        if len(main_info) == 2:  # 预组合字符（如 'ê'）
            main_char, default_tone = main_info
            for tone in TONE_ORDER:
                if tone:
                    normalized = normalize_char(base, tone)
                    decomposed_chars.append(normalized)
                else:
                    decomposed_chars.append(base)
        else:  # 复合字符（如 '_i'、'er'）
            main_char, _, tone_pos = main_info
            for tone in TONE_ORDER:
                if base == '_i':
                    decomposed_chars.append('_i'[:1] + (tone if tone else '') + '_i'[1:])
                elif base == 'er':
                    decomposed_chars.append('e' + (tone if tone else '') + 'r')
                elif base == 'ng':
                    decomposed_chars.append('n' + (tone if tone else '') + 'g')
                else:
                    decomposed_chars.append(main_char + (tone if tone else ''))
    return decomposed_chars

def sort_decomposed_chars(chars):
    """按自定义顺序排序"""
    base_order = {char: idx for idx, char in enumerate(BASE_CHARS)}
    tone_order = {tone: idx for idx, tone in enumerate(TONE_ORDER)}

    def sort_key(char):
        # 处理预组合字符（如 'ê'）
        if char in PRECOMPOSED_CHARS:
            main_char, _ = PRECOMPOSED_CHARS[char]
            base_idx = base_order.get(main_char, float('inf'))
            tone_idx = tone_order.get('', float('inf'))  # 默认无声调
            return (base_idx, tone_idx)
        # 处理复合字符（如 'er'、'ng'）
        elif char.startswith('e') and len(char) > 1 and char.endswith('r'):
            main_char = 'e'
            tone = char[1:-1] if len(char) > 2 else ''
            base_idx = base_order.get('er', float('inf'))
            tone_idx = tone_order.get(tone, float('inf'))
            return (base_idx, tone_idx)
        elif char.startswith('n') and len(char) > 1 and char.endswith('g'):
            main_char = 'n'
            tone = char[1:-1] if len(char) > 2 else ''
            base_idx = base_order.get('ng', float('inf'))
            tone_idx = tone_order.get(tone, float('inf'))
            return (base_idx, tone_idx)
        # 简单字符
        else:
            if len(char) > 1:
                main_char = char[0]
                tone = char[1:]
            else:
                main_char = char
                tone = ''
            base_idx = base_order.get(main_char, float('inf'))
            tone_idx = tone_order.get(tone, float('inf'))
            return (base_idx, tone_idx)

    return sorted(chars, key=sort_key)

# 生成并排序分解字符
decomposed_chars = compose_decomposed_chars()
sorted_chars = sort_decomposed_chars(decomposed_chars)

# 打印排序后的结果
print("按自定义顺序排序的分解字符（NFD形式）：")
for char in sorted_chars:
    print(char)

# 检查 'ê' 和 'ü' 是否为预组合字符
print("\n预组合字符检查：")
for char in ['ê', 'ü']:
    nfd = unicodedata.normalize('NFD', char)
    print(f"'{char}' 的 NFD 分解形式: {nfd} (码点: {[hex(ord(c)) for c in nfd]})")
    if len(nfd) > 1:
        print(f"'{char}' 是预组合字符，可分解为 '{nfd[0]}' + '{nfd[1:]}'")
    else:
        print(f"'{char}' 不是预组合字符")
