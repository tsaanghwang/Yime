# yime/test_hanzi_db_manager.py
import unittest
import sqlite3
import gc
from pathlib import Path

class Test拼音信息(unittest.TestCase):
    """测试拼音信息数据类"""

    def test_拼音信息创建(self):
        """测试拼音信息创建"""
        from yime.hanzi_db_manager import 拼音信息

        info = 拼音信息(
            音元拼音="zhong",
            数字标调拼音="zhong1",
            标准拼音="zhōng",
            注音符号="ㄓㄨㄥ"
        )

        self.assertEqual(info.音元拼音, "zhong")
        self.assertEqual(info.数字标调拼音, "zhong1")
        self.assertEqual(info.标准拼音, "zhōng")
        self.assertEqual(info.注音符号, "ㄓㄨㄥ")

    def test_拼音信息相等性(self):
        """测试拼音信息相等性"""
        from yime.hanzi_db_manager import 拼音信息

        info1 = 拼音信息(
            音元拼音="zhong",
            数字标调拼音="zhong1",
            标准拼音="zhōng",
            注音符号="ㄓㄨㄥ"
        )

        info2 = 拼音信息(
            音元拼音="zhong",
            数字标调拼音="zhong1",
            标准拼音="zhōng",
            注音符号="ㄓㄨㄥ"
        )

        self.assertEqual(info1, info2)


class Test数据库管理器(unittest.TestCase):
    """测试汉字数据库管理器"""

    def setUp(self):
        """设置测试环境"""
        self.db_path = ":memory:"

    def tearDown(self):
        """清理测试环境"""
        gc.collect()

    def test_上下文管理器进入(self):
        """测试上下文管理器进入"""
        from yime.hanzi_db_manager import 数据库管理器

        with 数据库管理器(self.db_path) as conn:
            self.assertIsNotNone(conn)
            self.assertIsInstance(conn, sqlite3.Connection)

    def test_上下文管理器退出成功(self):
        """测试上下文管理器正常退出"""
        from yime.hanzi_db_manager import 数据库管理器

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


class Test表管理器(unittest.TestCase):
    """测试汉字表管理器"""

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
        from yime.hanzi_db_manager import 表管理器

        表管理器.创建表

    def test_创建表_表存在性(self):
        """测试表是否正确创建"""
        from yime.hanzi_db_manager import 表管理器

        表管理器.创建表

        cursor = self.conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table'")
        tables = [row[0] for row in cursor.fetchall()]

        # 验证关键表存在
        self.assertIn('汉字', tables)
        self.assertIn('汉字频率', tables)
        self.assertIn('词汇', tables)

    def test_创建表_重复调用(self):
        """测试重复创建表"""
        from yime.hanzi_db_manager import 表管理器

        # 第一次创建
        表管理器.创建表

        # 第二次创建（应该成功）
        表管理器.创建表

        # 验证表仍然存在
        cursor = self.conn.cursor()
        cursor.execute("SELECT COUNT(*) FROM sqlite_master WHERE type='table'")
        count = cursor.fetchone()[0]
        self.assertGreater(count, 0)


