"""
数字标调拼音数据导入工具(重构版)

说明：
- 从"拼音映射关系"表导入数据到"数字标调拼音"表
- 确保两表间的引用关系
"""

import sqlite3
import logging
from pathlib import Path
from typing import Dict, List, Optional

class 数字标调拼音导入器:
    """重构版：从拼音映射关系表导入数据"""

    REQUIRED_TABLE = "数字标调拼音"
    SOURCE_TABLE = "拼音映射关系"

    def __init__(self, 数据库路径: str | Path = "pinyin_hanzi.db"):
        self.数据库路径 = Path(数据库路径).absolute()
        self.日志 = logging.getLogger(__name__)
        self.日志.setLevel(logging.INFO)

        # 设置日志格式
        格式 = logging.Formatter('%(asctime)s - %(levelname)s - %(message)s')
        控制台处理器 = logging.StreamHandler()
        控制台处理器.setFormatter(格式)
        self.日志.addHandler(控制台处理器)

    def 检查表结构(self) -> bool:
        """检查数据库表结构是否完整"""
        with sqlite3.connect(self.数据库路径) as 连接:
            游标 = 连接.cursor()

            # 检查目标表是否存在
            游标.execute(f"SELECT name FROM sqlite_master WHERE type='table' AND name='{self.REQUIRED_TABLE}'")
            if not 游标.fetchone():
                self.日志.error(f"表 {self.REQUIRED_TABLE} 不存在")
                return False

            # 检查源表是否存在
            游标.execute(f"SELECT name FROM sqlite_master WHERE type='table' AND name='{self.SOURCE_TABLE}'")
            if not 游标.fetchone():
                self.日志.error(f"表 {self.SOURCE_TABLE} 不存在")
                return False

            # 检查源表是否有需要的列
            游标.execute(f"PRAGMA table_info({self.SOURCE_TABLE})")
            列信息 = [列[1] for 列 in 游标.fetchall()]
            if "原拼音" not in 列信息 or "原拼音类型" not in 列信息:
                self.日志.error(f"表 {self.SOURCE_TABLE} 缺少必要的列")
                return False

        return True

    def 导入数据(self) -> bool:
        """从拼音映射关系表导入数据到数字标调拼音表"""
        if not self.检查表结构():
            return False

        try:
            with sqlite3.connect(self.数据库路径) as 连接:
                游标 = 连接.cursor()

                # 添加外键列(如果不存在)
                游标.execute(f"PRAGMA table_info({self.REQUIRED_TABLE})")
                列信息 = [列[1] for 列 in 游标.fetchall()]
                if "映射编号" not in 列信息:
                    self.日志.info("添加映射编号外键列...")
                    游标.execute(f"""
                        ALTER TABLE {self.REQUIRED_TABLE}
                        ADD COLUMN 映射编号 INTEGER REFERENCES {self.SOURCE_TABLE}(映射编号)
                    """)

                # 从拼音映射关系表导入数据(仅数字标调类型)
                self.日志.info("开始导入数据...")
                游标.execute(f"""
                    INSERT OR IGNORE INTO {self.REQUIRED_TABLE} (全拼, 映射编号)
                    SELECT 原拼音, 映射编号
                    FROM {self.SOURCE_TABLE}
                    WHERE 原拼音类型 = '数字标调'
                """)

                # 更新已存在的记录
                游标.execute(f"""
                    UPDATE {self.REQUIRED_TABLE}
                    SET 映射编号 = (
                        SELECT 映射编号
                        FROM {self.SOURCE_TABLE}
                        WHERE 原拼音 = {self.REQUIRED_TABLE}.全拼
                        AND 原拼音类型 = '数字标调'
                    )
                    WHERE 映射编号 IS NULL
                """)

                连接.commit()
                self.日志.info(f"成功导入/更新 {游标.rowcount} 条记录")
                return True

        except Exception as e:
            self.日志.error(f"导入失败: {e}")
            return False

if __name__ == "__main__":
    导入器 = 数字标调拼音导入器()
    if not 导入器.导入数据():
        exit(1)