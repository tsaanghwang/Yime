# yime/db_migration.py (重构版)
import sqlite3
import time
import logging
import sys
from pathlib import Path
from dataclasses import dataclass

# 确保能正确导入utils模块
utils_path = Path("c:/Users/Freeman Golden/OneDrive/Yime/utils")
if utils_path.exists():
    sys.path.insert(0, str(utils_path))

from utils.pinyin_normalizer import PinyinNormalizer
from utils.pinyin_zhuyin import PinyinZhuyinConverter

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

@dataclass
class PinyinInfo:
    numeric_pinyin: str
    standard_pinyin: str
    zhuyin: str

class DatabaseManager:
    """封装数据库连接和基本操作"""
    def __init__(self, db_path: str):
        self.db_path = Path(db_path)

    def __enter__(self):
        self.conn = sqlite3.connect(self.db_path)
        self.conn.execute("PRAGMA journal_mode=WAL")
        self.conn.isolation_level = None
        return self.conn

    def __exit__(self, exc_type, exc_val, exc_tb):
        if exc_type is None:
            self.conn.commit()
        self.conn.close()

class TableManager:
    """管理数据库表结构和索引"""
    @staticmethod
    def create_tables(conn: sqlite3.Connection) -> None:
        """创建所有必要的数据库表"""
        cursor = conn.cursor()

        tables = {
            'yinjie_mapping': '''
                CREATE TABLE IF NOT EXISTS yinjie_mapping (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    numeric_pinyin TEXT NOT NULL,
                    standard_pinyin TEXT NOT NULL,
                    zhuyin TEXT NOT NULL,
                    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    UNIQUE(numeric_pinyin)
                )''',
            'yinjie_reverse': '''
                CREATE TABLE IF NOT EXISTS yinjie_reverse (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    standard_pinyin TEXT NOT NULL,
                    numeric_pinyin TEXT NOT NULL,
                    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    UNIQUE(standard_pinyin, numeric_pinyin)
                )'''
        }

        for table, ddl in tables.items():
            cursor.execute(f"DROP TABLE IF EXISTS {table}")
            cursor.execute(ddl)

        # 创建索引
        indexes = [
            ('idx_yinjie_mapping_numeric', 'yinjie_mapping(numeric_pinyin)'),
            ('idx_yinjie_mapping_standard', 'yinjie_mapping(standard_pinyin)'),
            ('idx_yinjie_reverse_standard', 'yinjie_reverse(standard_pinyin)'),
            ('idx_yinjie_reverse_numeric', 'yinjie_reverse(numeric_pinyin)')
        ]

        for name, columns in indexes:
            cursor.execute(f"CREATE INDEX IF NOT EXISTS {name} ON {columns}")

        logger.info("数据库表结构创建/验证完成")

class DataImporter:
    """处理数据导入逻辑"""
    @staticmethod
    def import_yinjie_data(conn: sqlite3.Connection) -> int:
        """从code_to_pinyin表导入并处理数据"""
        cursor = conn.cursor()

        # 获取所有唯一拼音
        cursor.execute("SELECT DISTINCT pinyin FROM code_to_pinyin")
        pinyin_list = [row[0] for row in cursor.fetchall()]

        if not pinyin_list:
            logger.error("从code_to_pinyin表获取的拼音列表为空")
            return 0

        # 处理拼音数据
        normalized_dict, _ = PinyinNormalizer.process_pinyin_dict({p: p for p in pinyin_list})
        zhuyin_dict, _ = PinyinZhuyinConverter.process_pinyin_dict({p: p for p in pinyin_list})

        # 批量插入数据
        batch_size = 100
        total = 0

        for i in range(0, len(pinyin_list), batch_size):
            batch = pinyin_list[i:i+batch_size]
            try:
                # 准备批量插入数据
                mapping_data = [
                    (p, normalized_dict.get(p, p), zhuyin_dict.get(p, ''))
                    for p in batch
                ]

                reverse_data = [
                    (normalized_dict.get(p, p), p)
                    for p in batch
                ]

                # 执行批量插入
                cursor.executemany('''
                    INSERT OR REPLACE INTO yinjie_mapping
                    (numeric_pinyin, standard_pinyin, zhuyin)
                    VALUES (?, ?, ?)
                ''', mapping_data)

                cursor.executemany('''
                    INSERT OR REPLACE INTO yinjie_reverse
                    (standard_pinyin, numeric_pinyin)
                    VALUES (?, ?)
                ''', reverse_data)

                total += len(batch)
                logger.debug(f"已处理 {total}/{len(pinyin_list)} 条记录")

            except sqlite3.Error as e:
                logger.error(f"批量导入失败: {e}")
                conn.rollback()
                raise

        logger.info(f"成功导入 {total} 条音元映射")
        return total

