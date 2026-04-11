# yime/test_hanzi_pinyin_data.py
"""
测试汉字拼音初始数据
"""
import unittest
import sqlite3
import gc
from pathlib import Path


class Test汉字拼音初始数据(unittest.TestCase):
    """测试汉字拼音初始数据"""

    def setUp(self):
        """设置测试环境"""
        self.db_path = Path(__file__).parent / "pinyin_hanzi.db"
        self.conn = sqlite3.connect(str(self.db_path))

    def tearDown(self):
        """清理测试环境"""
        if self.conn:
            self.conn.close()
        gc.collect()

    def test_数据存在(self):
        """测试数据是否存在"""
        cursor = self.conn.cursor()
        cursor.execute('SELECT COUNT(*) FROM "汉字拼音初始数据"')
        count = cursor.fetchone()[0]
        self.assertGreater(count, 0)
        print(f"\n汉字拼音数据: {count} 条")

    def test_汉字数量(self):
        """测试汉字数量"""
        cursor = self.conn.cursor()
        cursor.execute('SELECT COUNT(DISTINCT "汉字") FROM "汉字拼音初始数据"')
        count = cursor.fetchone()[0]
        self.assertGreater(count, 0)
        print(f"不同汉字: {count} 个")

    def test_拼音数量(self):
        """测试拼音数量"""
        cursor = self.conn.cursor()
        cursor.execute('SELECT COUNT(DISTINCT "拼音") FROM "汉字拼音初始数据"')
        count = cursor.fetchone()[0]
        self.assertGreater(count, 0)
        print(f"不同拼音: {count} 个")

    def test_查询特定汉字(self):
        """测试查询特定汉字"""
        cursor = self.conn.cursor()
        cursor.execute('SELECT * FROM "汉字拼音初始数据" WHERE "汉字" = ?', ('中',))
        rows = cursor.fetchall()
        self.assertGreater(len(rows), 0)
        print(f"汉字'中'的拼音: {[row[1] for row in rows]}")

    def test_查询特定拼音(self):
        """测试查询特定拼音"""
        cursor = self.conn.cursor()
        cursor.execute('SELECT * FROM "汉字拼音初始数据" WHERE "拼音" = ?', ('zhong1',))
        rows = cursor.fetchall()
        self.assertGreater(len(rows), 0)
        print(f"拼音'zhong1'的汉字数量: {len(rows)}")

    def test_常用读音(self):
        """测试常用读音标记"""
        cursor = self.conn.cursor()
        cursor.execute('SELECT COUNT(*) FROM "汉字拼音初始数据" WHERE "常用读音" = 1')
        count = cursor.fetchone()[0]
        self.assertGreater(count, 0)
        print(f"常用读音数量: {count}")

    def test_数据完整性(self):
        """测试数据完整性"""
        cursor = self.conn.cursor()

        # 检查空值
        cursor.execute('SELECT COUNT(*) FROM "汉字拼音初始数据" WHERE "汉字" IS NULL OR "汉字" = ""')
        null_count = cursor.fetchone()[0]
        self.assertEqual(null_count, 0)

        cursor.execute('SELECT COUNT(*) FROM "汉字拼音初始数据" WHERE "拼音" IS NULL OR "拼音" = ""')
        null_count = cursor.fetchone()[0]
        self.assertEqual(null_count, 0)

    def test_多音字(self):
        """测试多音字"""
        cursor = self.conn.cursor()
        cursor.execute('''
            SELECT "汉字", COUNT(*) as 拼音数
            FROM "汉字拼音初始数据"
            GROUP BY "汉字"
            HAVING 拼音数 > 1
            ORDER BY 拼音数 DESC
            LIMIT 10
        ''')
        rows = cursor.fetchall()
        self.assertGreater(len(rows), 0)
        print(f"\n多音字示例:")
        for row in rows:
            print(f"  {row[0]}: {row[1]} 个读音")

    def test_拼音格式(self):
        """测试拼音格式"""
        cursor = self.conn.cursor()
        cursor.execute('SELECT DISTINCT "拼音" FROM "汉字拼音初始数据" LIMIT 20')
        rows = cursor.fetchall()
        print(f"\n拼音格式示例:")
        for row in rows:
            print(f"  {row[0]}")


class Test汉字拼音数据质量(unittest.TestCase):
    """测试汉字拼音数据质量"""

    def setUp(self):
        """设置测试环境"""
        self.db_path = Path(__file__).parent / "pinyin_hanzi.db"
        self.conn = sqlite3.connect(str(self.db_path))

    def tearDown(self):
        """清理测试环境"""
        if self.conn:
            self.conn.close()
        gc.collect()

    def test_拼音声调格式(self):
        """测试拼音声调格式"""
        cursor = self.conn.cursor()
        # 检查拼音是否包含声调数字（使用LIKE代替REGEXP）
        cursor.execute('''
            SELECT COUNT(*) FROM "汉字拼音初始数据"
            WHERE "拼音" LIKE '%1' OR "拼音" LIKE '%2'
               OR "拼音" LIKE '%3' OR "拼音" LIKE '%4'
        ''')
        count = cursor.fetchone()[0]
        self.assertGreater(count, 0)
        print(f"\n包含声调数字的拼音: {count} 条")

    def test_汉字Unicode范围(self):
        """测试汉字Unicode范围"""
        cursor = self.conn.cursor()
        # 检查汉字是否在CJK统一汉字范围内
        cursor.execute('''
            SELECT "汉字", unicode("汉字") as code
            FROM "汉字拼音初始数据"
            WHERE code >= 0x4E00 AND code <= 0x9FFF
            LIMIT 5
        ''')
        rows = cursor.fetchall()
        self.assertGreater(len(rows), 0)
        print(f"CJK统一汉字示例:")
        for row in rows:
            print(f"  {row[0]}: U+{ord(row[0]):04X}")

    def test_数据来源(self):
        """测试数据来源"""
        cursor = self.conn.cursor()
        cursor.execute('SELECT DISTINCT "来源" FROM "汉字拼音初始数据"')
        rows = cursor.fetchall()
        self.assertGreater(len(rows), 0)
        print(f"\n数据来源:")
        for row in rows:
            print(f"  {row[0]}")


if __name__ == '__main__':
    unittest.main()