class Test数据库操作集成(unittest.TestCase):
    """集成测试：汉字数据库操作"""

    def setUp(self):
        """设置完整测试环境"""
        self.conn = sqlite3.connect(":memory:")

        from yime.hanzi_db_manager import 表管理器
        表管理器.创建表

    def tearDown(self):
        """清理测试环境"""
        if self.conn:
            self.conn.close()
        gc.collect()

    def test_插入汉字数据(self):
        """测试插入汉字数据"""
        cursor = self.conn.cursor()

        # 插入测试数据
        cursor.execute(
            'INSERT INTO 汉字 (编号, 字符, Unicode码点, 画数, 部首) VALUES (?, ?, ?, ?, ?)',
            (1, "中", "U+4E2D", 4, "丨")
        )
        self.conn.commit()

        # 验证数据已插入
        cursor.execute('SELECT COUNT(*) FROM 汉字')
        count = cursor.fetchone()[0]
        self.assertEqual(count, 1)

    def test_插入汉字频率数据(self):
        """测试插入汉字频率数据"""
        cursor = self.conn.cursor()

        # 先插入汉字
        cursor.execute(
            'INSERT INTO 汉字 (编号, 字符, Unicode码点) VALUES (?, ?, ?)',
            (1, "中", "U+4E2D")
        )

        # 插入频率数据
        cursor.execute(
            'INSERT INTO 汉字频率 (汉字编号, 绝对频率, 相对频率) VALUES (?, ?, ?)',
            (1, 1000, 0.05)
        )
        self.conn.commit()

        # 验证数据已插入
        cursor.execute('SELECT COUNT(*) FROM 汉字频率')
        count = cursor.fetchone()[0]
        self.assertEqual(count, 1)

    def test_插入词汇数据(self):
        """测试插入词汇数据"""
        cursor = self.conn.cursor()

        # 插入词汇
        cursor.execute(
            'INSERT INTO 词汇 (编号, 词语, 拼音序列) VALUES (?, ?, ?)',
            (1, "中国", "zhong1 guo2")
        )
        self.conn.commit()

        # 验证数据已插入
        cursor.execute('SELECT COUNT(*) FROM 词汇')
        count = cursor.fetchone()[0]
        self.assertEqual(count, 1)

    def test_查询汉字(self):
        """测试查询汉字"""
        cursor = self.conn.cursor()

        # 插入测试数据
        test_data = [
            (1, "中", "U+4E2D", 4, "丨"),
            (2, "国", "U+56FD", 8, "囗"),
            (3, "人", "U+4EBA", 2, "人"),
        ]
        cursor.executemany(
            'INSERT INTO 汉字 (编号, 字符, Unicode码点, 画数, 部首) VALUES (?, ?, ?, ?, ?)',
            test_data
        )
        self.conn.commit()

        # 查询特定汉字
        cursor.execute('SELECT 字符, 画数 FROM 汉字 WHERE 编号 = ?', (1,))
        row = cursor.fetchone()
        self.assertEqual(row[0], "中")
        self.assertEqual(row[1], 4)

    def test_更新汉字频率(self):
        """测试更新汉字频率"""
        cursor = self.conn.cursor()

        # 插入初始数据
        cursor.execute(
            'INSERT INTO 汉字 (编号, 字符, Unicode码点) VALUES (?, ?, ?)',
            (1, "中", "U+4E2D")
        )
        cursor.execute(
            'INSERT INTO 汉字频率 (汉字编号, 绝对频率, 相对频率) VALUES (?, ?, ?)',
            (1, 1000, 0.05)
        )
        self.conn.commit()

        # 更新频率
        cursor.execute(
            'UPDATE 汉字频率 SET 绝对频率 = ?, 相对频率 = ? WHERE 汉字编号 = ?',
            (2000, 0.10, 1)
        )
        self.conn.commit()

        # 验证更新
        cursor.execute('SELECT 绝对频率, 相对频率 FROM 汉字频率 WHERE 汉字编号 = ?', (1,))
        row = cursor.fetchone()
        self.assertEqual(row[0], 2000)
        self.assertEqual(row[1], 0.10)

    def test_删除汉字(self):
        """测试删除汉字"""
        cursor = self.conn.cursor()

        # 插入测试数据
        cursor.execute(
            'INSERT INTO 汉字 (编号, 字符, Unicode码点) VALUES (?, ?, ?)',
            (1, "中", "U+4E2D")
        )
        self.conn.commit()

        # 删除数据
        cursor.execute('DELETE FROM 汉字 WHERE 编号 = ?', (1,))
        self.conn.commit()

        # 验证删除
        cursor.execute('SELECT COUNT(*) FROM 汉字')
        count = cursor.fetchone()[0]
        self.assertEqual(count, 0)

    def test_唯一约束(self):
        """测试唯一约束"""
        cursor = self.conn.cursor()

        # 插入第一条数据
        cursor.execute(
            'INSERT INTO 汉字 (编号, 字符, Unicode码点) VALUES (?, ?, ?)',
            (1, "中", "U+4E2D")
        )
        self.conn.commit()

        # 尝试插入重复字符（应该失败）
        with self.assertRaises(sqlite3.IntegrityError):
            cursor.execute(
                'INSERT INTO 汉字 (编号, 字符, Unicode码点) VALUES (?, ?, ?)',
                (2, "中", "U+4E2D")
            )


if __name__ == '__main__':
    unittest.main()
