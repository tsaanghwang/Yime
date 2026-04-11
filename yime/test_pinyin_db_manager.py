# yime/test_pinyin_db_manager.py
import unittest
import sqlite3
import gc

class Test表管理器(unittest.TestCase):
    """测试拼音数据库表管理器"""

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
        from yime.pinyin_db_manager import 表管理器

        # 创建表不应抛出异常
        try:
            表管理器.创建表
        except Exception as e:
            self.fail(f"创建表失败: {e}")


class Test数据导入器(unittest.TestCase):
    """测试数据导入器"""

    def setUp(self):
        """设置测试环境"""
        self.conn = sqlite3.connect(":memory:")

        from yime.pinyin_db_manager import 表管理器
        表管理器.创建表

    def tearDown(self):
        """清理测试环境"""
        if self.conn:
            self.conn.close()
        gc.collect()

    def test_导入音元数据_空列表(self):
        """测试导入空数据"""
        from yime.pinyin_db_manager import 数据导入器

        # 导入空数据应该返回0
        count = 数据导入器.导入音元数据
        self.assertEqual(count, 0)


if __name__ == '__main__':
    unittest.main()
