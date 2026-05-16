# yime/test_db_manager_real.py
"""
使用实际数据库的测试
连接 yime/pinyin_hanzi.db
"""
import unittest
import sqlite3
import gc
from pathlib import Path


class Test实际数据库(unittest.TestCase):
    """测试实际数据库"""

    def setUp(self):
        """设置测试环境"""
        self.db_path = Path(__file__).resolve().parent.parent / "pinyin_hanzi.db"
        self.conn = sqlite3.connect(str(self.db_path))

    def tearDown(self):
        """清理测试环境"""
        if self.conn:
            self.conn.close()
        gc.collect()

    def test_数据库连接(self):
        """测试数据库连接"""
        self.assertIsNotNone(self.conn)
        self.assertIsInstance(self.conn, sqlite3.Connection)

    def test_表存在性(self):
        """测试表是否存在"""
        cursor = self.conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table'")
        tables = [row[0] for row in cursor.fetchall()]

        # 验证关键表存在
        self.assertIn('音元拼音', tables)
        self.assertIn('数字标调拼音', tables)
        self.assertNotIn('汉字拼音初始数据', tables)
        self.assertNotIn('汉字', tables)
        self.assertNotIn('汉字频率', tables)
        self.assertNotIn('词汇', tables)
        self.assertIn('char_inventory', tables)
        self.assertIn('phrase_inventory', tables)

    def test_音元拼音数据(self):
        """测试音元拼音数据"""
        cursor = self.conn.cursor()
        cursor.execute('SELECT COUNT(*) FROM "音元拼音"')
        count = cursor.fetchone()[0]
        self.assertGreater(count, 0)
        print(f"音元拼音数据: {count} 条")

    def test_char_inventory数据(self):
        """测试 prototype 单字数据"""
        cursor = self.conn.cursor()
        cursor.execute('SELECT COUNT(*) FROM char_inventory')
        count = cursor.fetchone()[0]
        self.assertGreater(count, 0)
        print(f"char_inventory 数据: {count} 条")

    def test_phrase_inventory数据(self):
        """测试 prototype 词语数据"""
        cursor = self.conn.cursor()
        cursor.execute('SELECT COUNT(*) FROM phrase_inventory')
        count = cursor.fetchone()[0]
        self.assertGreater(count, 0)
        print(f"phrase_inventory 数据: {count} 条")

    def test_查询音元拼音(self):
        """测试查询音元拼音"""
        cursor = self.conn.cursor()
        cursor.execute('SELECT * FROM "音元拼音" LIMIT 5')
        rows = cursor.fetchall()
        self.assertGreater(len(rows), 0)

    def test_查询phrase_inventory(self):
        """测试查询 prototype 词语表"""
        cursor = self.conn.cursor()
        cursor.execute('SELECT * FROM phrase_inventory LIMIT 5')
        rows = cursor.fetchall()
        self.assertGreater(len(rows), 0)

    def test_索引存在性(self):
        """测试索引是否存在"""
        cursor = self.conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='index'")
        indexes = [row[0] for row in cursor.fetchall()]
        self.assertGreater(len(indexes), 0)
        print(f"索引数量: {len(indexes)}")


class Test数据库CRUD操作(unittest.TestCase):
    """测试数据库 CRUD 操作"""

    def setUp(self):
        """设置测试环境"""
        self.db_path = Path(__file__).resolve().parent.parent / "pinyin_hanzi.db"
        self.conn = sqlite3.connect(str(self.db_path))

    def tearDown(self):
        """清理测试环境"""
        if self.conn:
            self.conn.close()
        gc.collect()

    def test_查询特定拼音(self):
        """测试查询特定拼音"""
        cursor = self.conn.cursor()
        cursor.execute('SELECT "全拼" FROM "音元拼音" LIMIT 1')
        pinyin = cursor.fetchone()[0]
        cursor.execute('SELECT * FROM "音元拼音" WHERE "全拼" = ?', (pinyin,))
        rows = cursor.fetchall()
        self.assertGreater(len(rows), 0)

    def test_查询特定汉字(self):
        """测试查询特定汉字"""
        cursor = self.conn.cursor()
        cursor.execute('SELECT * FROM char_inventory WHERE hanzi = ?', ('中',))
        rows = cursor.fetchall()
        self.assertGreater(len(rows), 0)

    def test_查询特定短语(self):
        """测试查询特定短语"""
        cursor = self.conn.cursor()
        cursor.execute('SELECT * FROM phrase_inventory WHERE phrase LIKE ?', ('中国%',))
        rows = cursor.fetchall()
        self.assertGreater(len(rows), 0)

    def test_统计拼音数量(self):
        """测试统计拼音数量"""
        cursor = self.conn.cursor()
        cursor.execute('SELECT COUNT(DISTINCT "全拼") FROM "音元拼音"')
        count = cursor.fetchone()[0]
        self.assertGreater(count, 0)
        print(f"不同拼音数量: {count}")

    def test_统计汉字数量(self):
        """测试统计 prototype 单字数量"""
        cursor = self.conn.cursor()
        cursor.execute('SELECT COUNT(DISTINCT hanzi) FROM char_inventory')
        count = cursor.fetchone()[0]
        self.assertGreater(count, 0)
        print(f"不同汉字数量: {count}")

    def test_统计短语数量(self):
        """测试统计 prototype 词语数量"""
        cursor = self.conn.cursor()
        cursor.execute('SELECT COUNT(DISTINCT phrase) FROM phrase_inventory')
        count = cursor.fetchone()[0]
        self.assertGreater(count, 0)
        print(f"不同短语数量: {count}")


if __name__ == '__main__':
    unittest.main()
