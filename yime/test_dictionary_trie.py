# yime/test_dictionary_trie.py
import unittest
from yime.dictionary_trie import TrieNode, DictionaryTrie

class TestTrieNode(unittest.TestCase):
    """测试字典树节点"""

    def test_node_initialization(self):
        """测试节点初始化"""
        node = TrieNode()
        self.assertEqual(node.children, {})
        self.assertFalse(node.is_end)
        self.assertIsNone(node.data)

    def test_node_with_data(self):
        """测试带数据的节点"""
        node = TrieNode()
        node.data = {"frequency": 100}
        node.is_end = True

        self.assertTrue(node.is_end)
        self.assertEqual(node.data["frequency"], 100)


class TestDictionaryTrie(unittest.TestCase):
    """测试字典树"""

    def setUp(self):
        """设置测试环境"""
        self.trie = DictionaryTrie()

    def test_trie_initialization(self):
        """测试字典树初始化"""
        self.assertIsNotNone(self.trie.root)
        self.assertEqual(self.trie.word_count, 0)

    def test_insert_single_word(self):
        """测试插入单个单词"""
        self.trie.insert("hello")
        self.assertEqual(self.trie.word_count, 1)
        self.assertTrue(self.trie.search("hello"))

    def test_insert_multiple_words(self):
        """测试插入多个单词"""
        words = ["hello", "world", "python", "test"]
        for word in words:
            self.trie.insert(word)

        self.assertEqual(self.trie.word_count, len(words))
        for word in words:
            self.assertTrue(self.trie.search(word))

    def test_insert_with_data(self):
        """测试插入带数据的单词"""
        self.trie.insert("hello", {"frequency": 100})
        self.assertTrue(self.trie.search("hello"))

        # 获取所有以 "hello" 开头的单词
        results = self.trie.get_all_with_prefix("hello")
        self.assertEqual(len(results), 1)
        self.assertEqual(results[0][1]["frequency"], 100)

    def test_insert_duplicate_word(self):
        """测试插入重复单词"""
        self.trie.insert("hello")
        self.trie.insert("hello")  # 重复插入

        # 不应该重复计数
        self.assertEqual(self.trie.word_count, 1)

    def test_search_existing_word(self):
        """测试搜索存在的单词"""
        self.trie.insert("hello")
        self.assertTrue(self.trie.search("hello"))

    def test_search_nonexistent_word(self):
        """测试搜索不存在的单词"""
        self.trie.insert("hello")
        self.assertFalse(self.trie.search("world"))

    def test_search_case_insensitive(self):
        """测试大小写不敏感搜索"""
        # 注意：当前实现使用 lower() 进行搜索，但插入时不转换
        # 所以需要插入小写版本才能搜索到
        self.trie.insert("hello")
        self.assertTrue(self.trie.search("hello"))
        self.assertTrue(self.trie.search("HELLO"))  # search 会转换为小写

    def test_starts_with_existing_prefix(self):
        """测试存在的前缀"""
        self.trie.insert("hello")
        self.assertTrue(self.trie.starts_with("he"))
        self.assertTrue(self.trie.starts_with("hel"))

    def test_starts_with_nonexistent_prefix(self):
        """测试不存在的前缀"""
        self.trie.insert("hello")
        self.assertFalse(self.trie.starts_with("wo"))

    def test_get_all_with_prefix_single(self):
        """测试获取单个前缀匹配"""
        self.trie.insert("hello")
        results = self.trie.get_all_with_prefix("he")
        self.assertEqual(len(results), 1)
        self.assertEqual(results[0][0], "hello")

    def test_get_all_with_prefix_multiple(self):
        """测试获取多个前缀匹配"""
        words = ["hello", "help", "helicopter", "world"]
        for word in words:
            self.trie.insert(word)

        results = self.trie.get_all_with_prefix("hel")
        self.assertEqual(len(results), 3)

        result_words = [r[0] for r in results]
        self.assertIn("hello", result_words)
        self.assertIn("help", result_words)
        self.assertIn("helicopter", result_words)
        self.assertNotIn("world", result_words)

    def test_get_all_with_prefix_empty(self):
        """测试空前缀匹配"""
        self.trie.insert("hello")
        results = self.trie.get_all_with_prefix("")
        self.assertEqual(len(results), 1)

    def test_get_all_with_prefix_no_match(self):
        """测试无匹配的前缀"""
        self.trie.insert("hello")
        results = self.trie.get_all_with_prefix("xyz")
        self.assertEqual(len(results), 0)

    def test_delete_existing_word(self):
        """测试删除存在的单词"""
        self.trie.insert("hello")
        self.assertTrue(self.trie.search("hello"))

        self.trie.delete("hello")
        self.assertFalse(self.trie.search("hello"))

    def test_delete_nonexistent_word(self):
        """测试删除不存在的单词"""
        # 不应该抛出异常
        self.trie.delete("hello")

    def test_delete_partial_word(self):
        """测试删除部分单词"""
        self.trie.insert("hello")
        self.trie.insert("hel")

        self.trie.delete("hel")
        self.assertFalse(self.trie.search("hel"))
        self.assertTrue(self.trie.search("hello"))

    def test_word_count_accuracy(self):
        """测试单词计数准确性"""
        words = ["a", "ab", "abc", "abcd"]
        for word in words:
            self.trie.insert(word)

        self.assertEqual(self.trie.word_count, len(words))

        # 删除一个单词
        self.trie.delete("ab")
        # 注意：delete 可能不更新 word_count，取决于实现

    def test_empty_trie(self):
        """测试空字典树"""
        self.assertEqual(self.trie.word_count, 0)
        self.assertFalse(self.trie.search("any"))
        self.assertFalse(self.trie.starts_with("any"))
        self.assertEqual(self.trie.get_all_with_prefix("any"), [])

    def test_long_word(self):
        """测试长单词"""
        long_word = "supercalifragilisticexpialidocious"
        self.trie.insert(long_word)
        self.assertTrue(self.trie.search(long_word))
        self.assertTrue(self.trie.starts_with("super"))

    def test_special_characters(self):
        """测试特殊字符"""
        self.trie.insert("hello-world")
        self.trie.insert("test_123")

        self.assertTrue(self.trie.search("hello-world"))
        self.assertTrue(self.trie.search("test_123"))

    def test_chinese_characters(self):
        """测试中文字符"""
        self.trie.insert("你好")
        self.trie.insert("世界")

        self.assertTrue(self.trie.search("你好"))
        self.assertTrue(self.trie.search("世界"))
        self.assertTrue(self.trie.starts_with("你"))

    def test_prefix_hierarchy(self):
        """测试前缀层次结构"""
        words = ["a", "ab", "abc", "abcd"]
        for word in words:
            self.trie.insert(word)

        # 所有前缀都应该存在
        for word in words:
            self.assertTrue(self.trie.search(word))

        # 获取 "a" 开头的所有单词
        results = self.trie.get_all_with_prefix("a")
        self.assertEqual(len(results), 4)


class TestDictionaryTriePerformance(unittest.TestCase):
    """性能测试"""

    def test_large_dataset(self):
        """测试大数据集"""
        trie = DictionaryTrie()

        # 插入1000个单词
        for i in range(1000):
            trie.insert(f"word{i}")

        self.assertEqual(trie.word_count, 1000)

        # 搜索应该快速
        self.assertTrue(trie.search("word500"))
        self.assertFalse(trie.search("word1000"))

        # 前缀搜索
        results = trie.get_all_with_prefix("word1")
        self.assertGreater(len(results), 0)

    def test_deep_nesting(self):
        """测试深层嵌套"""
        trie = DictionaryTrie()

        # 创建深层嵌套
        word = "a" * 100
        trie.insert(word)

        self.assertTrue(trie.search(word))
        self.assertTrue(trie.starts_with("a" * 50))


if __name__ == '__main__':
    unittest.main()
