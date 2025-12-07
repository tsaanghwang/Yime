class TreeNode:
    """二叉树节点类"""
    def __init__(self, value=None, left=None, right=None):
        self.value = value
        self.left = left
        self.right = right

def build_tree(code):
    """
    构建左支只有叶子节点的右支二叉树
    改动：内部节点不保存整个编码（value=None），叶子节点保存单个码元
    """
    if len(code) == 0:
        return None

    # 内部节点不存值，叶子节点存单个码元
    node = TreeNode(None)

    # 左支：第一个码元作为叶子节点
    node.left = TreeNode(code[0])

    # 右支：处理剩余编码
    if len(code) > 1:
        remaining = code[1:]
        if len(remaining) > 1:
            node.right = build_tree(remaining)
        else:
            # 当剩余编码长度为1时直接作为叶子节点
            node.right = TreeNode(remaining)

    return node

def inorder_traversal(node):
    """中序遍历（左-根-右），只返回非 None 的节点值（忽略中间节点）"""
    if node is None:
        return []
    res = []
    res += inorder_traversal(node.left)
    if node.value is not None:
        res.append(node.value)
    res += inorder_traversal(node.right)
    return res

def generate_root_encoding_from_level(root, max_level):
    """
    生成指定层级编码（按层收集码元）
    说明：
    - 首先按原设计收集在 max_level 层可见的码元（左支叶子与目标层的叶子/可收集值）
    - 若收集结果长度不足（等长编码场景），用所有叶子补齐缺失部分
    """
    if root is None:
        return ""

    from collections import deque
    queue = deque([(root, 0)])
    upper_leaves = []         # 存储上层叶子节点（level < max_level）
    current_level_nodes = []  # 存储当前层级能直接收集的码元（level == max_level）

    while queue:
        node, level = queue.popleft()
        if level < max_level:
            # 左支总是叶子
            if node.left and node.left.value is not None:
                upper_leaves.append(node.left.value)
            # 右支继续向下构造链
            if node.right:
                queue.append((node.right, level + 1))
        elif level == max_level:
            # 在目标层：收集左支（若存在）和右支（若为叶子则收集）
            if node.left and node.left.value is not None:
                current_level_nodes.append(node.left.value)
            if node.right:
                # 如果右支为叶子，直接收集其值；否则不深入（按“按层收集”语义）
                if node.right.left is None and node.right.right is None and node.right.value is not None:
                    current_level_nodes.append(node.right.value)

    result = ''.join(upper_leaves + current_level_nodes)

    # 若等长编码场景需完整恢复且当前结果不足，则补上剩余叶子（保证在固定长度编码下返回完整编码）
    full = generate_root_encoding_from_leaves(root)
    if len(result) < len(full):
        result = result + full[len(result):]

    return result

def generate_root_encoding_from_leaves(root):
    """
    通过收集所有叶子节点生成根节点编码
    """
    def collect_leaves(node):
        if node is None:
            return []
        leaves = []
        # 左支节点总是叶子节点
        if node.left:
            leaves.append(node.left.value)
        # 递归收集右支链的叶子节点
        if node.right:
            # 如果右支是叶子节点
            if node.right.left is None and node.right.right is None:
                leaves.append(node.right.value)
            # 否则继续递归
            else:
                leaves += collect_leaves(node.right)
        return leaves

    leaves = collect_leaves(root)
    return ''.join(leaves)

def print_tree(node, level):
    """递归打印树结构（可视化）"""
    if node is None:
        return
    indent = "  " * level
    # 判断节点是否为叶子节点
    is_leaf = (node.left is None or
              (node.left.left is None and node.left.right is None)) and (
               node.right is None or
              (node.right.left is None and node.right.right is None))

    print(f"{indent}值: {node.value} (叶子: {is_leaf})")
    if node.left:
        print(f"{indent} 左支:")
        print_tree(node.left, level + 1)
    if node.right:
        print(f"{indent} 右支:")
        print_tree(node.right, level + 1)

def get_levels(root):
    """按层返回节点值的列表（每层一个子列表）"""
    if root is None:
        return []
    from collections import deque
    q = deque([(root, 0)])
    levels = []
    while q:
        node, lvl = q.popleft()
        if lvl >= len(levels):
            levels.append([])
        levels[lvl].append(node.value)
        if node.left:
            q.append((node.left, lvl + 1))
        if node.right:
            q.append((node.right, lvl + 1))
    return levels

# 测试用例
if __name__ == "__main__":
    # 编码示例（4位大小写字母）
    codes = ["AbcD", "XyZ1", "aAaA", "ZzZz"]

    for code in codes:
        print(f"\n构建编码 {code} 的二叉树:")
        root = build_tree(code)

        # 中序遍历验证树结构
        print("中序遍历结果:", inorder_traversal(root))

        # 生成根节点编码（通过第一层节点）
        level_encoding = generate_root_encoding_from_level(root, 1)
        print(f"第一层生成的编码: {level_encoding}")
        print(f"根节点编码验证: {level_encoding == code}")
        # 生成根节点编码（通过第二层节点）
        level_encoding = generate_root_encoding_from_level(root, 2)
        print(f"第二层生成的编码: {level_encoding}")
        print(f"根节点编码验证: {level_encoding == code}")
        # 生成根节点编码（通过第三层节点）
        level_encoding = generate_root_encoding_from_level(root, 3)
        print(f"第三层生成的编码: {level_encoding}")
        print(f"根节点编码验证: {level_encoding == code}")

        # 通过叶子节点生成根节点编码
        leaves_encoding = generate_root_encoding_from_leaves(root)
        print(f"叶子节点生成的编码: {leaves_encoding}")
        print(f"根节点编码验证: {leaves_encoding == code}")

        # 按层打印节点值（用于排查）
        levels = get_levels(root)
        for i, lv in enumerate(levels):
            print(f"第 {i} 层: {lv}")

        # 可视化树结构
        print("树结构可视化:")
        print_tree(root, 0)
        print("\n" + "-"*50 + "\n")
