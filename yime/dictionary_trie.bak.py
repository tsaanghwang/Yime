class TrieNode:
    def __init__(self):
        self.children = {}  # 子节点字典 {char: TrieNode}
        self.is_end = False  # 标记单词结束

class DictionaryTrie:
    def __init__(self):
        self.root = TrieNode()
        self.word_count = 0  # 记录总单词数

    def insert(self, word: str) -> None:
        """插入单词到字典树"""
        node = self.root
        for char in word.lower():  # 统一转为小写（可选）
            if char not in node.children:
                node.children[char] = TrieNode()
            node = node.children[char]
        if not node.is_end:  # 避免重复计数
            node.is_end = True
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

# 创建字典树并插入单词
dictionary = DictionaryTrie()
words = ["apple", "banana", "orange", "app", "application"]
for word in words:
    dictionary.insert(word)

# 查询测试
print(dictionary.search("apple"))     # True
print(dictionary.search("app"))       # True
print(dictionary.search("appl"))      # False
print(dictionary.starts_with("ora"))  # True
print(f"字典单词总数: {dictionary.size()}")  # 5

#  从文件中加载并查询
dictionary.load_dictionary("dictionary.txt")
print(dictionary.search("apple"))     # True
print(dictionary.search("app"))       # True
print(dictionary.search("appl"))      # False
print(dictionary.starts_with("ora"))  # True
print(f"字典单词总数: {dictionary.size()}")  # 5

dict_trie = DictionaryTrie()
dict_trie.load_dictionary("dictionary.txt")

print(dict_trie.search("banana"))  # True
print(dict_trie.get_all_words())   # 输出所有单词

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
# 使用示例
print(dict_trie.fuzzy_search("app.."))  # 可能匹配 ["apple", "apply"]（如果存在）


if __name__ == "__main__":
    # 示例用法
    trie = DictionaryTrie()
    trie.insert("hello")
    trie.insert("world")
    print(trie.search("hello"))  # True
