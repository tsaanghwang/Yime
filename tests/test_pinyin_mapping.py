# yime/test_pinyin_mapping.py
import unittest
import sqlite3
import tempfile
import os
from yime.pinyin_mapping import PinyinMapper

class TestPinyinMapper(unittest.TestCase):
    """测试拼音映射器"""

    def setUp(self):
        """设置测试数据库"""
        self.temp_db = tempfile.NamedTemporaryFile(delete=False, suffix='.db')
        self.db_path = self.temp_db.name
        self.temp_db.close()

        # 初始化测试数据库
        self._init_test_database()

        # 创建映射器实例
        self.mapper = PinyinMapper(db_path=self.db_path)

    def tearDown(self):
        """清理测试数据库"""
        if os.path.exists(self.db_path):
            try:
                os.unlink(self.db_path)
            except PermissionError:
                pass

    def _init_test_database(self):
        """初始化测试数据库结构"""
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()

            # 创建数字标调拼音表
            cursor.execute('''
                CREATE TABLE IF NOT EXISTS "数字标调拼音" (
                    "编号" INTEGER PRIMARY KEY AUTOINCREMENT,
                    "全拼" TEXT NOT NULL UNIQUE,
                    "声母" TEXT,
                    "韵母" TEXT,
                    "声调" INTEGER
                )
            ''')

            # 创建音元拼音表
            cursor.execute('''
                CREATE TABLE IF NOT EXISTS "音元拼音" (
                    "编号" INTEGER PRIMARY KEY AUTOINCREMENT,
                    "全拼" TEXT NOT NULL UNIQUE
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

            conn.commit()

    def test_init(self):
        """测试初始化"""
        self.assertEqual(self.mapper.db_path, self.db_path)

    def test_parse_pinyin_with_tone(self):
        """测试拼音解析（带声调）"""
        result = self.mapper._parse_pinyin("zhong1")
        self.assertEqual(result, ("zh", "ong", 1))

        result = self.mapper._parse_pinyin("guo2")
        self.assertEqual(result, ("g", "uo", 2))

    def test_parse_pinyin_without_tone(self):
        """测试拼音解析（无声调）"""
        result = self.mapper._parse_pinyin("zhong")
        self.assertEqual(result, ("zh", "ong", 1))

    def test_parse_pinyin_no_initial(self):
        """测试拼音解析（无声母）"""
        result = self.mapper._parse_pinyin("a1")
        self.assertEqual(result, ("", "a", 1))

    def test_parse_pinyin_various_initials(self):
        """测试拼音解析（各种声母）"""
        test_cases = [
            ("ba1", ("b", "a", 1)),
            ("pa2", ("p", "a", 2)),
            ("ma3", ("m", "a", 3)),
            ("fa4", ("f", "a", 4)),
            ("zhi1", ("zh", "i", 1)),
            ("chi2", ("ch", "i", 2)),
            ("shi3", ("sh", "i", 3)),
        ]
        for pinyin, expected in test_cases:
            result = self.mapper._parse_pinyin(pinyin)
            self.assertEqual(result, expected)

    def test_add_mapping_basic(self):
        """测试添加基本映射"""
        result = self.mapper.add_mapping("zhong1", "zhong")
        self.assertTrue(result)

    def test_add_mapping_duplicate(self):
        """测试添加重复映射"""
        # 第一次添加
        self.mapper.add_mapping("zhong1", "zhong")

        # 第二次添加（应该成功，使用 REPLACE）
        result = self.mapper.add_mapping("zhong1", "zhong")
        self.assertTrue(result)

    def test_add_mapping_multiple(self):
        """测试添加多个映射"""
        mappings = [
            ("zhong1", "zhong"),
            ("guo2", "guo"),
            ("ren2", "ren"),
        ]
        for digital, yinyuan in mappings:
            result = self.mapper.add_mapping(digital, yinyuan)
            self.assertTrue(result)

    def test_get_mapping_existing(self):
        """测试获取已存在的映射"""
        # 先添加映射
        self.mapper.add_mapping("zhong1", "zhong")

        # 获取映射
        result = self.mapper.get_mapping("zhong1")
        self.assertEqual(result, "zhong")

    def test_get_mapping_nonexistent(self):
        """测试获取不存在的映射"""
        result = self.mapper.get_mapping("nonexistent")
        self.assertIsNone(result)

    def test_get_mapping_after_multiple_adds(self):
        """测试添加多个映射后获取"""
        # 添加多个映射
        mappings = {
            "zhong1": "zhong",
            "guo2": "guo",
            "ren2": "ren",
        }
        for digital, yinyuan in mappings.items():
            self.mapper.add_mapping(digital, yinyuan)

        # 验证每个映射
        for digital, expected_yinyuan in mappings.items():
            result = self.mapper.get_mapping(digital)
            self.assertEqual(result, expected_yinyuan)

    def test_batch_add_mappings(self):
        """测试批量添加映射"""
        mappings = {
            "zhong1": "zhong",
            "guo2": "guo",
            "ren2": "ren",
            "min2": "min",
        }
        count = self.mapper.batch_add_mappings(mappings)
        self.assertEqual(count, len(mappings))

    def test_batch_add_mappings_partial_success(self):
        """测试批量添加映射（部分成功）"""
        mappings = {
            "zhong1": "zhong",
            "guo2": "guo",
        }
        count = self.mapper.batch_add_mappings(mappings)
        self.assertGreater(count, 0)
        self.assertLessEqual(count, len(mappings))

    def test_batch_add_mappings_empty(self):
        """测试批量添加空映射"""
        count = self.mapper.batch_add_mappings({})
        self.assertEqual(count, 0)

    def test_get_pinyin_id_existing(self):
        """测试获取已存在的拼音ID"""
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()

            # 插入测试数据
            cursor.execute(
                'INSERT INTO "数字标调拼音" ("全拼") VALUES (?)',
                ("test",)
            )
            test_id = cursor.lastrowid
            conn.commit()

            # 获取ID
            result_id = self.mapper._get_pinyin_id(cursor, "数字标调拼音", "test")
            self.assertEqual(result_id, test_id)

    def test_get_pinyin_id_nonexistent(self):
        """测试获取不存在的拼音ID"""
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            result_id = self.mapper._get_pinyin_id(cursor, "数字标调拼音", "nonexistent")
            self.assertIsNone(result_id)

    def test_mapping_roundtrip(self):
        """测试映射往返"""
        # 添加映射
        self.mapper.add_mapping("zhong1", "zhong")

        # 获取映射
        result = self.mapper.get_mapping("zhong1")

        # 验证往返一致
        self.assertEqual(result, "zhong")

    def test_mapping_update(self):
        """测试映射更新"""
        # 添加初始映射
        self.mapper.add_mapping("zhong1", "zhong")

        # 更新映射
        self.mapper.add_mapping("zhong1", "zhong_new")

        # 获取更新后的映射
        result = self.mapper.get_mapping("zhong1")
        self.assertEqual(result, "zhong_new")

if __name__ == '__main__':
    unittest.main()
