"""Legacy-compatible schema/migration helpers for the old Chinese-table database surface.

This module is still kept at the package root because older scripts, tests, and
manual maintenance entrypoints import it directly. It is not the current mainline
rebuild entry. The stable compatibility surface here is `run_schema_migrations()`.
"""

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
DB_PATH = Path(__file__).resolve().parents[2] / "pinyin_hanzi.db"
CANONICAL_MAPPING_TABLE = "多式拼音映射关系"
UNUSED_SHORT_MAPPING_TABLE = "拼音映射"
UNUSED_HOMOPHONE_TABLE = "音元拼音同音表"
UNUSED_LEGACY_TABLES = (
    "汉字拼音初始数据",
    "拼音映射初始数据",
    "数字标调全拼",
    "汉字音元拼音映射",
    "汉字数字标调拼音映射",
    "词汇",
    "汉字",
    "汉字频率",
)
UNUSED_LEGACY_VIEWS = (
    "多音字视图",
    "拼音映射视图",
    "汉字拼音映射视图",
    "汉字标准拼音视图",
    "汉字音元拼音视图",
)

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
        # 说明：`多式拼音映射关系` 是资料层/对照层表，用于保存多种拼音表示法之间的关系。
        # `音元拼音` 是保留的音节结构表，用于保存 `全拼 -> 简拼` 与
        # `全拼 -> 首音/干音/呼音/主音/末音/间音/韵音` 的结构拆分结果。
        # 当前口径要求 `全拼` 为四音等长编码，并满足：
        # `首音 = 全拼[0]`，`干音 = 全拼[1:]`，`呼音 = 全拼[1]`，`主音 = 全拼[2]`，
        # `末音 = 全拼[3]`，`间音 = 全拼[1:3] = 呼音 + 主音`，
        # `韵音 = 全拼[2:4] = 主音 + 末音`。
        # `简拼` 则要求等于把音节中连续相同的两音或三音合并成一个音后的结果。
        # 它不是当前 runtime 主线候选表；当前主线仍是
        # `source_pinyin.db -> prototype tables -> refresh_runtime_yime_codes -> runtime_candidates`。
        # 其中 `mapping_yime_code` 作为库内兼容映射面，按唯一 yime_code 重新编号，
        # 供 `音元拼音.映射编号` 对齐引用，避免再次回到仓库外部文件直接建表。
        表结构 = {
            CANONICAL_MAPPING_TABLE: f'''
                CREATE TABLE IF NOT EXISTS "{CANONICAL_MAPPING_TABLE}" (
                    "映射编号" INTEGER PRIMARY KEY AUTOINCREMENT,
                    "原拼音类型" TEXT NOT NULL,
                    "原拼音" TEXT NOT NULL,
                    "目标拼音类型" TEXT NOT NULL,
                    "目标拼音" TEXT NOT NULL,
                    "关系类型" TEXT NOT NULL DEFAULT '对应',
                    "时期标签" TEXT,
                    "数据来源" TEXT,
                    "版本号" TEXT,
                    "备注" TEXT,
                    "创建时间" TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    UNIQUE("原拼音类型", "原拼音", "目标拼音类型", "目标拼音", "关系类型", "数据来源")
                )
            ''',
            'mapping_yime_code': '''
                CREATE TABLE IF NOT EXISTS "mapping_yime_code" (
                    "mapping_id" INTEGER PRIMARY KEY,
                    "yime_code" TEXT NOT NULL,
                    "source_pinyin_tone" TEXT,
                    "updated_at" TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            ''',
            '音元拼音': '''
                CREATE TABLE IF NOT EXISTS "音元拼音" (
                    "编号" INTEGER PRIMARY KEY AUTOINCREMENT,
                    "全拼" TEXT NOT NULL UNIQUE,
                    "简拼" TEXT UNIQUE,
                    "首音" TEXT NOT NULL,
                    "干音" TEXT NOT NULL,
                    "呼音" TEXT,
                    "主音" TEXT,
                    "末音" TEXT,
                    "间音" TEXT,
                    "韵音" TEXT,
                    "映射编号" INTEGER REFERENCES "mapping_yime_code"("mapping_id") ON DELETE SET NULL,
                    "最近更新" TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            ''',
            '数字标调拼音': '''
                CREATE TABLE IF NOT EXISTS "数字标调拼音" (
                    "编号" INTEGER PRIMARY KEY AUTOINCREMENT,
                    "全拼" TEXT NOT NULL UNIQUE,
                    "声母" TEXT,
                    "韵母" TEXT NOT NULL,
                    "声调" INTEGER DEFAULT 1,
                    "映射编号" INTEGER REFERENCES "多式拼音映射关系"("映射编号"),
                    "最近更新" TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    UNIQUE ("全拼", "声母", "韵母", "声调")
                )
            ''',
        }

        # 修改 表管理器.创建表() 方法中的删除逻辑
        for 表名, 创建语句 in 表结构.items():
            # 直接执行创建语句（语句中已经使用了 IF NOT EXISTS）
            # 如果未来需要变更表结构，应使用迁移脚本而不是在运行时 drop/recreate
            游标.executescript(创建语句)

        # 创建索引（用双引号保护索引和表列）
        索引列表 = [
            # 拼音相关索引
            ('索引_多式拼音映射关系_源类型拼音', '"多式拼音映射关系"("原拼音类型", "原拼音")'),
            ('索引_多式拼音映射关系_目标类型拼音', '"多式拼音映射关系"("目标拼音类型", "目标拼音")'),
            ('索引_多式拼音映射关系_双向映射', '"多式拼音映射关系"("原拼音类型", "原拼音", "目标拼音类型", "目标拼音")'),
            ('idx_mapping_yime_code_yime_code', '"mapping_yime_code"("yime_code")'),

            # 音元拼音表新增索引（全拼列索引可保留）
            ('索引_音元拼音_全拼', '"音元拼音"("全拼")'),
             ('索引_音元拼音_干音', '"音元拼音"("干音")'),  # 高频查询字段
             ('索引_音元拼音_映射编号', '"音元拼音"("映射编号")'),  # 新增外键索引
             ('索引_音元拼音_复合查询', '"音元拼音"("干音", "呼音", "主音")'),  # 复合查询优化
             ('索引_音元拼音_全拼映射', '"音元拼音"("全拼", "映射编号")'),  # 联合查询优化

        ]

        for 索引名, 列名 in 索引列表:
            游标.execute(f'CREATE INDEX IF NOT EXISTS "{索引名}" ON {列名}')

        连接.commit()
        logger.info("数据库表结构创建/验证完成")

    @staticmethod
    def 检查索引存在(连接: sqlite3.Connection, 索引名: str) -> bool:
        """检查指定索引是否存在（索引名请传不带额外引号的纯名）"""
        游标 = 连接.cursor()
        # 使用参数化查询避免 SQL 注入/拼接错误
        游标.execute("""
            SELECT name FROM sqlite_master
            WHERE type='index' AND name = ?
        """, (索引名,))
        return 游标.fetchone() is not None

    @staticmethod
    def 获取连接() -> sqlite3.Connection:
        conn = sqlite3.connect(str(DB_PATH))
        conn.row_factory = sqlite3.Row
        # 启用 WAL 与外键，作为默认安全设置
        try:
            conn.execute("PRAGMA journal_mode = WAL;")
        except Exception:
            pass
        conn.execute("PRAGMA foreign_keys = ON;")
        return conn

