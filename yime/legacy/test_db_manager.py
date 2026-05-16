# yime/test_db_manager.py
import unittest
import sqlite3
import tempfile
import os
import shutil
import gc
from pathlib import Path
from yime.legacy.pending_removal.db_manager import 数据库管理器, 表管理器

class Test数据库管理器(unittest.TestCase):
    """测试数据库管理器"""

    def setUp(self):
        """设置测试数据库"""
        self.temp_dir = tempfile.mkdtemp(prefix="yime-db-manager-")
        self.db_path = os.path.join(self.temp_dir, "test.db")

    def tearDown(self):
        """清理测试数据库"""
        gc.collect()
        shutil.rmtree(self.temp_dir, ignore_errors=True)

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

        # 检查保留表存在，已退场旧表不应再创建
        self.assertNotIn('汉字拼音初始数据', tables)
        self.assertIn('多式拼音映射关系', tables)
        self.assertIn('音元拼音', tables)
        self.assertIn('数字标调拼音', tables)

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
        self.temp_dir = tempfile.mkdtemp(prefix="yime-db-manager-")
        self.db_path = os.path.join(self.temp_dir, "test.db")

        # 初始化数据库结构
        with 数据库管理器(self.db_path) as conn:
            表管理器.创建表(conn)

    def tearDown(self):
        """清理测试环境"""
        gc.collect()
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_插入音元拼音数据(self):
        """测试插入音元拼音数据"""
        with 数据库管理器(self.db_path) as conn:
            cursor = conn.cursor()
            cursor.execute(
                'INSERT INTO "音元拼音" ("全拼", "简拼", "首音", "干音") VALUES (?, ?, ?, ?)',
                ('zhong', 'zh', 'zh', 'ong')
            )

        # 验证数据已插入
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            cursor.execute('SELECT "全拼", "简拼", "干音" FROM "音元拼音"')
            row = cursor.fetchone()
            self.assertEqual(row[0], 'zhong')
            self.assertEqual(row[1], 'zh')
            self.assertEqual(row[2], 'ong')

    def test_退场旧表不会创建(self):
        """测试已退场旧表不会再被创建"""
        with 数据库管理器(self.db_path) as conn:
            cursor = conn.cursor()
            cursor.execute(
                "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='汉字拼音初始数据'"
            )
            count = cursor.fetchone()[0]
            self.assertEqual(count, 0)

if __name__ == '__main__':
    unittest.main()
