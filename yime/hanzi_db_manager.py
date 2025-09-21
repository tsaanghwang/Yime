import sqlite3
import time
import logging
from pathlib import Path
from dataclasses import dataclass

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

@dataclass
class 拼音信息:
    音元拼音: str
    数字标调拼音: str
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
                    编号 INTEGER PRIMARY KEY,
                    字符 TEXT NOT NULL UNIQUE,
                    Unicode码点 TEXT NOT NULL,
                    画数 INTEGER,
                    部首 TEXT,
                    常用字 BOOLEAN DEFAULT 1,
                    最近更新 TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )''',
            '汉字音元拼音映射': '''
                CREATE TABLE IF NOT EXISTS 汉字音元拼音映射 (
                    汉字编号 INTEGER REFERENCES 汉字(编号),
                    音元拼音编号 INTEGER REFERENCES 音元拼音(编号),
                    频率 FLOAT DEFAULT 1.0,
                    常用读音 BOOLEAN DEFAULT 0,
                    PRIMARY KEY (汉字编号, 音元拼音编号)
                )''',
            '汉字数字标调拼音映射': '''
                CREATE TABLE IF NOT EXISTS 汉字数字标调拼音映射 (
                    汉字编号 INTEGER REFERENCES 汉字(编号),
                    数字标调拼音编号 INTEGER REFERENCES 数字标调拼音(编号),
                    频率 FLOAT DEFAULT 1.0,
                    常用读音 BOOLEAN DEFAULT 0,
                    PRIMARY KEY (汉字编号, 数字标调拼音编号)
                )''',
            '汉字频率': '''
                CREATE TABLE IF NOT EXISTS 汉字频率 (
                    汉字编号 INTEGER PRIMARY KEY REFERENCES 汉字(编号),
                    绝对频率 INTEGER,
                    相对频率 FLOAT,
                    语料来源 TEXT,
                    最近更新 TIMESTAMP
                )''',
            '词汇': '''
                CREATE TABLE IF NOT EXISTS 词汇 (
                    编号 INTEGER PRIMARY KEY,
                    词语 TEXT NOT NULL,
                    音元拼音 TEXT NOT NULL,
                    频率 FLOAT,
                    长度 INTEGER,
                    常用词语 BOOLEAN DEFAULT 1,
                    最近更新 TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )'''
        }

        for 表名, 定义 in 表定义.items():
            游标.execute(f"DROP TABLE IF EXISTS {表名}")
            游标.execute(定义)

        # 创建索引
        索引 = [
            ('索引_汉字_字符', '汉字(字符)'),
            ('索引_汉字音元拼音映射_汉字', '汉字音元拼音映射(汉字编号)'),
            ('索引_汉字音元拼音映射_音元拼音', '汉字音元拼音映射(音元拼音编号)'),
            ('索引_汉字数字标调拼音映射_汉字', '汉字数字标调拼音映射(汉字编号)'),
            ('索引_汉字数字标调拼音映射_数字标调拼音', '汉字数字标调拼音映射(数字标调拼音编号)'),
            ('索引_词汇_词语', '词汇(词语)'),
            ('索引_词汇_音元拼音', '词汇(音元拼音)')
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