class 数据库初始化器:
    """初始化数据库的入口类"""
    def __init__(self, 数据库路径: str = None):
        self.数据库路径 = Path(数据库路径) if 数据库路径 else Path(__file__).parent / "pinyin_hanzi.db"

    def 初始化数据库(self) -> None:
        """执行完整的数据库初始化流程"""
        try:
            print(f"已创建/验证表结构: {str(self.数据库路径)}")
            run_schema_migrations(self.数据库路径)
            logger.info("数据库初始化完成")
        except Exception as e:
            logger.error(f"数据库初始化失败: {e}")
            raise


def _重建数字标调拼音表(连接: sqlite3.Connection) -> None:
    游标 = 连接.cursor()
    游标.execute('DROP TABLE IF EXISTS "数字标调拼音__migration_backup"')
    游标.execute(
        '''
        CREATE TABLE "数字标调拼音__migration_backup" AS
        SELECT * FROM "数字标调拼音"
        '''
    )
    游标.execute('DROP TABLE "数字标调拼音"')
    游标.execute(
        f'''
        CREATE TABLE "数字标调拼音" (
            "编号" INTEGER PRIMARY KEY AUTOINCREMENT,
            "全拼" TEXT NOT NULL UNIQUE,
            "声母" TEXT,
            "韵母" TEXT NOT NULL,
            "声调" INTEGER DEFAULT 1,
            "映射编号" INTEGER REFERENCES "{CANONICAL_MAPPING_TABLE}"("映射编号"),
            "最近更新" TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE ("全拼", "声母", "韵母", "声调")
        )
        '''
    )
    游标.execute(
        '''
        INSERT INTO "数字标调拼音" ("编号", "全拼", "声母", "韵母", "声调", "映射编号", "最近更新")
        SELECT "编号", "全拼", "声母", "韵母", "声调", "映射编号", "最近更新"
        FROM "数字标调拼音__migration_backup"
        '''
    )
    游标.execute('DROP TABLE "数字标调拼音__migration_backup"')


