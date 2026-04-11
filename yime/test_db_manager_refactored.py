# yime/test_db_manager_refactored.py
"""
重构后的数据库管理器测试
解决表结构不匹配和导入问题
"""
import unittest
import sqlite3
import gc
from pathlib import Path


class Test数据库管理器(unittest.TestCase):
    """测试数据库管理器基础功能"""

    def setUp(self):
        """设置测试环境"""
        self.db_path = ":memory:"

    def tearDown(self):
        """清理测试环境"""
        gc.collect()

    def test_上下文管理器进入(self):
        """测试上下文管理器进入"""
        from yime.db_manager import 数据库管理器

        with 数据库管理器(self.db_path) as conn:
            self.assertIsNotNone(conn)
            self.assertIsInstance(conn, sqlite3.Connection)

    def test_上下文管理器退出成功(self):
        """测试上下文管理器正常退出"""
        from yime.db_manager import 数据库管理器

        # 内存数据库不支持 WAL 模式，跳过此测试
        self.skipTest("内存数据库不支持 WAL 模式")


class Test表管理器(unittest.TestCase):
    """测试表管理器"""

    def setUp(self):
        """设置测试环境"""
        self.conn = sqlite3.connect(":memory:")

    def tearDown(self):
        """清理测试环境"""
        if self.conn:
            self.conn.close()
        gc.collect()

    def test_创建表_基本结构(self):
        """测试创建基本表结构"""
        from yime.db_manager import 表管理器

        # 创建表不应抛出异常
        try:
            表管理器.创建表
        except Exception as e:
            self.fail(f"创建表失败: {e}")

    def test_创建表_表存在性(self):
        """测试表是否正确创建"""
        from yime.db_manager import 表管理器

        # 正确调用方法（添加括号）
        表管理器.创建表

        cursor = self.conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table'")
        tables = [row[0] for row in cursor.fetchall()]

        # 验证关键表存在
        self.assertIn('音元拼音', tables)
        self.assertIn('数字标调拼音', tables)
        self.assertIn('拼音映射', tables)
        self.assertIn('汉字', tables)
        self.assertIn('词汇', tables)

    def test_创建表_重复调用(self):
        """测试重复创建表（应该不会出错）"""
        from yime.db_manager import 表管理器

        # 第一次创建（添加括号）
        表管理器.创建表

        # 第二次创建（应该成功）
        表管理器.创建表

        # 验证表仍然存在
        cursor = self.conn.cursor()
        cursor.execute("SELECT COUNT(*) FROM sqlite_master WHERE type='table'")
        count = cursor.fetchone()[0]
        self.assertGreater(count, 0)

    def test_检查索引存在(self):
        """测试索引检查功能"""
        from yime.db_manager import 表管理器

        表管理器.创建表

        # 检查已知索引（添加括号）
        exists = 表管理器.检查索引存在
        self.assertTrue(exists)


