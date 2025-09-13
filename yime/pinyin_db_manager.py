import sqlite3
import logging

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
        """创建所有必要的数据库表"""
        游标 = 连接.cursor()

        表结构 = {
            '音元拼音': '''
                CREATE TABLE IF NOT EXISTS 音元拼音 (
                    id INTEGER PRIMARY KEY,
                    全拼 TEXT NOT NULL UNIQUE,
                    简拼 TEXT,
                    首音 TEXT,
                    干音 TEXT,
                    呼音 TEXT,
                    主音 TEXT,
                    末音 TEXT,
                    间音 TEXT,
                    韵音 TEXT,
                    创建时间 TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )''',
            '数字标调拼音': '''
                CREATE TABLE IF NOT EXISTS 数字标调拼音 (
                    id INTEGER PRIMARY KEY,
                    数字标调拼音 TEXT NOT NULL UNIQUE,
                    声母 TEXT,
                    韵母 TEXT,
                    声调 INTEGER,
                    创建时间 TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )''',
            '音元拼音已有拼音映射': '''
                CREATE TABLE IF NOT EXISTS 音元拼音已有拼音映射 (
                    音元拼音id INTEGER REFERENCES 音元拼音(id),
                    数字标调拼音id INTEGER REFERENCES 数字标调拼音(id),
                    标准拼音 TEXT NOT NULL,
                    注音符号 TEXT NOT NULL,
                    最后更新时间 TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    PRIMARY KEY (音元拼音id, 数字标调拼音id)
                )'''
        }

        for 表名, 创建语句 in 表结构.items():
            游标.execute(f"DROP TABLE IF EXISTS {表名}")
            游标.execute(创建语句)

        # 创建索引
        索引列表 = [
            ('索引_数字标调拼音_数字标调拼音', '数字标调拼音(数字标调拼音)'),
            ('索引_音元拼音数字标调拼音映射_标准拼音', '音元拼音已有拼音映射(标准拼音)'),
            ('索引_音元拼音数字标调拼音映射_注音符号', '音元拼音已有拼音映射(注音符号)')
        ]

        for 索引名, 列名 in 索引列表:
            游标.execute(f"CREATE INDEX IF NOT EXISTS {索引名} ON {列名}")

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
                    INSERT OR REPLACE INTO 音元拼音已有拼音映射
                    (数字标调拼音id, 标准拼音, 注音符号)
                    VALUES (
                        (SELECT id FROM 数字标调拼音 WHERE 数字标调拼音 = ?),
                        ?, ?
                    )
                ''', 映射数据)

                总数 += len(批次)
                logger.debug(f"已处理 {总数}/{len(拼音列表)} 条记录")

            except sqlite3.Error as 错误:
                logger.error(f"批量导入失败: {错误}")
                连接.rollback()
                raise

        logger.info(f"成功导入 {总数} 条音元映射")
        return 总数

class 数据库迁移器:
    def __init__(self, 数据库路径: str):
        self.数据库路径 = 数据库路径

    def 通过拼音查询(self, 数字标调拼音: str) -> list:
        """通过拼音查询相关信息"""
        with sqlite3.connect(str(self.数据库路径)) as 连接:
            游标 = 连接.cursor()

            游标.execute('''
                SELECT
                    d.数字标调拼音,
                    m.标准拼音,
                    m.注音符号,
                    y.全拼 AS 音元拼音
                FROM 音元拼音已有拼音映射 m
                JOIN 数字标调拼音 d ON m.数字标调拼音id = d.id
                LEFT JOIN 音元拼音 y ON m.音元拼音id = y.id
                WHERE d.数字标调拼音 = ? OR m.标准拼音 = ?
            ''', (数字标调拼音, 数字标调拼音))

            return [{
                '数字标调拼音': 行[0],
                '标准拼音': 行[1],
                '注音符号': 行[2],
                '音元拼音': 行[3]
            } for 行 in 游标.fetchall()]

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
    数据库路径 = "pinyin_hanzi.db"

    # 初始化数据库
    with sqlite3.connect(数据库路径) as 连接:
        表管理器.创建表(连接)

    # 测试查询
    迁移器 = 数据库迁移器(数据库路径)
    print(迁移器.通过拼音查询("ni3"))
    print(迁移器.验证表结构())