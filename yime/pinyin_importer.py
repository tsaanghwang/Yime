"""
重构版音元拼音导入工具
功能：从"拼音映射关系"表导入数据到"音元拼音"表
"""

import sqlite3
import logging
from pathlib import Path
from typing import Optional, Set, List, Tuple
from db_manager import DB_PATH


class PinyinImporter:
    """重构版：从拼音映射关系表导入数据到音元拼音表"""

    REQUIRED_TABLE = "音元拼音"
    SOURCE_TABLE = "拼音映射关系"

    def __init__(self, db_path: str | Path = "C:/Users/Freeman Golden/OneDrive/Yime/yime/pinyin_hanzi.db"):
        """
        初始化导入器
        :param db_path: 数据库文件路径，默认为当前目录下的 pinyin_hanzi.db
        """
        self.db_path = Path(db_path).absolute()
        self._setup_logging()
        self.logger.info(f"初始化拼音导入器，数据库路径: {self.db_path}")

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
        try:
            with sqlite3.connect(str(self.db_path)) as conn:
                cursor = conn.cursor()

                # 检查表是否存在
                for table in [self.REQUIRED_TABLE, self.SOURCE_TABLE]:
                    cursor.execute(
                        "SELECT name FROM sqlite_master "
                        "WHERE type='table' AND name=?", (table,)
                    )
                    if not cursor.fetchone():
                        self.logger.error(f"表 {table} 不存在")
                        return False

                # 检查音元拼音表是否有映射编号列和外键约束
                cursor.execute(f"PRAGMA foreign_key_list({self.REQUIRED_TABLE})")
                fk_exists = any(fk[2] == self.SOURCE_TABLE for fk in cursor.fetchall())

                if not fk_exists:
                    self.logger.info("目标表缺少映射编号外键约束，将尝试添加约束")
                    try:
                        # 获取当前表结构
                        cursor.execute(f"SELECT sql FROM sqlite_master WHERE type='table' AND name='{self.REQUIRED_TABLE}'")
                        table_sql = cursor.fetchone()[0]

                        if "FOREIGN KEY" not in table_sql:
                            # 创建新表并迁移数据
                            cursor.execute(f"""
                                CREATE TABLE {self.REQUIRED_TABLE}_new (
                                    编号 INTEGER PRIMARY KEY AUTOINCREMENT,
                                    全拼 TEXT NOT NULL UNIQUE,
                                    简拼 TEXT NOT NULL UNIQUE,
                                    首音 TEXT,
                                    干音 TEXT NOT NULL,
                                    呼音 TEXT,
                                    主音 TEXT,
                                    末音 TEXT,
                                    间音 TEXT,
                                    韵音 TEXT,
                                    最近更新 TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                                    映射编号 INTEGER REFERENCES {self.SOURCE_TABLE}(映射编号),
                                    UNIQUE ("全拼", "首音", "干音")
                                )
                            """)
                            cursor.execute(f"""
                                INSERT INTO {self.REQUIRED_TABLE}_new
                                SELECT *, NULL FROM {self.REQUIRED_TABLE}
                            """)
                            cursor.execute(f"DROP TABLE {self.REQUIRED_TABLE}")
                            cursor.execute(f"ALTER TABLE {self.REQUIRED_TABLE}_new RENAME TO {self.REQUIRED_TABLE}")
                            conn.commit()
                    except Exception as e:
                        self.logger.error(f"添加外键约束失败: {e}")
                        return False

                return True

        except Exception as e:
            self.logger.error(f"检查表结构时出错: {e}")
            return False

    def _get_existing_jianpin(self, cursor: sqlite3.Cursor) -> Set[str]:
        """获取当前已存在的简拼集合"""
        cursor.execute(f'SELECT 简拼 FROM "{self.REQUIRED_TABLE}"')
        return {row[0] for row in cursor.fetchall()}

    def _resolve_jianpin_conflict(
        self,
        jianpin: str,
        used_jianpin: Set[str]
    ) -> Tuple[str, Set[str]]:
        """
        处理简拼冲突
        :param jianpin: 原始简拼
        :param used_jianpin: 已使用的简拼集合
        :return: (处理后的简拼, 更新后的已使用简拼集合)
        """
        original_jianpin = jianpin
        suffix = 1
        while jianpin in used_jianpin:
            jianpin = f"{original_jianpin}{suffix}"
            suffix += 1
        used_jianpin.add(jianpin)
        return jianpin, used_jianpin

    def _import_data(self, cursor: sqlite3.Cursor) -> Optional[int]:
        """
        执行实际的数据导入
        :param cursor: 数据库游标
        :return: 成功导入的记录数，失败返回None
        """
        # 获取当前已存在的映射关系
        cursor.execute(f'SELECT 映射编号 FROM "{self.REQUIRED_TABLE}" WHERE 映射编号 IS NOT NULL')
        existing_mappings = {row[0] for row in cursor.fetchall()}

        # 获取当前已存在的简拼集合
        existing_jianpin = self._get_existing_jianpin(cursor)

        # 查询源数据中未导入的记录
        cursor.execute(f"""
            SELECT 原拼音, 映射编号
            FROM {self.SOURCE_TABLE}
            WHERE 原拼音类型 = '音元拼音'
            AND (映射编号 NOT IN ({','.join('?' for _ in existing_mappings)})
                OR {'1=1' if not existing_mappings else f'映射编号 NOT IN ({",".join("?" for _ in existing_mappings)})'})
        """, tuple(existing_mappings) * 2 if existing_mappings else ())
        rows = cursor.fetchall()

        if not rows:
            self.logger.info("没有需要导入的新记录")
            return 0

        # 合并新旧简拼集合
        used_jianpin = set(existing_jianpin)

        for row in rows:
            yuan_pinyin, mapping_id = row
            jianpin = yuan_pinyin[0] + (yuan_pinyin[1] if len(yuan_pinyin) > 1 else '')

            # 处理简拼冲突
            jianpin, used_jianpin = self._resolve_jianpin_conflict(jianpin, used_jianpin)

            # 插入记录
            cursor.execute(f"""
                INSERT INTO {self.REQUIRED_TABLE} (
                    全拼, 简拼, 首音, 干音, 呼音, 主音, 末音, 间音, 韵音, 映射编号
                )
                VALUES (?, ?, ?, ?, NULL, NULL, NULL, NULL, NULL, ?)
            """, (
                yuan_pinyin,
                jianpin,
                yuan_pinyin[0],
                yuan_pinyin[1:] if len(yuan_pinyin) > 1 else '',
                mapping_id
            ))

        return len(rows)

    def import_from_mapping(self) -> bool:
        """
        从拼音映射关系表导入数据到音元拼音表
        :return: 导入是否成功
        """
        if not self.check_table_structure():
            return False

        try:
            with sqlite3.connect(str(self.db_path)) as conn:
                conn.execute("PRAGMA foreign_keys = ON")  # 启用外键约束
                cursor = conn.cursor()

                # 开始事务
                conn.execute("BEGIN TRANSACTION")

                try:
                    record_count = self._import_data(cursor)
                    if record_count is None:
                        raise RuntimeError("数据导入失败")

                    conn.commit()
                    self.logger.info(f"成功导入 {record_count} 条记录")
                    return True

                except Exception as e:
                    conn.rollback()
                    self.logger.error(f"导入过程中出错，已回滚: {e}")
                    return False

        except Exception as e:
            self.logger.error(f"数据库连接失败: {e}")
            return False


if __name__ == "__main__":
    # 配置根日志记录器
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )

    importer = PinyinImporter()
    if not importer.import_from_mapping():
        exit(1)

    import sqlite3
    conn = sqlite3.connect("C:/Users/Freeman Golden/OneDrive/Yime/yime/pinyin_hanzi.db")
    print(conn.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall())
