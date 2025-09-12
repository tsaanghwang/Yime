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

        # 创建新表结构
        tables = {
            'hanzi': '''
                CREATE TABLE IF NOT EXISTS hanzi (
                    id INTEGER PRIMARY KEY,
                    character TEXT NOT NULL UNIQUE,
                    unicode_hex TEXT NOT NULL,
                    stroke_count INTEGER,
                    radical TEXT,
                    is_common BOOLEAN DEFAULT 1,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )''',
            'pinyin': '''
                CREATE TABLE IF NOT EXISTS pinyin (
                    id INTEGER PRIMARY KEY,
                    pinyin TEXT NOT NULL UNIQUE,
                    initial TEXT,
                    final TEXT,
                    tone INTEGER,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )''',
            'hanzi_pinyin': '''
                CREATE TABLE IF NOT EXISTS hanzi_pinyin (
                    hanzi_id INTEGER REFERENCES hanzi(id),
                    pinyin_id INTEGER REFERENCES pinyin(id),
                    frequency FLOAT DEFAULT 1.0,
                    is_primary BOOLEAN DEFAULT 0,
                    PRIMARY KEY (hanzi_id, pinyin_id)
                )''',
            'character_frequency': '''
                CREATE TABLE IF NOT EXISTS character_frequency (
                    hanzi_id INTEGER PRIMARY KEY REFERENCES hanzi(id),
                    absolute_freq INTEGER,
                    relative_freq FLOAT,
                    corpus_source TEXT,
                    last_updated TIMESTAMP
                )''',
            'vocabulary': '''
                CREATE TABLE IF NOT EXISTS vocabulary (
                    id INTEGER PRIMARY KEY,
                    phrase TEXT NOT NULL,
                    pinyin TEXT NOT NULL,
                    frequency FLOAT,
                    length INTEGER,
                    is_common BOOLEAN DEFAULT 1,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )'''
        }

        for table, ddl in tables.items():
            cursor.execute(ddl)

        # 创建索引
        indexes = [
            ('idx_hanzi_character', 'hanzi(character)'),
            ('idx_pinyin_pinyin', 'pinyin(pinyin)'),
            ('idx_hanzi_pinyin_hanzi', 'hanzi_pinyin(hanzi_id)'),
            ('idx_hanzi_pinyin_pinyin', 'hanzi_pinyin(pinyin_id)'),
            ('idx_vocabulary_phrase', 'vocabulary(phrase)'),
            ('idx_vocabulary_pinyin', 'vocabulary(pinyin)')
        ]

        for name, columns in indexes:
            cursor.execute(f"CREATE INDEX IF NOT EXISTS {name} ON {columns}")

        logger.info("新数据库表结构创建/验证完成")

class DatabaseMigrator:
    """重构后的主迁移类"""
    def __init__(self, db_path: str = None):
        self.db_path = Path(db_path) if db_path else Path(__file__).parent / "pinyin_hanzi.db"

    def migrate(self) -> None:
        """执行完整的数据迁移流程"""
        start_time = time.time()

        try:
            with sqlite3.connect(str(self.db_path)) as conn:
                # 启用WAL模式提高并发性能
                conn.execute("PRAGMA journal_mode=WAL")
                conn.isolation_level = None  # 禁用自动事务

                # 创建表结构
                TableManager.create_tables(conn)

                # 优化数据库
                conn.execute("VACUUM")

                total_time = time.time() - start_time
                logger.info(f"数据库表结构初始化完成! 耗时: {total_time:.2f}秒")

        except Exception as e:
            logger.error(f"数据库初始化失败: {e}")
            raise

if __name__ == "__main__":
    migrator = DatabaseMigrator()
    migrator.migrate()