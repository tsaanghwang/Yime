import sqlite3
import logging
from pathlib import Path

from utils.pinyin_normalizer import PinyinNormalizer
from utils.pinyin_zhuyin import PinyinZhuyinConverter

logger = logging.getLogger(__name__)
logger.setLevel(logging.DEBUG)
handler = logging.StreamHandler()
handler.setFormatter(logging.Formatter('%(asctime)s - %(levelname)s - %(message)s'))
logger.addHandler(handler)


class 表管理器:
    @staticmethod
    def 创建表(连接: sqlite3.Connection) -> None:
        """创建所有必要的数据库表（使用双引号保护标识符以避免解析问题）"""
        游标 = 连接.cursor()

        表结构 = {
            '音元拼音': '''
                CREATE TABLE IF NOT EXISTS "音元拼音" (
                    "编号" INTEGER PRIMARY KEY AUTOINCREMENT,
                    "全拼" TEXT NOT NULL UNIQUE,
                    "简拼" TEXT NOT NULL UNIQUE,
                    "首音" TEXT,
                    "干音" TEXT TEXT NOT NULL,
                    "呼音" TEXT,
                    "主音" TEXT,
                    "末音" TEXT,
                    "间音" TEXT,
                    "韵音" TEXT,
                    "最近更新" TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    UNIQUE ("全拼", "首音", "干音")
                )
            ''',
            # 将列定义放在前面，表级约束（UNIQUE）放在最后，避免在 SQLite 中出现语法错误
            '数字标调拼音': '''
                CREATE TABLE IF NOT EXISTS "数字标调拼音" (
                    "编号" INTEGER PRIMARY KEY AUTOINCREMENT,
                    "全拼" TEXT NOT NULL UNIQUE,
                    "声母" TEXT,
                    "韵母" TEXT NOT NULL,
                    "声调" INTEGER DEFAULT 1,
                    "最近更新" TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    UNIQUE ("全拼", "声母", "韵母", "声调")
                )
            ''',
            '音元拼音已有拼音映射': '''
                CREATE TABLE IF NOT EXISTS "音元拼音已有拼音映射" (
                    "音元拼音" INTEGER REFERENCES "音元拼音"("编号"),
                    "带数拼音" INTEGER REFERENCES "数字标调拼音"("编号"),
                    "标准拼音" TEXT NOT NULL,
                    "注音符号" TEXT NOT NULL,
                    "最近更新" TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    PRIMARY KEY ("音元拼音", "带数拼音")
                )
            '''
        }

        # 先删除（如果存在），再创建 — 使用双引号保护表名
        for 表名, 创建语句 in 表结构.items():
            游标.execute(f'DROP TABLE IF EXISTS "{表名}"')
            游标.execute(创建语句)

        # 创建索引（用双引号保护索引和表列）
        索引列表 = [
            ('索引_数字标调拼音_全拼', '"数字标调拼音"("全拼")'),
            ('索引_音元拼音已有拼音映射_标准拼音', '"音元拼音已有拼音映射"("标准拼音")'),
            ('索引_音元拼音已有拼音映射_注音符号', '"音元拼音已有拼音映射"("注音符号")')
        ]

        for 索引名, 列名 in 索引列表:
            游标.execute(f'CREATE INDEX IF NOT EXISTS "{索引名}" ON {列名}')

        连接.commit()
        logger.info("数据库表结构创建/验证完成")


class 数据导入器:
    @staticmethod
    def 导入音元数据(连接: sqlite3.Connection) -> int:
        """从外部数据源导入并处理数据"""
        游标 = 连接.cursor()

        # 这里需要修改为从您的实际数据源获取拼音列表
        拼音列表 = []  # 替换为实际数据源

        if not 拼音列表:
            logger.error("拼音列表为空")
            return 0

        # 处理拼音数据
        标准化字典, _ = PinyinNormalizer.process_pinyin_dict({数字标调拼音: 数字标调拼音 for 数字标调拼音 in 拼音列表})
        注音字典, _ = PinyinZhuyinConverter.process_pinyin_dict({数字标调拼音: 数字标调拼音 for 数字标调拼音 in 拼音列表})

        # 批量插入数据
        批量大小 = 100
        总数 = 0

        for i in range(0, len(拼音列表), 批量大小):
            批次 = 拼音列表[i:i+批量大小]
            try:
                # 准备批量插入数据
                映射数据 = [
                    (数字标调拼音, 标准化字典.get(数字标调拼音, 数字标调拼音), 注音字典.get(数字标调拼音, ''))
                    for 数字标调拼音 in 批次
                ]

                游标.executemany('''
                    INSERT OR REPLACE INTO "音元拼音已有拼音映射"
                    ("数字标调拼音", "标准拼音", "注音符号")
                    VALUES (
                        (SELECT "编号" FROM "数字标调拼音" WHERE "数字标调拼音" = ?),
                        ?, ?
                    )
                ''', 映射数据)

                总数 += len(批次)
                logger.debug(f"已处理 {总数}/{len(拼音列表)} 条记录")

            except sqlite3.Error as 错误:
                logger.error(f"批量导入失败: {错误}")
                连接.rollback()
                raise

        连接.commit()
        logger.info(f"成功导入 {总数} 条音元映射")
        return 总数


class 数据库迁移器:
    def __init__(self, 数据库路径: str | Path):  # 接受str或Path类型
        self.数据库路径 = str(数据库路径)  # 内部统一转为字符串

    def 通过拼音查询(self, 数字标调拼音: str) -> list:
        """通过拼音查询相关信息"""
        with sqlite3.connect(str(self.数据库路径)) as 连接:
            连接.row_factory = sqlite3.Row
            游标 = 连接.cursor()

            # 修正列名：数字标调拼音表中使用的是 "全拼" 列，映射表使用的是 "带数拼音" 作为外键
            sql = '''
                SELECT
                    d."全拼" AS 数字标调拼音,
                    m."标准拼音" AS 标准拼音,
                    m."注音符号" AS 注音符号,
                    y."全拼" AS 音元拼音
                FROM "音元拼音已有拼音映射" m
                JOIN "数字标调拼音" d ON m."带数拼音" = d."编号"
                LEFT JOIN "音元拼音" y ON m."音元拼音" = y."编号"
                WHERE d."全拼" = ? OR m."标准拼音" = ?
            '''
            游标.execute(sql, (数字标调拼音, 数字标调拼音))

            return [dict(row) for row in 游标.fetchall()]

    def 验证表结构(self) -> bool:
        """验证所有表结构是否正确创建"""
        with sqlite3.connect(str(self.数据库路径)) as 连接:
            游标 = 连接.cursor()
            表列表 = ['音元拼音', '数字标调拼音', '音元拼音已有拼音映射']

            for 表名 in 表列表:
                游标.execute(f"SELECT name FROM sqlite_master WHERE type='table' AND name='{表名}'")
                if not 游标.fetchone():
                    return False
            return True


if __name__ == "__main__":
    # 测试代码
    数据库路径 = Path(__file__).parent / "pinyin_hanzi.db"

    # 初始化数据库
    with sqlite3.connect(数据库路径) as 连接:
        表管理器.创建表(连接)

    # 测试查询
    迁移器 = 数据库迁移器(数据库路径)
    print(迁移器.通过拼音查询("ni3"))
    print(迁移器.验证表结构())
