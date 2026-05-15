"""将数字标调拼音拆分为声母、韵母、声调并重建目标表。"""

import sqlite3
import logging
from pathlib import Path
from typing import Dict
from syllable.analysis.syllable_splitter import SyllableSplitter

CANONICAL_MAPPING_TABLE = "多式拼音映射关系"
NUMERIC_SOURCE_TYPE = "音元拼音"
DEFAULT_DB = Path(__file__).resolve().parent / "pinyin_hanzi.db"


class 数字标调拼音导入器:
    """从规范映射面重建数字标调拼音，并拆分出声母、韵母、声调。"""

    REQUIRED_TABLE = "数字标调拼音"
    SOURCE_TABLE = CANONICAL_MAPPING_TABLE

    def __init__(self, 数据库路径: str | Path = DEFAULT_DB):
        self.数据库路径 = Path(数据库路径).resolve()
        self._配置日志()

    def _配置日志(self):
        logging.basicConfig(
            level=logging.INFO,
            format="%(asctime)s - %(levelname)s - %(message)s"
        )
        self.日志 = logging.getLogger(__name__)

    def _获取连接(self) -> sqlite3.Connection:
        conn = sqlite3.connect(str(self.数据库路径))
        conn.row_factory = sqlite3.Row
        return conn

    def _检查表存在(self, conn: sqlite3.Connection, 表名: str) -> bool:
        cursor = conn.cursor()
        cursor.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
            (表名,)
        )
        return cursor.fetchone() is not None

    def _确保表结构正确(self, conn: sqlite3.Connection):
        """确保目标表存在且结构正确。"""
        source_table = self.SOURCE_TABLE
        if not self._检查表结构(conn):
            cursor = conn.cursor()
            cursor.execute(f'''
            CREATE TABLE IF NOT EXISTS "{self.REQUIRED_TABLE}" (
                映射编号 INTEGER REFERENCES "{source_table}"(映射编号),
                全拼 TEXT NOT NULL,
                声母 TEXT,
                韵母 TEXT NOT NULL,
                声调 INTEGER DEFAULT 1,
                最近更新 TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (映射编号),
                UNIQUE (全拼, 声母, 韵母, 声调)
            )''')
            cursor.execute(f'PRAGMA table_info("{self.REQUIRED_TABLE}")')
            existing_columns = [col[1] for col in cursor.fetchall()]
            required_columns = ["映射编号", "全拼", "声母", "韵母", "声调"]

            for col in required_columns:
                if col not in existing_columns:
                    if col == "映射编号":
                        column_type = f'INTEGER REFERENCES "{source_table}"(映射编号)'
                    elif col == "声调":
                        column_type = "INTEGER"
                    else:
                        column_type = "TEXT"
                    cursor.execute(f'''
                    ALTER TABLE "{self.REQUIRED_TABLE}"
                    ADD COLUMN {col} {column_type}
                    ''')

    def _清空目标表(self, conn: sqlite3.Connection) -> None:
        cursor = conn.cursor()
        cursor.execute(f'DELETE FROM "{self.REQUIRED_TABLE}"')
        has_sequence = cursor.execute(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name='sqlite_sequence'"
        ).fetchone()
        if has_sequence is not None:
            cursor.execute("DELETE FROM sqlite_sequence WHERE name=?", (self.REQUIRED_TABLE,))
        conn.commit()

    def 从映射表加载数据(self, conn: sqlite3.Connection) -> Dict[str, Dict[str, str]]:
        """从多式拼音映射关系表加载数字标调拼音数据。"""
        source_table = self.SOURCE_TABLE

        cursor = conn.cursor()
        cursor.execute(
            f'''SELECT 映射编号, 原拼音, 目标拼音
            FROM "{source_table}"
                        WHERE 原拼音类型 = '{NUMERIC_SOURCE_TYPE}'
                            AND 目标拼音类型 = '数字标调'
                            AND 目标拼音 IS NOT NULL'''
        )

        数据 = {row["原拼音"]: {"数字标调": row["目标拼音"]}
              for row in cursor.fetchall()}

        self.日志.info(f"已从 {source_table} 加载 {len(数据)} 条数字标调拼音数据")
        return 数据

    def 解析拼音(self, pinyin_str: str) -> dict:
        """使用 SyllableSplitter 统一规则，将数字标调拼音解析为声母、韵母、声调。"""
        shouyin, ganyin = SyllableSplitter.split_syllable(pinyin_str)
        normalized_initial = "" if shouyin == "'" else shouyin

        numeric_final = SyllableSplitter.REVERSE_SPECIAL_SYLLABLES.get(ganyin, ganyin)
        tone = int(numeric_final[-1]) if numeric_final and numeric_final[-1].isdigit() else 1
        yunmu = numeric_final[:-1] if numeric_final and numeric_final[-1].isdigit() else numeric_final

        return {
            "声母": normalized_initial,
            "韵母": yunmu,
            "声调": tone
        }

    def 导入数据(self) -> int:
        """从映射表全量重建数字标调拼音数据。"""
        with self._获取连接() as conn:
            self._确保表结构正确(conn)
            self._清空目标表(conn)
            cursor = conn.cursor()
            source_table = self.SOURCE_TABLE

            cursor.execute(f'''
            SELECT 映射编号, 原拼音, 目标拼音 FROM "{source_table}"
                        WHERE 原拼音类型 = '{NUMERIC_SOURCE_TYPE}'
                            AND 目标拼音类型 = '数字标调'
                            AND 目标拼音 IS NOT NULL
            ORDER BY 映射编号
            ''')

            rows = cursor.fetchall()
            cursor.executemany(f'''
            INSERT INTO "{self.REQUIRED_TABLE}"
            (映射编号, 全拼, 声母, 韵母, 声调)
            VALUES (?, ?, ?, ?, ?)
            ''', [
                (
                    row["映射编号"],
                    row["目标拼音"],
                    *self.解析拼音(row["目标拼音"]).values()
                )
                for row in rows
            ])

            conn.commit()
            return len(rows)

    def _检查表结构(self, conn: sqlite3.Connection) -> bool:
        """检查数据库表结构是否完整。"""
        cursor = conn.cursor()

        if not self._检查表存在(conn, self.REQUIRED_TABLE):
            self.日志.error(f"表 {self.REQUIRED_TABLE} 不存在")
            return False

        source_table = self.SOURCE_TABLE
        if not self._检查表存在(conn, source_table):
            self.日志.error(f"表 {source_table} 不存在")
            return False

        cursor.execute(f'PRAGMA table_info("{source_table}")')
        源表列 = [col[1] for col in cursor.fetchall()]
        if "原拼音" not in 源表列 or "目标拼音" not in 源表列 or "目标拼音类型" not in 源表列:
            self.日志.error(f"表 {source_table} 缺少必要的列")
            return False

        cursor.execute(f'PRAGMA table_info("{self.REQUIRED_TABLE}")')
        目标表列 = [col[1] for col in cursor.fetchall()]
        required_columns = ["映射编号", "全拼", "声母", "韵母", "声调"]
        if not all(col in 目标表列 for col in required_columns):
            self.日志.error(f"表 {self.REQUIRED_TABLE} 缺少必要的列")
            return False

        return True

    def 清理重复数据(self) -> int:
        """清理表中的重复拼音数据。"""
        with self._获取连接() as conn:
            cursor = conn.cursor()
            cursor.execute(f'''
            DELETE FROM "{self.REQUIRED_TABLE}"
            WHERE rowid NOT IN (
                SELECT MIN(rowid)
                FROM "{self.REQUIRED_TABLE}"
                GROUP BY 全拼, 声母, 韵母, 声调
            )
            ''')
            conn.commit()
            return cursor.rowcount


def rebuild_numeric_pinyin(database_path: str | Path = DEFAULT_DB) -> int:
    """对外暴露的重建入口：从库内规范映射面全量刷新数字标调拼音。"""
    导入器 = 数字标调拼音导入器(database_path)
    return 导入器.导入数据()


if __name__ == "__main__":
    try:
        结果 = rebuild_numeric_pinyin()
        print(f"导入结果: {结果} 条记录")
    except Exception as e:
        print(f"错误: {e}")
