# yime/test_db_manager_simple.py
"""
简化的数据库管理器测试
专注于核心功能测试
"""
import unittest
import sqlite3
import gc


class Test数据库基础功能(unittest.TestCase):
    """测试数据库基础功能"""

    def setUp(self):
        """设置测试环境"""
        self.conn = sqlite3.connect(":memory:")
        from yime.db_manager import 表管理器
        表管理器.创建表

    def tearDown(self):
        """清理测试环境"""
        if self.conn:
            self.conn.close()
        gc.collect()

    def test_表创建成功(self):
        """测试表创建成功"""
        cursor = self.conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table'")
        tables = [row[0] for row in cursor.fetchall()]

        # 验证关键表存在
        self.assertIn('音元拼音', tables)
        self.assertIn('数字标调拼音', tables)
        self.assertIn('拼音映射', tables)
        self.assertIn('汉字', tables)
        self.assertIn('词汇', tables)

    def test_插入音元拼音(self):
        """测试插入音元拼音"""
        cursor = self.conn.cursor()
        cursor.execute(
            'INSERT INTO "音元拼音" ("全拼", "干音") VALUES (?, ?)',
            ("zhong", "ong")
        )
        self.conn.commit()

        cursor.execute('SELECT COUNT(*) FROM "音元拼音"')
        count = cursor.fetchone()[0]
        self.assertEqual(count, 1)

    def test_插入汉字(self):
        """测试插入汉字"""
        cursor = self.conn.cursor()
        cursor.execute(
            'INSERT INTO "汉字" ("编号", "字符", "Unicode码点") VALUES (?, ?, ?)',
            (1, "中", "U+4E2D")
        )
        self.conn.commit()

        cursor.execute('SELECT COUNT(*) FROM "汉字"')
        count = cursor.fetchone()[0]
        self.assertEqual(count, 1)

    def test_插入词汇(self):
        """测试插入词汇"""
        cursor = self.conn.cursor()
        cursor.execute(
            'INSERT INTO "词汇" ("编号", "词语", "音元拼音") VALUES (?, ?, ?)',
            (1, "中国", "zhong guo")
        )
        self.conn.commit()

        cursor.execute('SELECT COUNT(*) FROM "词汇"')
        count = cursor.fetchone()[0]
        self.assertEqual(count, 1)

    def test_批量插入(self):
        """测试批量插入"""
        cursor = self.conn.cursor()
        test_data = [(f"p{i}", f"y{i}") for i in range(100)]

        cursor.executemany(
            'INSERT INTO "音元拼音" ("全拼", "干音") VALUES (?, ?)',
            test_data
        )
        self.conn.commit()

        cursor.execute('SELECT COUNT(*) FROM "音元拼音"')
        count = cursor.fetchone()[0]
        self.assertEqual(count, 100)

    def test_唯一约束(self):
        """测试唯一约束"""
        cursor = self.conn.cursor()
        cursor.execute(
            'INSERT INTO "音元拼音" ("全拼", "干音") VALUES (?, ?)',
            ("zhong", "ong")
        )
        self.conn.commit()

        # 尝试插入重复数据
        with self.assertRaises(sqlite3.IntegrityError):
            cursor.execute(
                'INSERT INTO "音元拼音" ("全拼", "干音") VALUES (?, ?)',
                ("zhong", "ong")
            )

    def test_查询操作(self):
        """测试查询操作"""
        cursor = self.conn.cursor()
        test_data = [("zhong", "ong"), ("guo", "uo"), ("ren", "en")]
        cursor.executemany(
            'INSERT INTO "音元拼音" ("全拼", "干音") VALUES (?, ?)',
            test_data
        )
        self.conn.commit()

        cursor.execute('SELECT * FROM "音元拼音" WHERE "全拼" = ?', ('zhong',))
        rows = cursor.fetchall()
        self.assertEqual(len(rows), 1)

    def test_更新操作(self):
        """测试更新操作"""
        cursor = self.conn.cursor()
        cursor.execute(
            'INSERT INTO "音元拼音" ("全拼", "干音") VALUES (?, ?)',
            ("zhong", "ong")
        )
        self.conn.commit()

        cursor.execute(
            'UPDATE "音元拼音" SET "简拼" = ? WHERE "全拼" = ?',
            ("zh", "zhong")
        )
        self.conn.commit()

        cursor.execute('SELECT "简拼" FROM "音元拼音" WHERE "全拼" = ?', ("zhong",))
        jianpin = cursor.fetchone()[0]
        self.assertEqual(jianpin, "zh")

    def test_删除操作(self):
        """测试删除操作"""
        cursor = self.conn.cursor()
        cursor.execute(
            'INSERT INTO "音元拼音" ("全拼", "干音") VALUES (?, ?)',
            ("zhong", "ong")
        )
        self.conn.commit()

        cursor.execute('DELETE FROM "音元拼音" WHERE "全拼" = ?', ("zhong",))
        self.conn.commit()

        cursor.execute('SELECT COUNT(*) FROM "音元拼音"')
        count = cursor.fetchone()[0]
        self.assertEqual(count, 0)


if __name__ == '__main__':
    unittest.main()
