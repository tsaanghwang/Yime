"""重构版音元拼音导入工具
功能：从"拼音映射关系"表导入数据到"音元拼音"表
"""

import sqlite3
import logging
from pathlib import Path


class PinyinImporter:
    """重构版：从拼音映射关系表导入数据到音元拼音表"""

    REQUIRED_TABLE = "音元拼音"
    SOURCE_TABLE = "拼音映射关系"

    def __init__(self, db_path: str | Path = "pinyin_hanzi.db"):
        self.db_path = Path(db_path).absolute()
        self._setup_logging()

    def _setup_logging(self):
        """配置日志记录"""
        self.logger = logging.getLogger(__name__)
        self.logger.setLevel(logging.INFO)
        formatter = logging.Formatter('%(asctime)s - %(levelname)s - %(message)s')
        console_handler = logging.StreamHandler()
        console_handler.setFormatter(formatter)
        self.logger.addHandler(console_handler)

    def check_table_structure(self) -> bool:
        """检查数据库表结构是否完整"""
        with sqlite3.connect(str(self.db_path)) as conn:
            cursor = conn.cursor()

            # 检查目标表是否存在
            cursor.execute(f"SELECT name FROM sqlite_master WHERE type='table' AND name='{self.REQUIRED_TABLE}'")
            if not cursor.fetchone():
                self.logger.error(f"表 {self.REQUIRED_TABLE} 不存在")
                return False

            # 检查源表是否存在
            cursor.execute(f"SELECT name FROM sqlite_master WHERE type='table' AND name='{self.SOURCE_TABLE}'")
            if not cursor.fetchone():
                self.logger.error(f"表 {self.SOURCE_TABLE} 不存在")
                return False

            # 检查源表是否有需要的列
            cursor.execute(f"PRAGMA table_info({self.SOURCE_TABLE})")
            columns = [col[1] for col in cursor.fetchall()]
            if "原拼音" not in columns or "原拼音类型" not in columns:
                self.logger.error(f"表 {self.SOURCE_TABLE} 缺少必要的列")
                return False

            # 检查目标表是否有映射编号列
            cursor.execute(f"PRAGMA table_info({self.REQUIRED_TABLE})")
            columns = [col[1] for col in cursor.fetchall()]
            if "映射编号" not in columns:
                self.logger.info("目标表缺少映射编号列，将自动添加")
                try:
                    cursor.execute(f"""
                        ALTER TABLE {self.REQUIRED_TABLE}
                        ADD COLUMN 映射编号 INTEGER REFERENCES {self.SOURCE_TABLE}(映射编号)
                    """)
                    conn.commit()
                except Exception as e:
                    self.logger.error(f"添加映射编号列失败: {e}")
                    return False

        return True

    def import_from_mapping(self) -> bool:
        """从拼音映射关系表导入数据到音元拼音表"""
        if not self.check_table_structure():
            return False

        try:
            with sqlite3.connect(str(self.db_path)) as conn:
                cursor = conn.cursor()

                # 清空表中原有记录
                cursor.execute(f'DELETE FROM "{self.REQUIRED_TABLE}"')

                # 从拼音映射关系表导入数据(仅音元拼音类型)
                cursor.execute(f"""
                    INSERT INTO {self.REQUIRED_TABLE} (
                        全拼, 简拼, 首音, 干音, 呼音, 主音, 末音, 间音, 韵音, 映射编号
                    )
                    SELECT
                        原拼音,
                        SUBSTR(原拼音, 1, 1) || CASE WHEN LENGTH(原拼音) > 1 THEN SUBSTR(原拼音, 2, 1) ELSE '' END,
                        SUBSTR(原拼音, 1, 1),
                        CASE WHEN LENGTH(原拼音) > 1 THEN SUBSTR(原拼音, 2) ELSE '' END,
                        NULL, NULL, NULL, NULL, NULL,
                        映射编号
                    FROM {self.SOURCE_TABLE}
                    WHERE 原拼音类型 = '音元拼音'
                """)

                conn.commit()
                self.logger.info(f"成功导入 {cursor.rowcount} 条记录")
                return True

        except Exception as e:
            self.logger.error(f"导入失败: {e}")
            return False

if __name__ == "__main__":
    importer = PinyinImporter()
    if not importer.import_from_mapping():
        exit(1)