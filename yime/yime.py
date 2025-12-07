key_to_code = {
    'a': [0xE001, 0xE002],  # 阴平、阳平
    'n': [0xE003],          # 声母 n
    # ...其他按键
}

code_to_hanzi = {
    (0xE001, 0xE002): [("张", 1000), ("章", 500), ("彰", 50)],  # 码元序列 → 汉字列表
    # ...其他码元组合
}

class CodeTrieNode:
    def __init__(self):
        self.children = {}      # {码元: 子节点}
        self.hanzi = []         # [(汉字, 频率), ...]
        self.is_end = False     # 是否为完整码元序列

# 插入码元序列 "U+E001, U+E002" → "张"
root = CodeTrieNode()
node = root
for code in [0xE001, 0xE002]:
    if code not in node.children:
        node.children[code] = CodeTrieNode()
    node = node.children[code]
node.hanzi = [("张", 1000), ("章", 500), ("彰", 50)]
node.is_end = True

class PinyinTrieNode:
    def __init__(self):
        self.children = {}      # {拼音字符: 子节点}
        self.hanzi = []         # 候选汉字列表 [(汉字, 词频), ...]
        self.is_end = False     # 是否为完整音节

# 示例：插入拼音 "ni" 和对应汉字
root = PinyinTrieNode()
node = root
for char in "ni":
    if char not in node.children:
        node.children[char] = PinyinTrieNode()
    node = node.children[char]
node.hanzi = [("你", 1000), ("尼", 100), ("呢", 50)]  # 按词频排序
node.is_end = True


code_to_pinyin = {
    (0xE001, 0xE002): "zhang",
    (0xE003, 0xE004): "ni",
    # ...其他码元组合
}

bigram_model = {
    (0xE001, 0xE002): {(0xE003, 0xE004): 0.8, (0xE005, 0xE006): 0.5},  # "zhang" 后常接 "ni"
    # ...其他共现概率
}

user_history = {
    (0xE001, 0xE002): {"张": 100, "章": 10},  # 用户偏好 "张"
    # ...其他码元序列
}

def get_code_points_for_key(key):
    return key_to_code.get(key, [])

def rank_candidates(code_sequence, candidates):
    # 结合用户历史和上下文
    if code_sequence in user_history:
        history_freq = {hanzi: freq for hanzi, freq in user_history[code_sequence].items()}
        candidates = sorted(candidates, key=lambda x: history_freq.get(x[0], 0), reverse=True)
    # 若无历史数据，按全局频率排序
    else:
        candidates = sorted(candidates, key=lambda x: -x[1])
    return candidates


# 保护性默认，避免被 import 时抛出 NameError
code_sequence = globals().get("code_sequence", []) or []
try:
    code_tuple = tuple(code_sequence)
except Exception:
    import logging
    logging.getLogger(__name__).warning("code_sequence 无法转为 tuple，回退为空 tuple")
    code_tuple = tuple()

# 把顶层运行逻辑移入函数，防止 import 时执行
def main():
    # 示例输入
    input_keys = ['A', 'B']  # 用户按键
    code_sequence = []
    for key in input_keys:
        code_sequence.extend(get_code_points_for_key(key))

    # 保护性默认：避免模块被 import 时因未定义的 code_sequence/code_tuple 崩溃
    code_sequence = globals().get("code_sequence", []) or []
    try:
        code_tuple = tuple(code_sequence)
    except Exception:
        import logging
        logging.getLogger(__name__).warning("code_sequence 无法转为 tuple，回退为空 tuple")
        code_tuple = tuple()

    candidates = code_to_hanzi.get(code_tuple, [])
    pinyin = code_to_pinyin.get(code_tuple, "")

    ranked_candidates = rank_candidates(code_tuple, candidates)

    # 输出结果
    print("输入码元:", [f"U+{cp:04X}" for cp in code_tuple])
    print(f'拼音提示: "{pinyin}"')
    print("汉字候选:", end=" ")
    if ranked_candidates:
        print("  ".join(f"{i+1}. {hanzi}" for i, (hanzi, _) in enumerate(ranked_candidates)))
    else:
        print("(无候选)")

    print()
    print("输入键击:", " → ".join(input_keys))
    print("码元序列:", [f"U+{cp:04X}" for cp in code_tuple])
    print("拼音提示:", pinyin)
    print("汉字候选:")
    for i, (hanzi, freq) in enumerate(ranked_candidates, 1):
        note = " (用户常用)" if user_history.get(code_tuple, {}).get(hanzi, 0) > 0 else ""
        print(f"{i}. {hanzi}{note}")

    return

if __name__ == "__main__":
    main()