def _确保多式拼音映射关系(连接: sqlite3.Connection) -> None:
    游标 = 连接.cursor()
    表管理器.创建表(连接)

    数字标调定义 = 游标.execute(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name='数字标调拼音'"
    ).fetchone()
    if 数字标调定义 and CANONICAL_MAPPING_TABLE not in (数字标调定义[0] or ''):
        _重建数字标调拼音表(连接)


def _删除未使用短表名残留(连接: sqlite3.Connection) -> None:
    游标 = 连接.cursor()
    for 表名 in (UNUSED_HOMOPHONE_TABLE, UNUSED_SHORT_MAPPING_TABLE):
        对象类型 = 游标.execute(
            "SELECT type FROM sqlite_master WHERE name=?",
            (表名,),
        ).fetchone()
        if 对象类型 and 对象类型[0] == 'view':
            游标.execute(f'DROP VIEW IF EXISTS "{表名}"')
        else:
            游标.execute(f'DROP TABLE IF EXISTS "{表名}"')


def _删除未使用遗留空表(连接: sqlite3.Connection) -> None:
    游标 = 连接.cursor()
    for 表名 in UNUSED_LEGACY_TABLES:
        游标.execute(f'DROP TABLE IF EXISTS "{表名}"')


def _删除未使用遗留视图(连接: sqlite3.Connection) -> None:
    游标 = 连接.cursor()
    for 视图名 in UNUSED_LEGACY_VIEWS:
        游标.execute(f'DROP VIEW IF EXISTS "{视图名}"')


def run_schema_migrations(db_path: str | Path | None = None) -> None:
    目标路径 = Path(db_path) if db_path else DB_PATH
    with sqlite3.connect(str(目标路径)) as 连接:
        连接.row_factory = sqlite3.Row
        连接.execute('PRAGMA foreign_keys = OFF;')
        try:
            _确保多式拼音映射关系(连接)
            _删除未使用短表名残留(连接)
            _删除未使用遗留空表(连接)
            _删除未使用遗留视图(连接)
            连接.commit()
        finally:
            连接.execute('PRAGMA foreign_keys = ON;')


if __name__ == "__main__":
    初始化器 = 数据库初始化器()
    初始化器.初始化数据库()

    # 示例验证：使用模块内 DB_PATH（避免相对 path 导致混淆）
    with 数据库管理器(str(DB_PATH)) as 连接:
        存在 = 表管理器.检查索引存在(连接, "索引_多式拼音映射关系_源类型拼音")
        print(f"索引存在: {存在}")
