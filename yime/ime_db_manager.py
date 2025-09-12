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
class 拼音信息:
    数字拼音: str
    标准拼音: str
    注音符号: str

class 数据库管理器:
    """封装数据库连接和基本操作"""
    def __init__(self, 数据库路径: str):
        self.数据库路径 = Path(数据库路径)

    def __enter__(self):
        self.连接 = sqlite3.connect(self.数据库路径)
        self.连接.execute("PRAGMA journal_mode=WAL")
        self.连接.isolation_level = None
        return self.连接

    def __exit__(self, exc_type, exc_val, exc_tb):
        if exc_type is None:
            self.连接.commit()
        self.连接.close()

class 表管理器:
    """管理数据库表结构和索引"""
    @staticmethod
    def 创建表(连接: sqlite3.Connection) -> None:
        """创建所有必要的数据库表"""
        游标 = 连接.cursor()

        # 创建新表结构
        表定义 = {
            '汉字': '''
                CREATE TABLE IF NOT EXISTS 汉字 (
                    id INTEGER PRIMARY KEY,
                    字符 TEXT NOT NULL UNIQUE,
                    Unicode编码 TEXT NOT NULL,
                    笔画数 INTEGER,
                    部首 TEXT,
                    常用字 BOOLEAN DEFAULT 1,
                    创建时间 TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )''',
            '拼音': '''
                CREATE TABLE IF NOT EXISTS 拼音 (
                    id INTEGER PRIMARY KEY,
                    拼音 TEXT NOT NULL UNIQUE,
                    声母 TEXT,
                    韵母 TEXT,
                    声调 INTEGER,
                    创建时间 TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )''',
            '汉字拼音映射': '''
                CREATE TABLE IF NOT EXISTS 汉字拼音映射 (
                    汉字id INTEGER REFERENCES 汉字(id),
                    拼音id INTEGER REFERENCES 拼音(id),
                    频率 FLOAT DEFAULT 1.0,
                    主读音 BOOLEAN DEFAULT 0,
                    PRIMARY KEY (汉字id, 拼音id)
                )''',
            '汉字频率': '''
                CREATE TABLE IF NOT EXISTS 汉字频率 (
                    汉字id INTEGER PRIMARY KEY REFERENCES 汉字(id),
                    绝对频率 INTEGER,
                    相对频率 FLOAT,
                    语料来源 TEXT,
                    最后更新时间 TIMESTAMP
                )''',
            '词汇': '''
                CREATE TABLE IF NOT EXISTS 词汇 (
                    id INTEGER PRIMARY KEY,
                    词语 TEXT NOT NULL,
                    拼音 TEXT NOT NULL,
                    频率 FLOAT,
                    长度 INTEGER,
                    常用词 BOOLEAN DEFAULT 1,
                    创建时间 TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )'''
        }

        for 表名, 定义 in 表定义.items():
            游标.execute(定义)

        # 创建索引
        索引 = [
            ('索引_汉字_字符', '汉字(字符)'),
            ('索引_拼音_拼音', '拼音(拼音)'),
            ('索引_汉字拼音映射_汉字', '汉字拼音映射(汉字id)'),
            ('索引_汉字拼音映射_拼音', '汉字拼音映射(拼音id)'),
            ('索引_词汇_词语', '词汇(词语)'),
            ('索引_词汇_拼音', '词汇(拼音)')
        ]

        for 名称, 列 in 索引:
            游标.execute(f"CREATE INDEX IF NOT EXISTS {名称} ON {列}")

        logger.info("数据库表结构创建/验证完成")

class 数据库迁移器:
    """重构后的主迁移类"""
    def __init__(self, 数据库路径: str = None):
        self.数据库路径 = Path(数据库路径) if 数据库路径 else Path(__file__).parent / "pinyin_hanzi.db"

    def 迁移(self) -> None:
        """执行完整的数据迁移流程"""
        开始时间 = time.time()

        try:
            with sqlite3.connect(str(self.数据库路径)) as 连接:
                # 启用WAL模式提高并发性能
                连接.execute("PRAGMA journal_mode=WAL")
                连接.isolation_level = None  # 禁用自动事务

                # 创建表结构
                表管理器.创建表(连接)

                # 优化数据库
                连接.execute("VACUUM")

                总耗时 = time.time() - 开始时间
                logger.info(f"数据库表结构初始化完成! 耗时: {总耗时:.2f}秒")

        except Exception as e:
            logger.error(f"数据库初始化失败: {e}")
            raise

if __name__ == "__main__":
    迁移器 = 数据库迁移器()
    迁移器.迁移()