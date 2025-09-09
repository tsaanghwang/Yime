class TrieNode:
    """字典树节点类"""
    def __init__(self):
        self.children = {}  # 子节点字典
        self.is_end = False  # 标记是否为单词结尾
        self.data = None  # 可选的附加数据

class DictionaryTrie:
    """字典树实现"""
    def __init__(self):
        self.root = TrieNode()

    def insert(self, word, data=None):
        """插入单词到字典树"""
        node = self.root
        for char in word:
            if char not in node.children:
                node.children[char] = TrieNode()
            node = node.children[char]
        node.is_end = True
        node.data = data

    def search(self, word):
        """搜索完整单词"""
        node = self._search_prefix(word)
        return node is not None and node.is_end

    def starts_with(self, prefix):
        """检查是否有以prefix开头的单词"""
        return self._search_prefix(prefix) is not None

    def _search_prefix(self, prefix):
        """内部方法：搜索前缀"""
        node = self.root
        for char in prefix:
            if char not in node.children:
                return None
            node = node.children[char]
        return node

    def get_all_with_prefix(self, prefix):
        """获取所有以prefix开头的单词"""
        node = self._search_prefix(prefix)
        if not node:
            return []

        results = []
        self._dfs_collect(node, prefix, results)
        return results

    def _dfs_collect(self, node, prefix, results):
        """深度优先收集所有单词"""
        if node.is_end:
            results.append((prefix, node.data))

        for char, child in node.children.items():
            self._dfs_collect(child, prefix + char, results)

    def delete(self, word):
        """删除单词"""
        self._delete_helper(self.root, word, 0)

    def _delete_helper(self, node, word, index):
        """递归删除辅助函数"""
        if index == len(word):
            if not node.is_end:
                return False  # 单词不存在
            node.is_end = False
            return len(node.children) == 0

        char = word[index]
        if char not in node.children:
            return False  # 单词不存在

        should_delete_child = self._delete_helper(node.children[char], word, index + 1)

        if should_delete_child:
            del node.children[char]
            return len(node.children) == 0 and not node.is_end

        return False