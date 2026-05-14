# yime/test_pinyin_converter.py
import unittest
import sqlite3
import tempfile
import os
from pathlib import Path
from yime.pinyin_converter import PinyinConverter

class TestPinyinConverter(unittest.TestCase):
    """测试拼音转换器"""

    def setUp(self):
        """设置测试数据库"""
        # 创建临时数据库
        self.temp_db = tempfile.NamedTemporaryFile(delete=False, suffix='.db')
        self.db_path = self.temp_db.name
        self.temp_db.close()

        # 初始化测试数据
        self._init_test_database()

        # 创建转换器实例
        self.converter = PinyinConverter(db_path=self.db_path)

    def tearDown(self):
        """清理测试数据库"""
        if os.path.exists(self.db_path):
            try:
                os.unlink(self.db_path)
            except PermissionError:
                pass  # Windows 文件锁定，忽略

    def _init_test_database(self):
        """初始化测试数据库结构"""
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()

            # 创建数字标调拼音表
            cursor.execute('''
                CREATE TABLE IF NOT EXISTS "数字标调拼音" (
                    "编号" INTEGER PRIMARY KEY,
                    "全拼" TEXT NOT NULL
                )
            ''')

            # 创建音元拼音表
            cursor.execute('''
                CREATE TABLE IF NOT EXISTS "音元拼音" (
                    "编号" INTEGER PRIMARY KEY,
                    "全拼" TEXT NOT NULL,
                    "简拼" TEXT,
                    "干音" TEXT
                )
            ''')

            # 创建拼音映射表
            cursor.execute('''
                CREATE TABLE IF NOT EXISTS "拼音映射" (
                    "音元拼音" INTEGER,
                    "数字标调拼音" INTEGER,
                    "标准拼音" TEXT,
                    "注音符号" TEXT,
                    PRIMARY KEY ("音元拼音", "数字标调拼音")
                )
            ''')

            # 插入测试数据
            test_pinyins = [
                (1, "zhong1"),
                (2, "guo2"),
                (3, "ren2"),
                (4, "min2"),
                (5, "bei3"),
                (6, "jing1"),
                (7, "shang4"),
                (8, "hai3"),
            ]
            cursor.executemany(
                'INSERT INTO "数字标调拼音" ("编号", "全拼") VALUES (?, ?)',
                test_pinyins
            )

            conn.commit()

    def test_init_default_db_path(self):
        """测试默认数据库路径初始化"""
        converter = PinyinConverter()
        self.assertEqual(converter.db_path, "pinyin_hanzi.db")

    def test_init_custom_db_path(self):
        """测试自定义数据库路径初始化"""
        self.assertEqual(self.converter.db_path, self.db_path)

    def test_convert_pinyin_basic(self):
        """测试基本拼音转换"""
        # 测试转换函数
        result = self.converter._convert_pinyin("zhong1")
        self.assertIsNotNone(result)
        self.assertEqual(result, "zhong1")  # 当前实现返回原值

    def test_convert_pinyin_various_tones(self):
        """测试不同声调的拼音转换"""
        test_cases = [
            ("zhong1", "zhong1"),
            ("guo2", "guo2"),
            ("bei3", "bei3"),
            ("shang4", "shang4"),
        ]
        for input_pinyin, expected in test_cases:
            result = self.converter._convert_pinyin(input_pinyin)
            self.assertEqual(result, expected)

    def test_convert_pinyin_empty(self):
        """测试空字符串转换"""
        result = self.converter._convert_pinyin("")
        self.assertEqual(result, "")

    def test_convert_pinyin_special_cases(self):
        """测试特殊情况转换"""
        # 测试带数字的拼音
        result = self.converter._convert_pinyin("a1")
        self.assertEqual(result, "a1")

        # 测试长拼音
        result = self.converter._convert_pinyin("zhuang1")
        self.assertEqual(result, "zhuang1")

    def test_get_zhuyin(self):
        """测试注音符号获取"""
        zhuyin = self.converter._get_zhuyin("zhong1")
        self.assertIsNotNone(zhuyin)
        self.assertIsInstance(zhuyin, str)
        self.assertEqual(zhuyin, "ㄓㄨˋ ㄧㄣ")  # 当前实现返回固定值

    def test_get_zhuyin_different_pinyins(self):
        """测试不同拼音的注音符号获取"""
        test_pinyins = ["zhong1", "guo2", "ren2", "min2"]
        for pinyin in test_pinyins:
            zhuyin = self.converter._get_zhuyin(pinyin)
            self.assertIsInstance(zhuyin, str)
            self.assertGreater(len(zhuyin), 0)

    def test_convert_all_with_empty_db(self):
        """测试空数据库转换"""
        # 清空测试数据
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            cursor.execute('DELETE FROM "数字标调拼音"')
            conn.commit()

        # 执行转换
        count = self.converter.convert_all()
        self.assertEqual(count, 0)

    def test_convert_all_with_test_data(self):
        """测试完整转换流程"""
        # 执行转换
        count = self.converter.convert_all()

        # 验证转换数量
        self.assertGreater(count, 0)
        self.assertLessEqual(count, 8)  # 最多8条测试数据

        # 验证数据库记录
        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            cursor = conn.cursor()

            # 检查音元拼音表
            cursor.execute('SELECT COUNT(*) as count FROM "音元拼音"')
            yinyuan_count = cursor.fetchone()['count']
            self.assertGreater(yinyuan_count, 0)

            # 检查拼音映射表
            cursor.execute('SELECT COUNT(*) as count FROM "拼音映射"')
            mapping_count = cursor.fetchone()['count']
            self.assertEqual(mapping_count, count)

    def test_convert_all_idempotent(self):
        """测试转换的幂等性（多次转换结果一致）"""
        # 第一次转换
        count1 = self.converter.convert_all()

        # 第二次转换（应该不会创建重复记录）
        count2 = self.converter.convert_all()

        # 验证结果一致
        self.assertEqual(count1, count2)

    def test_get_or_create_yinyuan_existing(self):
        """测试获取已存在的音元拼音"""
        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            cursor = conn.cursor()

            # 先创建一条记录
            cursor.execute(
                'INSERT INTO "音元拼音" ("全拼", "简拼", "干音") VALUES (?, ?, ?)',
                ("test", "t", "test")
            )
            existing_id = cursor.lastrowid
            conn.commit()

            # 再次获取应该返回相同ID
            result_id = self.converter._get_or_create_yinyuan(cursor, "test")
            self.assertEqual(result_id, existing_id)

    def test_get_or_create_yinyuan_new(self):
        """测试创建新的音元拼音"""
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()

            # 创建新记录
            new_id = self.converter._get_or_create_yinyuan(cursor, "new_pinyin")

            # 验证记录已创建
            cursor.execute(
                'SELECT "全拼", "简拼", "干音" FROM "音元拼音" WHERE "编号" = ?',
                (new_id,)
            )
            row = cursor.fetchone()
            self.assertIsNotNone(row)
            self.assertEqual(row[0], "new_pinyin")
            self.assertEqual(row[1], "n")  # 简拼应为首字母

    def test_get_or_create_yinyuan_multiple(self):
        """测试创建多个音元拼音"""
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()

            pinyins = ["pinyin1", "pinyin2", "pinyin3"]
            ids = []

            for pinyin in pinyins:
                id = self.converter._get_or_create_yinyuan(cursor, pinyin)
                ids.append(id)

            # 验证所有ID都是唯一的
            self.assertEqual(len(ids), len(set(ids)))

    def test_create_mapping(self):
        """测试创建映射关系"""
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()

            # 准备测试数据
            cursor.execute(
                'INSERT INTO "音元拼音" ("全拼", "简拼", "干音") VALUES (?, ?, ?)',
                ("test", "t", "test")
            )
            yinyuan_id = cursor.lastrowid

            # 创建映射
            self.converter._create_mapping(cursor, yinyuan_id, 1, "test1")

            # 验证映射已创建
            cursor.execute(
                'SELECT COUNT(*) FROM "拼音映射" WHERE "音元拼音" = ? AND "数字标调拼音" = ?',
                (yinyuan_id, 1)
            )
            count = cursor.fetchone()[0]
            self.assertEqual(count, 1)

    def test_create_mapping_duplicate(self):
        """测试创建重复映射（应该被忽略）"""
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()

            # 准备测试数据
            cursor.execute(
                'INSERT INTO "音元拼音" ("全拼", "简拼", "干音") VALUES (?, ?, ?)',
                ("test", "t", "test")
            )
            yinyuan_id = cursor.lastrowid

            # 创建映射
            self.converter._create_mapping(cursor, yinyuan_id, 1, "test1")

            # 尝试创建重复映射
            self.converter._create_mapping(cursor, yinyuan_id, 1, "test1")

            # 验证只有一条映射
            cursor.execute(
                'SELECT COUNT(*) FROM "拼音映射" WHERE "音元拼音" = ? AND "数字标调拼音" = ?',
                (yinyuan_id, 1)
            )
            count = cursor.fetchone()[0]
            self.assertEqual(count, 1)

if __name__ == '__main__':
    unittest.main()
