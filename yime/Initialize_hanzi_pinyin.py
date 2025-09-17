import sqlite3
import logging
from pathlib import Path

logger = logging.getLogger(__name__)
logger.setLevel(logging.DEBUG)
handler = logging.StreamHandler()
handler.setFormatter(logging.Formatter('%(asctime)s - %(levelname)s - %(message)s'))
logger.addHandler(handler)

from db_manager import 数据库管理器

class 数据库初始化器:
    def 初始化数据库(self) -> None:
        try:
            with 数据库管理器(str(self.数据库路径)) as 连接:
                表管理器.创建表(连接)

                # 检查是否有初始数据需要导入
                游标 = 连接.cursor()
                游标.execute('SELECT COUNT(*) FROM "汉字拼音初始数据"')
                if 游标.fetchone()[0] > 0:
                    表管理器.从初始数据表导入映射(连接)

                logger.info("数据库初始化完成")
        except Exception as e:
            logger.error(f"数据库初始化失败: {e}")
            raise

    @staticmethod
    def 从初始数据表导入映射(连接: sqlite3.Connection):
        """从汉字拼音初始数据表导入映射关系到正式表"""
        游标 = 连接.cursor()

        # 1. 导入汉字表
        游标.execute('''
            INSERT OR IGNORE INTO "汉字"("字符", "Unicode编码")
            SELECT DISTINCT
                汉字,
                'U+' || printf('%04X', unicode(汉字))
            FROM "汉字拼音初始数据"
        ''')

        # 2. 导入数字标调拼音表
        游标.execute('''
            INSERT OR IGNORE INTO "数字标调拼音"("全拼")
            SELECT DISTINCT 拼音
            FROM "汉字拼音初始数据"
        ''')

        # 3. 建立映射关系
        游标.execute('''
            INSERT OR REPLACE INTO "汉字数字标调拼音映射"(
                "汉字编号", "数字标调拼音编号", "频率", "常用读音"
            )
            SELECT
                h."编号",
                p."编号",
                d."频率",
                d."常用读音"
            FROM "汉字拼音初始数据" d
            JOIN "汉字" h ON h."字符" = d."汉字"
            JOIN "数字标调拼音" p ON p."全拼" = d."拼音"
        ''')

        连接.commit()

    @staticmethod
    def 导入初始数据(连接: sqlite3.Connection, 数据源: str, 来源: str = '手动导入'):
        """
        从不同数据源导入初始数据
        :param 数据源: 可以是CSV文件路径或字典对象
        :param 来源: 数据来源描述
        """
        游标 = 连接.cursor()

        if isinstance(数据源, str):  # CSV文件
            import csv
            with open(数据源, 'r', encoding='utf-8') as f:
                reader = csv.reader(f)
                数据 = [(row[0], row[1], float(row[2]) if len(row)>2 else 1.0,
                        int(row[3]) if len(row)>3 else 0, 来源)
                    for row in reader]
        else:  # 字典对象
            数据 = [(k, v, 1.0, 0, 来源) for k, vs in 数据源.items() for v in vs]

        游标.executemany('''
            INSERT OR REPLACE INTO "汉字拼音初始数据"
            ("汉字", "拼音", "频率", "常用读音", "来源")
            VALUES (?, ?, ?, ?, ?)
        ''', 数据)

        连接.commit()