import json
import os

# 定义键值对数据
data = {
    "A": "󰌾",  # key: ASCII, value: '󰌾' (U+F033E, Private Use Area)
    "B": "󰎄",  # key: ASCII, value: '󰎄' (U+F0384, Private Use Area)
    "C": "ĉ",   # key: ASCII, value: 'ĉ' (U+0109, Latin Small Letter C with Circumflex)
    "D": "󰎓",   # key: ASCII, value: '󰎓' (U+F0393, Private Use Area)
    "E": "󰍡",  # key: ASCII, value: '󰍡' (U+F0361, Private Use Area)
    "F": "󰍢",  # key: ASCII, value: '󰍢' (U+F0362, Private Use Area)
    "G": "󰎘",  # key: ASCII, value: '󰎘' (U+F0398, Private Use Area)
    "H": "󰎜",  # key: ASCII, value: '󰎜' (U+F039C, Private Use Area)
    "I": "󰌠",   # key: ASCII, value: '󰌠' (U+F0320, Private Use Area)
    "J": "󰌡",   # key: ASCII, value: '󰌡' (U+F0321, Private Use Area)
    "K": "󰎙",  # key: ASCII, value: '󰎙' (U+F0399, Private Use Area)
    "L": "󰍵",  # key: ASCII, value: '󰍵' (U+F0375, Private Use Area)
    "M": "󰎈",  # key: ASCII, value: '󰎈' (U+F0388, Private Use Area)
    "N": "󰎗",   # key: ASCII, value: '󰎗' (U+F0397, Private Use Area)
    "O": "󰍒",  # key: ASCII, value: '󰍒' (U+F0352, Private Use Area)
    "P": "󰎅",  # key: ASCII, value: '󰎅' (U+F0385, Private Use Area)
    "Q": "󰍶",  # key: ASCII, value: '󰍶' (U+F0376, Private Use Area)
    "R": "󰌿",  # key: ASCII, value: '󰌿' (U+F033F, Private Use Area)
    "S": "ŝ",   # key: ASCII, value: 'ŝ' (U+015D, Latin Small Letter S with Circumflex)
    "T": "󰎔",  # key: ASCII, value: '󰎔' (U+F0394, Private Use Area)
    "U": "󰌪",   # key: ASCII, value: '󰌪' (U+F032A, Private Use Area)
    "V": "󰌵",  # key: ASCII, value: '󰌵' (U+F0335, Private Use Area)
    "W": "󰌫",   # key: ASCII, value: '󰌫' (U+F032B, Private Use Area)
    "X": "󰍓",  # key: ASCII, value: '󰍓' (U+F0353, Private Use Area)
    "Y": "󰌴",  # key: ASCII, value: '󰌴' (U+F0334, Private Use Area)
    "Z": "ẑ",   # key: ASCII, value: 'ẑ' (U+1E91, Latin Small Letter Z with Circumflex)
    "a": "󰍂",  # key: ASCII, value: '󰍂' (U+F0342, Private Use Area)
    "b": "b",   # key: ASCII, value: 'b' (U+0062, Latin Small Letter B)
    "c": "c",   # key: ASCII, value: 'c' (U+0063, Latin Small Letter C)
    "d": "d",   # key: ASCII, value: 'd' (U+0064, Latin Small Letter D)
    "e": "󰍥",  # key: ASCII, value: '󰍥' (U+F0365, Private Use Area)
    "f": "f",   # key: ASCII, value: 'f' (U+0066, Latin Small Letter F)
    "g": "g",   # key: ASCII, value: 'g' (U+0067, Latin Small Letter G)
    "h": "h",   # key: ASCII, value: 'h' (U+0068, Latin Small Letter H)
    "i": "󰌤",   # key: ASCII, value: '󰌤' (U+F0324, Private Use Area)
    "j": "j",   # key: ASCII, value: 'j' (U+006A, Latin Small Letter J)
    "k": "k",   # key: ASCII, value: 'k' (U+006B, Latin Small Letter K)
    "l": "l",   # key: ASCII, value: 'l' (U+006C, Latin Small Letter L)
    "m": "m",   # key: ASCII, value: 'm' (U+006D, Latin Small Letter M)
    "n": "n",   # key: ASCII, value: 'n' (U+006E, Latin Small Letter N)
    "o": "󰍖",  # key: ASCII, value: '󰍖' (U+F0356, Private Use Area)
    "p": "p",   # key: ASCII, value: 'p' (U+0070, Latin Small Letter P)
    "q": "q",   # key: ASCII, value: 'q' (U+0071, Latin Small Letter Q)
    "r": "r",   # key: ASCII, value: 'r' (U+0072, Latin Small Letter R)
    "s": "s",   # key: ASCII, value: 's' (U+0073, Latin Small Letter S)
    "t": "t",   # key: ASCII, value: 't' (U+0074, Latin Small Letter T)
    "u": "󰌮",   # key: ASCII, value: '󰌮' (U+F032E, Private Use Area)
    "v": "ŋ",   # key: ASCII, value: 'ŋ' (U+014B, Latin Small Letter Eng)
    "w": "󰍹",  # key: ASCII, value: '󰍹' (U+F0379, Private Use Area)
    "x": "x",   # key: ASCII, value: 'x' (U+0078, Latin Small Letter X)
    "y": "󰌸",  # key: ASCII, value: '󰌸' (U+F0338, Private Use Area)
    "z": "z"    # key: ASCII, value: 'z' (U+007A, Latin Small Letter Z)
}

# 字符校验函数
def check_character(char):
    """检查字符属性并返回结果"""
    code = ord(char)
    is_ascii = code <= 127
    is_pua = (0xE000 <= code <= 0xF8FF) or (0xF0000 <= code <= 0xFFFFD) or (0x100000 <= code <= 0x10FFFD)

    if is_ascii:
        return "ASCII"
    elif is_pua:
        if 0xE000 <= code <= 0xF8FF:
            return "Private Use Area"
        elif 0xF0000 <= code <= 0xFFFFD:
            return "Private Use Area-A"
        elif 0x100000 <= code <= 0x10FFFD:
            return "Private Use Area-B"
    else:
        return f"Non-ASCII (Unicode {hex(code)})"

# 校验data对象中的所有键值对
def validate_data_mapping(data):
    """校验data对象中的所有键值对"""
    print("\n=== 键值对校验结果 ===")
    for key, value in data.items():
        key_result = "ASCII" if ord(key) <= 127 else "Non-ASCII"
        code = ord(value)
        print(f"键 '{key}': {key_result}, 值 '{value}': Unicode {hex(code)}")
    print("====================\n")

# 执行校验
validate_data_mapping(data)

# 统计Private Use Area字符数量
pua_count = sum(1 for value in data.values()
               if (0xE000 <= ord(value) <= 0xF8FF) or
                        (0xF0000 <= ord(value) <= 0xFFFFD) or
                        (0x100000 <= ord(value) <= 0x10FFFD))
print(f"\n=== 统计结果 ===\nPrivate Use Area字符总数: {pua_count} (Private Use Area)\n================\n")

# 定义目录名称
directory = "internal_data"

# 如果目录不存在，则创建目录
if not os.path.exists(directory):
    os.makedirs(directory)

# 定义文件路径
file_path = os.path.join(directory, "key_symbol_mapping.json")

# 保存为 JSON 文件
with open(file_path, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=4)

print(f"JSON 文件已生成：{file_path}")
