import sqlite3
import logging
from pathlib import Path

logger = logging.getLogger(__name__)
logger.setLevel(logging.DEBUG)
handler = logging.StreamHandler()
handler.setFormatter(logging.Formatter('%(asctime)s - %(levelname)s - %(message)s'))
if not logger.hasHandlers():
    logger.addHandler(handler)

# 统一数据库路径为 yime\pinyin_hanzi.db
DB_PATH = Path(__file__).parent / "pinyin_hanzi.db"

class 数据库管理器:
    """封装数据库连接和基本操作"""
    def __init__(self, 数据库路径: str):
        self.数据库路径 = Path(数据库路径)

    def __enter__(self):
        self.连接 = sqlite3.connect(str(self.数据库路径))
        self.连接.execute("PRAGMA journal_mode=WAL")
        self.连接.isolation_level = None
        return self.连接

    def __exit__(self, exc_type, exc_val, exc_tb):
        if exc_type is None:
            self.连接.commit()
        self.连接.close()

class 表管理器:
    """管理所有数据库表结构和索引"""
    @staticmethod
    def 创建表(连接: sqlite3.Connection) -> None:
        """创建所有必要的数据库表（使用双引号保护标识符以避免解析问题）"""
        游标 = 连接.cursor()

        # 拼音相关表
        表结构 = {
            '汉字拼音初始数据': '''
                CREATE TABLE IF NOT EXISTS "汉字拼音初始数据" (
                    "汉字" TEXT NOT NULL,
                    "拼音" TEXT NOT NULL,
                    "频率" FLOAT DEFAULT 1.0,
                    "常用读音" BOOLEAN DEFAULT 0,
                    "来源" TEXT,
                    PRIMARY KEY ("汉字", "拼音")
                )
            ''',
            '拼音映射关系': '''
                CREATE TABLE IF NOT EXISTS "拼音映射关系" (
                    "映射编号" INTEGER PRIMARY KEY AUTOINCREMENT,
                    "原拼音类型" TEXT NOT NULL,
                    "原拼音" TEXT NOT NULL,
                    "目标拼音类型" TEXT NOT NULL,
                    "目标拼音" TEXT NOT NULL,
                    "数据来源" TEXT,
                    "版本号" TEXT,
                    "备注" TEXT,
                    "创建时间" TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    UNIQUE("原拼音类型", "原拼音", "目标拼音类型", "目标拼音", "数据来源")
                )
            ''',
            '音元拼音': '''
                CREATE TABLE IF NOT EXISTS "音元拼音" (
                    "编号" INTEGER PRIMARY KEY AUTOINCREMENT,
                    "全拼" TEXT NOT NULL UNIQUE,
                    "简拼" TEXT NOT NULL UNIQUE,
                    "首音" TEXT,
                    "干音" TEXT NOT NULL,
                    "呼音" TEXT,
                    "主音" TEXT,
                    "末音" TEXT,
                    "间音" TEXT,
                    "韵音" TEXT,
                    "映射编号" INTEGER REFERENCES "拼音映射关系"("映射编号"),  -- 新增外键
                    "最近更新" TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    UNIQUE ("全拼", "首音", "干音")
                    )
                ''',
            '数字标调拼音': '''
                CREATE TABLE IF NOT EXISTS "数字标调拼音" (
                    "编号" INTEGER PRIMARY KEY AUTOINCREMENT,
                    "全拼" TEXT NOT NULL UNIQUE,
                    "声母" TEXT,
                    "韵母" TEXT NOT NULL,
                    "声调" INTEGER DEFAULT 1,
                    "映射编号" INTEGER REFERENCES "拼音映射关系"("映射编号"),
                    "最近更新" TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    UNIQUE ("全拼", "声母", "韵母", "声调")
                )
            ''',
            '拼音映射': '''
                CREATE TABLE IF NOT EXISTS "拼音映射" (
                    "编号" INTEGER PRIMARY KEY AUTOINCREMENT,
                    "数字标调拼音" TEXT NOT NULL UNIQUE,
                    "音元拼音" TEXT,
                    "标准拼音" TEXT,
                    "注音符号" TEXT,
                    "最近更新" TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            ''',
            # 汉字相关表
            '汉字': '''
                CREATE TABLE IF NOT EXISTS "汉字" (
                    "编号" INTEGER PRIMARY KEY,
                    "字符" TEXT NOT NULL UNIQUE,
                    "Unicode编码" TEXT NOT NULL,
                    "大写Unicode" TEXT GENERATED ALWAYS AS (UPPER("Unicode编码")) STORED,
                    "笔画数" INTEGER,
                    "部首" TEXT,
                    "常用字" BOOLEAN DEFAULT 1,
                    "最近更新" TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            ''',
            '汉字音元拼音映射': '''
                CREATE TABLE IF NOT EXISTS "汉字音元拼音映射" (
                    "汉字编号" INTEGER REFERENCES "汉字"("编号"),
                    "音元拼音编号" INTEGER REFERENCES "音元拼音"("编号"),
                    "频率" FLOAT DEFAULT 1.0,
                    "常用读音" BOOLEAN DEFAULT 0,
                    PRIMARY KEY ("汉字编号", "音元拼音编号")
                )
            ''',
            '汉字数字标调拼音映射': '''
                CREATE TABLE IF NOT EXISTS "汉字数字标调拼音映射" (
                    "汉字编号" INTEGER REFERENCES "汉字"("编号"),
                    "数字标调拼音编号" INTEGER REFERENCES "数字标调拼音"("编号"),
                    "频率" FLOAT DEFAULT 1.0,
                    "常用读音" BOOLEAN DEFAULT 0,
                    PRIMARY KEY ("汉字编号", "数字标调拼音编号")
                )
            ''',
            '汉字频率': '''
                CREATE TABLE IF NOT EXISTS "汉字频率" (
                    "汉字编号" INTEGER PRIMARY KEY REFERENCES "汉字"("编号"),
                    "绝对频率" INTEGER,
                    "相对频率" FLOAT,
                    "语料来源" TEXT,
                    "最近更新" TIMESTAMP
                )
            ''',
            '词汇': '''
                CREATE TABLE IF NOT EXISTS "词汇" (
                    "编号" INTEGER PRIMARY KEY,
                    "词语" TEXT NOT NULL,
                    "音元拼音" TEXT NOT NULL,
                    "频率" FLOAT,
                    "长度" INTEGER,
                    "常用词语" BOOLEAN DEFAULT 1,
                    "最近更新" TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            ''',
            '汉字标准拼音视图': '''
                CREATE VIEW IF NOT EXISTS 汉字标准拼音视图 AS
                SELECT
                    汉字.编号 AS 汉字编号,
                    汉字.字符 AS 汉字,
                    数字标调拼音.全拼 AS 标准拼音,
                    数字标调拼音.声调 AS 声调
                FROM 汉字
                JOIN 汉字数字标调拼音映射 ON 汉字.编号 = 汉字数字标调拼音映射.汉字编号
                JOIN 数字标调拼音 ON 汉字数字标调拼音映射.数字标调拼音编号 = 数字标调拼音.编号
                WHERE 汉字数字标调拼音映射.常用读音 = 1
            ''',
            '多音字视图': '''
                CREATE VIEW IF NOT EXISTS 多音字视图 AS
                SELECT
                    汉字.字符 AS 汉字,
                    GROUP_CONCAT(数字标调拼音.全拼, ', ') AS 所有读音
                FROM 汉字
                JOIN 汉字数字标调拼音映射 ON 汉字.编号 = 汉字数字标调拼音映射.汉字编号
                JOIN 数字标调拼音 ON 汉字数字标调拼音映射.数字标调拼音编号 = 数字标调拼音.编号
                GROUP BY 汉字.编号
                HAVING COUNT(*) > 1
            ''',
            '汉字音元拼音视图': '''
                CREATE VIEW IF NOT EXISTS 汉字音元拼音视图 AS
                SELECT
                    汉字.编号 AS 汉字编号,
                    汉字.字符 AS 汉字,
                    音元拼音.全拼 AS 音元拼音,
                    音元拼音.简拼 AS 简拼
                FROM 汉字
                JOIN 汉字音元拼音映射 ON 汉字.编号 = 汉字音元拼音映射.汉字编号
                JOIN 音元拼音 ON 汉字音元拼音映射.音元拼音编号 = 音元拼音.编号
                WHERE 汉字音元拼音映射.常用读音 = 1
            ''',
            '汉字拼音映射视图': '''
                CREATE VIEW IF NOT EXISTS 汉字拼音映射视图 AS
                SELECT
                    h.编号 AS 汉字编号,
                    h.字符 AS 汉字,
                    p.编号 AS 拼音编号,
                    p.全拼 AS 拼音,
                    p.声调,
                    m.频率,
                    m.常用读音
                FROM 汉字 h
                JOIN 汉字数字标调拼音映射 m ON h.编号 = m.汉字编号
                JOIN 数字标调拼音 p ON m.数字标调拼音编号 = p.编号
            '''
        }

        # 修改 表管理器.创建表() 方法中的删除逻辑
        for 表名, 创建语句 in 表结构.items():
            # 先检查是否是视图（创建语句以 CREATE VIEW 开头）
            if 创建语句.strip().upper().startswith('CREATE VIEW'):
                游标.execute(f'DROP VIEW IF EXISTS "{表名}"')
            else:
                游标.execute(f'DROP TABLE IF EXISTS "{表名}"')
            游标.execute(创建语句)

        # 创建索引（用双引号保护索引和表列）
        索引列表 = [
            # 拼音相关索引
            ('索引_拼音映射_标准拼音', '"拼音映射"("标准拼音")'),
            ('索引_拼音映射_注音符号', '"拼音映射"("注音符号")'),
            ('索引_拼音映射关系_源类型拼音', '"拼音映射关系"("原拼音类型", "原拼音")'),
            ('索引_拼音映射关系_目标类型拼音', '"拼音映射关系"("目标拼音类型", "目标拼音")'),
            ('索引_拼音映射关系_双向映射', '"拼音映射关系"("原拼音类型", "原拼音", "目标拼音类型", "目标拼音")'),

            # 音元拼音表新增索引
            ('索引_音元拼音_全拼', '"音元拼音"("全拼")'),  # 已存在UNIQUE约束，但单独索引可优化特定查询
            ('索引_音元拼音_简拼', '"音元拼音"("简拼")'),  # 已存在UNIQUE约束
            ('索引_音元拼音_干音', '"音元拼音"("干音")'),  # 高频查询字段
            ('索引_音元拼音_映射编号', '"音元拼音"("映射编号")'),  # 新增外键索引
            ('索引_音元拼音_复合查询', '"音元拼音"("干音", "呼音", "主音")'),  # 复合查询优化
            ('索引_音元拼音_全拼映射', '"音元拼音"("全拼", "映射编号")'),  # 联合查询优化

            # 汉字相关索引
            ('索引_汉字拼音初始数据_汉字', '"汉字拼音初始数据"("汉字")'),
            ('索引_汉字拼音初始数据_拼音', '"汉字拼音初始数据"("拼音")'),
            ('索引_汉字_字符', '"汉字"("字符")'),
            ('索引_汉字音元拼音映射_汉字', '"汉字音元拼音映射"("汉字编号")'),
            ('索引_汉字音元拼音映射_音元拼音', '"汉字音元拼音映射"("音元拼音编号")'),
            ('索引_汉字数字标调拼音映射_汉字', '"汉字数字标调拼音映射"("汉字编号")'),
            ('索引_汉字数字标调拼音映射_数字标调拼音', '"汉字数字标调拼音映射"("数字标调拼音编号")'),
            ('索引_词汇_词语', '"词汇"("词语")'),
            ('索引_词汇_音元拼音', '"词汇"("音元拼音")')
        ]

        for 索引名, 列名 in 索引列表:
            游标.execute(f'CREATE INDEX IF NOT EXISTS "{索引名}" ON {列名}')

        连接.commit()
        logger.info("数据库表结构创建/验证完成")

    @staticmethod
    def 检查索引存在(连接: sqlite3.Connection, 索引名: str) -> bool:
        """检查指定索引是否存在（需包含双引号）"""
        游标 = 连接.cursor()
        游标.execute(f"""
            SELECT name FROM sqlite_master
            WHERE type='index' AND name={索引名}
        """)
        return 游标.fetchone() is not None

    @staticmethod
    def 获取连接() -> sqlite3.Connection:
        return sqlite3.connect(str(DB_PATH))

class 数据库初始化器:
    """初始化数据库的入口类"""
    def __init__(self, 数据库路径: str = None):
        self.数据库路径 = Path(数据库路径) if 数据库路径 else Path(__file__).parent / "pinyin_hanzi.db"

    def 初始化数据库(self) -> None:
        """执行完整的数据库初始化流程"""
        try:
            print(f"已创建/验证表结构: {str(self.数据库路径)}")

            with 数据库管理器(str(self.数据库路径)) as 连接:
                表管理器.创建表(连接)
                logger.info("数据库初始化完成")
        except Exception as e:
            logger.error(f"数据库初始化失败: {e}")
            raise


if __name__ == "__main__":
    初始化器 = 数据库初始化器()
    初始化器.初始化数据库()

    with 数据库管理器("pinyin_hanzi.db") as 连接:
        存在 = 表管理器.检查索引存在(连接, '"索引_拼音映射_标准拼音"')
        print(f"索引存在: {存在}")

    import sqlite3
    conn = sqlite3.connect("pinyin_hanzi.db")
    for row in conn.execute("PRAGMA index_list('拼音映射关系')"):
        print(row)
    for row in conn.execute("PRAGMA index_info('sqlite_autoindex_拼音映射关系_1')"):
        print(row)
