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
        self.db_path = Path(__file__).parent / "pinyin_hanzi.db"
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
        self.assertIn('汉字拼音初始数据', tables)
        self.assertIn('汉字频率', tables)
        self.assertIn('词汇', tables)

    def test_音元拼音数据(self):
        """测试音元拼音数据"""
        cursor = self.conn.cursor()
        cursor.execute('SELECT COUNT(*) FROM "音元拼音"')
        count = cursor.fetchone()[0]
        self.assertGreater(count, 0)
        print(f"音元拼音数据: {count} 条")

    def test_汉字数据(self):
        """测试汉字数据"""
        cursor = self.conn.cursor()
        cursor.execute('SELECT COUNT(*) FROM "汉字拼音初始数据"')
        count = cursor.fetchone()[0]
        self.assertGreater(count, 0)
        print(f"汉字数据: {count} 条")

    def test_词汇数据(self):
        """测试词汇数据"""
        cursor = self.conn.cursor()
        cursor.execute('SELECT COUNT(*) FROM "词汇"')
        count = cursor.fetchone()[0]
        self.assertGreater(count, 0)
        print(f"词汇数据: {count} 条")

    def test_查询音元拼音(self):
        """测试查询音元拼音"""
        cursor = self.conn.cursor()
        cursor.execute('SELECT * FROM "音元拼音" LIMIT 5')
        rows = cursor.fetchall()
        self.assertGreater(len(rows), 0)

    def test_查询汉字(self):
        """测试查询汉字"""
        cursor = self.conn.cursor()
        cursor.execute('SELECT * FROM "汉字拼音初始数据" LIMIT 5')
        rows = cursor.fetchall()
        self.assertGreater(len(rows), 0)

    def test_查询词汇(self):
        """测试查询词汇"""
        cursor = self.conn.cursor()
        cursor.execute('SELECT * FROM "词汇" LIMIT 5')
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
        self.db_path = Path(__file__).parent / "pinyin_hanzi.db"
        self.conn = sqlite3.connect(str(self.db_path))

    def tearDown(self):
        """清理测试环境"""
        if self.conn:
            self.conn.close()
        gc.collect()

    def test_查询特定拼音(self):
        """测试查询特定拼音"""
        cursor = self.conn.cursor()
        cursor.execute('SELECT * FROM "音元拼音" WHERE "全拼" = ?', ('zhong',))
        rows = cursor.fetchall()
        self.assertGreater(len(rows), 0)

    def test_查询特定汉字(self):
        """测试查询特定汉字"""
        cursor = self.conn.cursor()
        cursor.execute('SELECT * FROM "汉字拼音初始数据" WHERE "汉字" = ?', ('中',))
        rows = cursor.fetchall()
        self.assertGreater(len(rows), 0)

    def test_查询特定词汇(self):
        """测试查询特定词汇"""
        cursor = self.conn.cursor()
        cursor.execute('SELECT * FROM "词汇" WHERE "词语" LIKE ?', ('中国%',))
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
        """测试统计汉字数量"""
        cursor = self.conn.cursor()
        cursor.execute('SELECT COUNT(DISTINCT "汉字") FROM "汉字拼音初始数据"')
        count = cursor.fetchone()[0]
        self.assertGreater(count, 0)
        print(f"不同汉字数量: {count}")

    def test_统计词汇数量(self):
        """测试统计词汇数量"""
        cursor = self.conn.cursor()
        cursor.execute('SELECT COUNT(DISTINCT "词语") FROM "词汇"')
        count = cursor.fetchone()[0]
        self.assertGreater(count, 0)
        print(f"不同词汇数量: {count}")


if __name__ == '__main__':
    unittest.main()