class DatabaseMigrator:
    """重构后的主迁移类"""
    def __init__(self, db_path: str = None):
        self.db_path = Path(db_path) if db_path else Path(__file__).parent / "pinyin_hanzi.db"

    def migrate(self) -> None:
        """执行完整的数据迁移流程"""
        start_time = time.time()

        try:
            # 将Path对象转换为字符串
            with sqlite3.connect(str(self.db_path)) as conn:
                # 启用WAL模式提高并发性能
                conn.execute("PRAGMA journal_mode=WAL")
                conn.isolation_level = None  # 禁用自动事务

                # 创建表结构
                TableManager.create_tables(conn)

                # 导入数据
                count = DataImporter.import_yinjie_data(conn)

                # 优化数据库
                conn.execute("VACUUM")

                total_time = time.time() - start_time
                logger.info(
                    f"数据迁移完成! 音元记录: {count}, 耗时: {total_time:.2f}秒"
                )

        except Exception as e:
            logger.error(f"数据迁移失败: {e}")
            raise



    def query_pinyin_info(self, pinyin: str) -> dict:
        """查询拼音的详细信息"""
        with sqlite3.connect(str(self.db_path)) as conn:
            cursor = conn.cursor()

            # 查询标准拼音信息
            cursor.execute('''
                SELECT numeric_pinyin, standard_pinyin, zhuyin
                FROM yinjie_mapping
                WHERE numeric_pinyin = ? OR standard_pinyin = ?
            ''', (pinyin, pinyin))

            result = cursor.fetchone()

            # 始终返回字典，即使查询不到结果
            return {
                'numeric_pinyin': result[0] if result else '',
                'standard_pinyin': result[1] if result else '',
                'zhuyin': result[2] if result else ''
            }

    def query_by_code(self, code: str) -> dict:
        """通过code查询所有拼音格式"""
        with sqlite3.connect(str(self.db_path)) as conn:
            cursor = conn.cursor()

            # 查询code对应的数字拼音
            cursor.execute('''
                SELECT pinyin
                FROM code_to_pinyin
                WHERE code = ?
            ''', (code,))
            numeric_pinyin = cursor.fetchone()

            if not numeric_pinyin:
                return {}

            # 查询所有拼音格式
            cursor.execute('''
                SELECT
                    c.pinyin AS numeric_pinyin,
                    m.standard_pinyin,
                    m.zhuyin
                FROM code_to_pinyin c
                JOIN yinjie_mapping m ON c.pinyin = m.numeric_pinyin
                WHERE c.code = ?
            ''', (code,))

            result = cursor.fetchone()
            return {
                'code': code,
                'numeric_pinyin': result[0],
                'standard_pinyin': result[1],
                'zhuyin': result[2]
            } if result else {}

    def query_by_pinyin(self, pinyin: str) -> list:
        """通过拼音反向查询所有对应的code"""
        with sqlite3.connect(str(self.db_path)) as conn:
            cursor = conn.cursor()

            # 先确定输入的是哪种拼音格式
            cursor.execute('''
                SELECT numeric_pinyin
                FROM yinjie_mapping
                WHERE numeric_pinyin = ? OR standard_pinyin = ?
            ''', (pinyin, pinyin))

            numeric_pinyin = cursor.fetchone()
            if not numeric_pinyin:
                return []

            # 查询所有对应的code
            cursor.execute('''
                SELECT DISTINCT code
                FROM code_to_pinyin
                WHERE pinyin = ?
            ''', (numeric_pinyin[0],))

            return [row[0] for row in cursor.fetchall()]

if __name__ == "__main__":
    migrator = DatabaseMigrator()
    migrator.migrate()

    # 测试通过code查询
    test_code = "1234"  # 替换为实际code
    code_result = migrator.query_by_code(test_code)
    print(f"\n通过code '{test_code}'查询结果:")
    if code_result:
        print(f"数字拼音: {code_result['numeric_pinyin']}")
        print(f"标准拼音: {code_result['standard_pinyin']}")
        print(f"注音符号: {code_result['zhuyin']}")
    else:
        print(f"未找到code '{test_code}'的信息")

    # 测试通过拼音反向查询
    test_pinyin = "ni3"  # 替换为实际拼音
    pinyin_result = migrator.query_by_pinyin(test_pinyin)
    print(f"\n通过拼音 '{test_pinyin}'反向查询结果:")
    if pinyin_result:
        print("对应的code列表:", pinyin_result)
    else:
        print(f"未找到拼音 '{test_pinyin}'对应的code")