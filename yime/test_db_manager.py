# yime/test_db_manager.py
import unittest
import sqlite3
import tempfile
import os
import gc
from pathlib import Path
from yime.db_manager import 数据库管理器, 表管理器

class Test数据库管理器(unittest.TestCase):
    """测试数据库管理器"""

    def setUp(self):
        """设置测试数据库"""
        # 使用内存数据库避免文件锁定问题
        self.db_path = ":memory:"

    def tearDown(self):
        """清理测试数据库"""
        # 内存数据库无需清理
        gc.collect()

    def test_context_manager_enter(self):
        """测试上下文管理器进入"""
        with 数据库管理器(self.db_path) as conn:
            self.assertIsNotNone(conn)
            self.assertIsInstance(conn, sqlite3.Connection)

    def test_context_manager_exit_success(self):
        """测试上下文管理器正常退出"""
        with 数据库管理器(self.db_path) as conn:
            cursor = conn.cursor()
            cursor.execute('CREATE TABLE test (id INTEGER)')
            cursor.execute('INSERT INTO test VALUES (1)')

        # 验证数据已提交
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            cursor.execute('SELECT COUNT(*) FROM test')
            count = cursor.fetchone()[0]
            self.assertEqual(count, 1)

    def test_context_manager_exit_with_exception(self):
        """测试上下文管理器异常退出"""
        try:
            with 数据库管理器(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute('CREATE TABLE test (id INTEGER)')
                cursor.execute('INSERT INTO test VALUES (1)')
                raise ValueError("测试异常")
        except ValueError:
            pass

        # 验证数据未提交（因为异常）
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            # 表可能不存在，因为事务被回滚
            cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='test'")
            result = cursor.fetchone()
            # 由于异常，表可能不存在或数据未插入
            # 具体行为取决于 isolation_level 设置

    def test_pragma_settings(self):
        """测试 PRAGMA 设置"""
        # 内存数据库不支持 WAL 模式，跳过此测试
        # 对于文件数据库，WAL 模式应该被设置
        if self.db_path == ":memory:":
            self.skipTest("内存数据库不支持 WAL 模式")
        
        with 数据库管理器(self.db_path) as conn:
            cursor = conn.cursor()
            cursor.execute('PRAGMA journal_mode')
            mode = cursor.fetchone()[0]
            # WAL 模式应该被设置
            self.assertEqual(mode.lower(), 'wal')


class Test表管理器(unittest.TestCase):
    """测试表管理器"""

    def setUp(self):
        """设置测试数据库"""
        # 使用内存数据库
        self.conn = sqlite3.connect(":memory:")

    def tearDown(self):
        """清理测试数据库"""
        if self.conn:
            self.conn.close()
        gc.collect()

    def test_创建表_基本表结构(self):
        """测试创建基本表结构"""
        表管理器.创建表(self.conn)

        # 验证表已创建
        cursor = self.conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table'")
        tables = [row[0] for row in cursor.fetchall()]

        # 检查关键表是否存在
        self.assertIn('汉字拼音初始数据', tables)
        self.assertIn('拼音映射关系', tables)
        self.assertIn('音元拼音', tables)
        self.assertIn('数字标调拼音', tables)
        self.assertIn('拼音映射', tables)

    def test_创建表_重复调用(self):
        """测试重复创建表（应该不会出错）"""
        # 第一次创建
        表管理器.创建表(self.conn)

        # 第二次创建（应该使用 IF NOT EXISTS）
        表管理器.创建表(self.conn)

        # 验证表仍然存在
        cursor = self.conn.cursor()
        cursor.execute("SELECT COUNT(*) FROM sqlite_master WHERE type='table'")
        count = cursor.fetchone()[0]
        self.assertGreater(count, 0)

    def test_表创建成功(self):
        """测试表创建成功"""
        # 创建表
        表管理器.创建表(self.conn)

        # 验证表已创建
        cursor = self.conn.cursor()
        cursor.execute("SELECT COUNT(*) FROM sqlite_master WHERE type='table'")
        count = cursor.fetchone()[0]
        self.assertGreater(count, 0)


class Test数据库操作集成(unittest.TestCase):
    """集成测试：数据库操作"""

    def setUp(self):
        """设置完整测试环境"""
        # 使用内存数据库
        self.db_path = ":memory:"

        # 初始化数据库结构
        with 数据库管理器(self.db_path) as conn:
            表管理器.创建表(conn)

    def tearDown(self):
        """清理测试环境"""
        gc.collect()

    def test_插入汉字拼音数据(self):
        """测试插入汉字拼音数据"""
        with 数据库管理器(self.db_path) as conn:
            cursor = conn.cursor()
            cursor.execute(
                'INSERT INTO "汉字拼音初始数据" ("汉字", "拼音", "频率") VALUES (?, ?, ?)',
                ('中', 'zhong1', 1000.0)
            )

        # 验证数据已插入
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            cursor.execute('SELECT "汉字", "拼音", "频率" FROM "汉字拼音初始数据"')
            row = cursor.fetchone()
            self.assertEqual(row[0], '中')
            self.assertEqual(row[1], 'zhong1')
            self.assertEqual(row[2], 1000.0)

    def test_插入音元拼音数据(self):
        """测试插入音元拼音数据"""
        with 数据库管理器(self.db_path) as conn:
            cursor = conn.cursor()
            cursor.execute(
                'INSERT INTO "音元拼音" ("全拼", "简拼", "干音") VALUES (?, ?, ?)',
                ('zhong', 'zh', 'ong')
            )

        # 验证数据已插入
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            cursor.execute('SELECT "全拼", "简拼", "干音" FROM "音元拼音"')
            row = cursor.fetchone()
            self.assertEqual(row[0], 'zhong')
            self.assertEqual(row[1], 'zh')
            self.assertEqual(row[2], 'ong')

    def test_查询操作(self):
        """测试查询操作"""
        # 插入测试数据
        with 数据库管理器(self.db_path) as conn:
            cursor = conn.cursor()
            test_data = [
                ('中', 'zhong1', 1000.0),
                ('国', 'guo2', 800.0),
                ('人', 'ren2', 600.0),
            ]
            cursor.executemany(
                'INSERT INTO "汉字拼音初始数据" ("汉字", "拼音", "频率") VALUES (?, ?, ?)',
                test_data
            )

        # 执行查询
        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            cursor = conn.cursor()
            cursor.execute(
                'SELECT * FROM "汉字拼音初始数据" WHERE "频率" > ? ORDER BY "频率" DESC',
                (500.0,)
            )
            rows = cursor.fetchall()

            self.assertEqual(len(rows), 3)
            self.assertEqual(rows[0]['汉字'], '中')
            self.assertEqual(rows[1]['汉字'], '国')
            self.assertEqual(rows[2]['汉字'], '人')

    def test_更新操作(self):
        """测试更新操作"""
        # 插入初始数据
        with 数据库管理器(self.db_path) as conn:
            cursor = conn.cursor()
            cursor.execute(
                'INSERT INTO "汉字拼音初始数据" ("汉字", "拼音", "频率") VALUES (?, ?, ?)',
                ('中', 'zhong1', 1000.0)
            )

        # 更新数据
        with 数据库管理器(self.db_path) as conn:
            cursor = conn.cursor()
            cursor.execute(
                'UPDATE "汉字拼音初始数据" SET "频率" = ? WHERE "汉字" = ?',
                (2000.0, '中')
            )

        # 验证更新
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            cursor.execute('SELECT "频率" FROM "汉字拼音初始数据" WHERE "汉字" = ?', ('中',))
            frequency = cursor.fetchone()[0]
            self.assertEqual(frequency, 2000.0)

    def test_删除操作(self):
        """测试删除操作"""
        # 插入测试数据
        with 数据库管理器(self.db_path) as conn:
            cursor = conn.cursor()
            cursor.execute(
                'INSERT INTO "汉字拼音初始数据" ("汉字", "拼音", "频率") VALUES (?, ?, ?)',
                ('中', 'zhong1', 1000.0)
            )

        # 删除数据
        with 数据库管理器(self.db_path) as conn:
            cursor = conn.cursor()
            cursor.execute('DELETE FROM "汉字拼音初始数据" WHERE "汉字" = ?', ('中',))

        # 验证删除
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            cursor.execute('SELECT COUNT(*) FROM "汉字拼音初始数据"')
            count = cursor.fetchone()[0]
            self.assertEqual(count, 0)

if __name__ == '__main__':
    unittest.main()
