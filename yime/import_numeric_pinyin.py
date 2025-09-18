"""数字标调拼音数据导入工具(最终修正版)"""

import sqlite3
import logging
from pathlib import Path
from typing import Dict, List, Optional

class 数字标调拼音导入器:
    """最终修正版：确保数据不重复导入"""

    REQUIRED_TABLE = "数字标调拼音"
    SOURCE_TABLE = "拼音映射关系"

    def __init__(self, 数据库路径: str | Path = "pinyin_hanzi.db"):
        self.数据库路径 = Path(数据库路径).absolute()
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
        """确保目标表存在且结构正确(修改版)"""
        if not self._检查表结构(conn):
            # 如果表结构检查失败，创建或修复表
            cursor = conn.cursor()
            cursor.execute(f'''
            CREATE TABLE IF NOT EXISTS "{self.REQUIRED_TABLE}" (
                映射编号 INTEGER REFERENCES "{self.SOURCE_TABLE}"(映射编号),
                全拼 TEXT NOT NULL,
                声母 TEXT,
                韵母 TEXT NOT NULL,
                声调 INTEGER DEFAULT 1,
                最近更新 TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (映射编号),
                UNIQUE (全拼, 声母, 韵母, 声调)
            )''')
            # 检查并添加缺失的列
            cursor.execute(f'PRAGMA table_info("{self.REQUIRED_TABLE}")')
            existing_columns = [col[1] for col in cursor.fetchall()]
            required_columns = ["映射编号", "全拼", "声母", "韵母", "声调"]

            for col in required_columns:
                if col not in existing_columns:
                    cursor.execute(f'''
                    ALTER TABLE "{self.REQUIRED_TABLE}"
                    ADD COLUMN {col} {
                        "INTEGER REFERENCES \"拼音映射关系\"(映射编号)" if col == "映射编号"
                        else "INTEGER" if col == "声调"
                        else "TEXT"
                    }
                    ''')

            # 清空表
            cursor.execute(f'DELETE FROM "{self.REQUIRED_TABLE}"')
            conn.commit()

    def 从映射表加载数据(self, conn: sqlite3.Connection) -> Dict[str, Dict[str, str]]:
        """从拼音映射关系表加载数字标调拼音数据"""
        if not self._检查表存在(conn, self.SOURCE_TABLE):
            raise ValueError(f"源表 {self.SOURCE_TABLE} 不存在")

        cursor = conn.cursor()
        cursor.execute(
            f'''SELECT 映射编号, 原拼音, 目标拼音
            FROM "{self.SOURCE_TABLE}"
            WHERE 目标拼音类型 = '数字标调' AND 目标拼音 IS NOT NULL'''
        )

        数据 = {row["原拼音"]: {"数字标调": row["目标拼音"]}
              for row in cursor.fetchall()}

        self.日志.info(f"已从 {self.SOURCE_TABLE} 加载 {len(数据)} 条数字标调拼音数据")
        return 数据

    def 解析拼音(self, pinyin_str: str) -> dict:
        """将数字标调拼音解析为声母、韵母、声调"""
        tone = int(pinyin_str[-1]) if pinyin_str[-1].isdigit() else 1
        base = pinyin_str[:-1] if pinyin_str[-1].isdigit() else pinyin_str

        initials = ["b", "p", "m", "f", "d", "t", "n", "l", "g", "k", "h",
                   "j", "q", "x", "zh", "ch", "sh", "r", "z", "c", "s", "y", "w"]
        shengmu = next((sm for sm in initials if base.startswith(sm)), "")
        yunmu = base[len(shengmu):]

        return {
            "声母": shengmu,
            "韵母": yunmu,
            "声调": tone
        }

    def 导入数据(self) -> int:
        """从映射表导入数据到目标表"""
        with self._获取连接() as conn:
            self._确保表结构正确(conn)
            cursor = conn.cursor()

            # 获取源数据
            cursor.execute(f'''
            SELECT 映射编号, 原拼音, 目标拼音 FROM "{self.SOURCE_TABLE}"
            WHERE 目标拼音类型 = '数字标调' AND 目标拼音 IS NOT NULL
            ''')

            # 使用INSERT OR IGNORE避免唯一约束冲突
            cursor.executemany(f'''
            INSERT OR IGNORE INTO "{self.REQUIRED_TABLE}"
            (映射编号, 全拼, 声母, 韵母, 声调)
            VALUES (?, ?, ?, ?, ?)
            ''', [
                (
                    row["映射编号"],
                    row["目标拼音"],
                    *self.解析拼音(row["目标拼音"]).values()
                )
                for row in cursor.fetchall()
            ])

            conn.commit()
            return cursor.rowcount

    def _检查表结构(self, conn: sqlite3.Connection) -> bool:
        """检查数据库表结构是否完整(新增方法)"""
        cursor = conn.cursor()

        # 检查目标表是否存在
        if not self._检查表存在(conn, self.REQUIRED_TABLE):
            self.日志.error(f"表 {self.REQUIRED_TABLE} 不存在")
            return False

        # 检查源表是否存在
        if not self._检查表存在(conn, self.SOURCE_TABLE):
            self.日志.error(f"表 {self.SOURCE_TABLE} 不存在")
            return False

        # 检查源表是否有需要的列
        cursor.execute(f'PRAGMA table_info("{self.SOURCE_TABLE}")')
        源表列 = [col[1] for col in cursor.fetchall()]
        if "原拼音" not in 源表列 or "目标拼音" not in 源表列 or "目标拼音类型" not in 源表列:
            self.日志.error(f"表 {self.SOURCE_TABLE} 缺少必要的列")
            return False

        # 检查目标表是否有需要的列
        cursor.execute(f'PRAGMA table_info("{self.REQUIRED_TABLE}")')
        目标表列 = [col[1] for col in cursor.fetchall()]
        required_columns = ["映射编号", "全拼", "声母", "韵母", "声调"]
        if not all(col in 目标表列 for col in required_columns):
            self.日志.error(f"表 {self.REQUIRED_TABLE} 缺少必要的列")
            return False

        return True

    def 清理重复数据(self) -> int:
        """清理表中的重复拼音数据"""
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

if __name__ == "__main__":
    导入器 = 数字标调拼音导入器()
    try:
        结果 = 导入器.导入数据()
        print(f"导入结果: {结果} 条记录")
    except Exception as e:
        print(f"错误: {e}")