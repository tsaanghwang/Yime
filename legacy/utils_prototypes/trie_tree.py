class TrieNode:
    def __init__(self):
        self.children = {}     # dict: symbol -> TrieNode
        self.is_leaf = False   # 标记是否为叶子（完整码）
        self.value = None      # 可选：存码或其它元数据

class Trie:
    def __init__(self):
        self.root = TrieNode()

    def insert(self, code: str, value=None):
        node = self.root
        for ch in code:
            node = node.children.setdefault(ch, TrieNode())
        node.is_leaf = True
        node.value = value if value is not None else code

    def find(self, prefix: str):
        node = self.root
        for ch in prefix:
            node = node.children.get(ch)
            if node is None:
                return None
        return node

    def decode_stream(self, symbols):
        """按符号流解码：逐步走 Trie，遇叶子返回完整码并重置到根"""
        node = self.root
        out = []
        for s in symbols:
            node = node.children.get(s)
            if node is None:
                # 前缀不存在 -> 重置并继续（或抛错，按需定）
                node = self.root
                continue
            if node.is_leaf:
                out.append(node.value)
                node = self.root
        return out

    def collect_codes(self):
        """遍历并返回所有码（按字典序）"""
        res = []
        def dfs(n, path):
            if n.is_leaf:
                res.append(''.join(path))
            for ch in sorted(n.children):
                dfs(n.children[ch], path + [ch])
        dfs(self.root, [])
        return res

    def collect_up_to_level(self, max_level: int):
        """
        收集到指定层级但不继续深入。
        返回字典：
          {
            'upper_leaves': [leaf_value, ...]   # 所有 level < max_level 的叶子值（按 BFS 顺序）
            'level_nodes': [                     # 所有处于 level == max_level 的节点信息（按 BFS 顺序）
                {'prefix': 'prefix到该节点', 'is_leaf': bool, 'children': ['a','b',...]},
                ...
            ]
          }
        语义：不进入第 max_level 的子节点，只收集第 max_level 层节点的 children 列表与 is_leaf 标记。
        """
        from collections import deque
        q = deque([(self.root, 0, "")])
        upper_leaves = []
        level_nodes = []

        while q:
            node, lvl, prefix = q.popleft()
            if lvl < max_level:
                # 收集上层叶子（level < max_level）
                if node.is_leaf and node.value is not None:
                    upper_leaves.append(node.value)
                # 继续向下
                for ch, child in node.children.items():
                    q.append((child, lvl + 1, prefix + ch))
            elif lvl == max_level:
                # 在目标层，收集该节点的基本信息，但不再向下深入
                level_nodes.append({
                    'prefix': prefix,
                    'is_leaf': node.is_leaf,
                    'children': sorted(list(node.children.keys()))
                })
            # 若 lvl > max_level 不会出现，因为我们不把第 max_level 的 children 入队

        return {'upper_leaves': upper_leaves, 'level_nodes': level_nodes}

    def generate_flat_upto_level(self, max_level: int):
        """
        依据 collect_up_to_level 的结果，生成一个扁平字符串：
        - 先按顺序拼接 upper_leaves
        - 然后对每个 level_node:
            * 若 node.is_leaf 为 True，拼接 node.prefix (或 node.value 如果存在)
            * 否则拼接该节点的 children 字符（按字典序）
        返回拼接后的字符串（用于快速检视/解码替代）。
        """
        info = self.collect_up_to_level(max_level)
        parts = []
        parts.extend(info['upper_leaves'])

        for node in info['level_nodes']:
            if node['is_leaf']:
                # 尽量使用 prefix 作代表（若叶子也存 value 可考虑使用 value）
                parts.append(node['prefix'])
            else:
                # 将该层节点的 children 字符合并为一个片段
                parts.append(''.join(node['children']))

        return ''.join(parts)

def decompose_code_to_level(code: str, k: int) -> str:
    """
    将 code 按层分解：
      k = 0 -> 返回原码串（例如 "AbcD"）
      k = 1 -> "A+bcD"
      k = 2 -> "A+b+cD"
      ...
      k = len(code) -> "A+b+c+D"
    k 最大为 len(code)。返回用 '+' 连接的分段字符串。
    """
    if not code:
        return ""
    k = max(0, min(k, len(code)))
    if k == 0:
        return code
    parts = [code[i] for i in range(min(k, len(code)))]
    if k < len(code):
        parts.append(code[k:])
    return '+'.join(parts)

def decompose_all_levels(code: str):
    """返回 code 从层 0 到层 len(code) 的所有分解表示（列表）"""
    return [decompose_code_to_level(code, k) for k in range(0, len(code) + 1)]

# 使用示例与主函数测试
if __name__ == "__main__":
    import sys, traceback
    try:
        t = Trie()
        codes = ["AbcD", "XyZ1", "aAaA", "ZzZz"]
        for c in codes:
            t.insert(c)

        print("All codes:", t.collect_codes())

        # 示例：对每个 code 打印每层分解
        for code in codes:
            print(f"\n分解: {code}")
            for k, s in enumerate(decompose_all_levels(code)):
                print(f" 第 {k} 层: {code} = {s}")

        # 原来的按层 trie 输出（保持不变）
        max_len = max((len(c) for c in codes), default=0)
        print("max_len =", max_len)
        for level in range(0, max_len + 1):
            info = t.collect_up_to_level(level)
            flat = t.generate_flat_upto_level(level)
            print(f"\n=== level {level} ===")
            print(" upper_leaves:", info['upper_leaves'])
            print(" level_nodes:")
            for n in info['level_nodes']:
                print("  ", n)
            print(" flat result:", repr(flat))
        print("Done")
    except Exception:
        print("Script raised an exception:", file=sys.stderr)
        traceback.print_exc()
        sys.exit(1)
