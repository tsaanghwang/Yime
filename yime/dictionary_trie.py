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
        self.word_count = 0  # 记录总单词数

    def insert(self, word, data=None):
        """插入单词到字典树"""
        node = self.root
        for char in word:
            if char not in node.children:
                node.children[char] = TrieNode()
            node = node.children[char]
        if not node.is_end:  # 避免重复计数
            node.is_end = True
            node.data = data
            self.word_count += 1

    def search(self, word: str) -> bool:
        """检查单词是否存在"""
        node = self.root
        for char in word.lower():
            if char not in node.children:
                return False
            node = node.children[char]
        return node.is_end

    def starts_with(self, prefix: str) -> bool:
        """检查是否存在以prefix开头的单词"""
        node = self.root
        for char in prefix.lower():
            if char not in node.children:
                return False
            node = node.children[char]
        return True

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

    def load_dictionary(self, file_path: str) -> None:
        """从文本文件加载字典（每行一个单词）"""
        with open(file_path, 'r', encoding='utf-8') as file:
            for line in file:
                word = line.strip()
                if word:  # 跳过空行
                    self.insert(word)

    def get_all_words(self) -> list:
        """获取字典树中所有单词（用于调试或导出）"""
        words = []

        def dfs(node, current_word):
            if node.is_end:
                words.append(current_word)
            for char, child_node in node.children.items():
                dfs(child_node, current_word + char)

        dfs(self.root, "")
        return words

    def size(self) -> int:
        """返回字典中的单词总数"""
        return self.word_count

    def fuzzy_search(self, pattern: str) -> list:
        """支持 '.' 通配符的模糊搜索（如 "appl." 匹配 "apple"）"""
        results = []

        def dfs(node, index, current_word):
            if index == len(pattern):
                if node.is_end:
                    results.append(current_word)
                return
            char = pattern[index]
            if char == '.':
                for next_char, child_node in node.children.items():
                    dfs(child_node, index + 1, current_word + next_char)
            else:
                if char in node.children:
                    dfs(node.children[char], index + 1, current_word + char)

        dfs(self.root, 0, "")
        return results

if __name__ == "__main__":
    # 示例用法
    trie = DictionaryTrie()
    words = ["apple", "banana", "orange", "app", "application"]
    for word in words:
        trie.insert(word)

    print(trie.fuzzy_search("app.."))  # 可能匹配 ["apple"]
    print(trie.search("apple"))     # True
    print(trie.search("app"))       # True
    print(trie.search("appl"))      # False
    print(trie.starts_with("ora"))  # True
    print(f"字典单词总数: {trie.size()}")  # 5

    # 从文件中加载并查询
    # 文件路径请根据实际情况调整
    try:
        trie.load_dictionary("yime/dictionary.txt")
        print(trie.search("apple"))     # True
        print(trie.search("app"))       # True
        print(trie.search("appl"))      # False
        print(trie.starts_with("ora"))  # True
        print(f"字典单词总数: {trie.size()}")
        print(trie.search("banana"))  # True
        print(trie.get_all_words())   # 输出所有单词
    except FileNotFoundError:
        print("未找到字典文件 yime/dictionary.txt")