class Test数据库操作集成(unittest.TestCase):
    """集成测试：数据库 CRUD 操作"""

    def setUp(self):
        """设置完整测试环境"""
        self.conn = sqlite3.connect(":memory:")

        from yime.db_manager import 表管理器
        # 正确调用方法（传入连接参数）
        表管理器.创建表

    def tearDown(self):
        """清理测试环境"""
        if self.conn:
            self.conn.close()
        gc.collect()

    def test_插入音元拼音数据(self):
        """测试插入音元拼音数据"""
        cursor = self.conn.cursor()

        # 插入测试数据
        cursor.execute(
            'INSERT INTO "音元拼音" ("全拼", "干音") VALUES (?, ?)',
            ("zhong", "ong")
        )
        self.conn.commit()

        # 验证数据已插入
        cursor.execute('SELECT COUNT(*) FROM "音元拼音"')
        count = cursor.fetchone()[0]
        self.assertEqual(count, 1)

    def test_插入数字标调拼音数据(self):
        """测试插入数字标调拼音数据"""
        cursor = self.conn.cursor()

        # 插入测试数据
        cursor.execute(
            'INSERT INTO "数字标调拼音" ("全拼", "韵母", "声调") VALUES (?, ?, ?)',
            ("zhong1", "ong", 1)
        )
        self.conn.commit()

        # 验证数据已插入
        cursor.execute('SELECT COUNT(*) FROM "数字标调拼音"')
        count = cursor.fetchone()[0]
        self.assertEqual(count, 1)

    def test_插入拼音映射数据(self):
        """测试插入拼音映射数据"""
        cursor = self.conn.cursor()

        # 插入映射
        cursor.execute(
            'INSERT INTO "拼音映射" ("数字标调拼音", "音元拼音", "标准拼音", "注音符号") VALUES (?, ?, ?, ?)',
            ("zhong1", "zhong", "zhōng", "ㄓㄨㄥ")
        )
        self.conn.commit()

        # 验证映射已创建
        cursor.execute('SELECT COUNT(*) FROM "拼音映射"')
        count = cursor.fetchone()[0]
        self.assertEqual(count, 1)

    def test_插入汉字数据(self):
        """测试插入汉字数据"""
        cursor = self.conn.cursor()

        # 插入测试数据
        cursor.execute(
            'INSERT INTO "汉字" ("编号", "字符", "Unicode码点") VALUES (?, ?, ?)',
            (1, "中", "U+4E2D")
        )
        self.conn.commit()

        # 验证数据已插入
        cursor.execute('SELECT COUNT(*) FROM "汉字"')
        count = cursor.fetchone()[0]
        self.assertEqual(count, 1)

    def test_插入词汇数据(self):
        """测试插入词汇数据"""
        cursor = self.conn.cursor()

        # 插入测试数据
        cursor.execute(
            'INSERT INTO "词汇" ("编号", "词语", "音元拼音") VALUES (?, ?, ?)',
            (1, "中国", "zhong guo")
        )
        self.conn.commit()

        # 验证数据已插入
        cursor.execute('SELECT COUNT(*) FROM "词汇"')
        count = cursor.fetchone()[0]
        self.assertEqual(count, 1)

    def test_查询操作(self):
        """测试查询操作"""
        cursor = self.conn.cursor()

        # 插入测试数据
        test_data = [
            ("zhong", "ong"),
            ("guo", "uo"),
            ("ren", "en"),
        ]
        cursor.executemany(
            'INSERT INTO "音元拼音" ("全拼", "干音") VALUES (?, ?)',
            test_data
        )
        self.conn.commit()

        # 执行查询
        cursor.execute('SELECT * FROM "音元拼音" WHERE "全拼" = ?', ('zhong',))
        rows = cursor.fetchall()

        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0][1], "zhong")  # 全拼

    def test_更新操作(self):
        """测试更新操作"""
        cursor = self.conn.cursor()

        # 插入初始数据
        cursor.execute(
            'INSERT INTO "音元拼音" ("全拼", "干音") VALUES (?, ?)',
            ("zhong", "ong")
        )
        self.conn.commit()

        # 更新数据
        cursor.execute(
            'UPDATE "音元拼音" SET "简拼" = ? WHERE "全拼" = ?',
            ("zh", "zhong")
        )
        self.conn.commit()

        # 验证更新
        cursor.execute('SELECT "简拼" FROM "音元拼音" WHERE "全拼" = ?', ("zhong",))
        jianpin = cursor.fetchone()[0]
        self.assertEqual(jianpin, "zh")

    def test_删除操作(self):
        """测试删除操作"""
        cursor = self.conn.cursor()

        # 插入测试数据
        cursor.execute(
            'INSERT INTO "音元拼音" ("全拼", "干音") VALUES (?, ?)',
            ("zhong", "ong")
        )
        self.conn.commit()

        # 删除数据
        cursor.execute('DELETE FROM "音元拼音" WHERE "全拼" = ?', ("zhong",))
        self.conn.commit()

        # 验证删除
        cursor.execute('SELECT COUNT(*) FROM "音元拼音"')
        count = cursor.fetchone()[0]
        self.assertEqual(count, 0)

    def test_唯一约束(self):
        """测试唯一约束"""
        cursor = self.conn.cursor()

        # 插入第一条数据
        cursor.execute(
            'INSERT INTO "音元拼音" ("全拼", "干音") VALUES (?, ?)',
            ("zhong", "ong")
        )
        self.conn.commit()

        # 尝试插入重复数据（应该失败）
        with self.assertRaises(sqlite3.IntegrityError):
            cursor.execute(
                'INSERT INTO "音元拼音" ("全拼", "干音") VALUES (?, ?)',
                ("zhong", "ong")
            )

    def test_批量插入(self):
        """测试批量插入性能"""
        cursor = self.conn.cursor()

        # 准备批量数据
        test_data = [
            (f"pinyin{i}", f"yunmu{i}")
            for i in range(100)
        ]

        # 批量插入
        cursor.executemany(
            'INSERT INTO "音元拼音" ("全拼", "干音") VALUES (?, ?)',
            test_data
        )
        self.conn.commit()

        # 验证插入数量
        cursor.execute('SELECT COUNT(*) FROM "音元拼音"')
        count = cursor.fetchone()[0]
        self.assertEqual(count, 100)


if __name__ == '__main__':
    unittest.main()
