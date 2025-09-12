# yime/map_pinyin_to_hanzi.py
import sqlite3
import json
from pathlib import Path
from typing import Dict, List
import logging
import os

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class PinyinHanziMapper:
    def __init__(self, db_path: str = None, json_path: str = None):
        self.base_dir = Path(__file__).parent
        self.db_path = Path(db_path) if db_path else self.base_dir / "pinyin_hanzi.db"
        self.json_path = Path(json_path) if json_path else self.base_dir / "pinyin_hanzi.json"

    def _migrate_table(self, conn: sqlite3.Connection) -> None:
        """迁移表结构从旧版本到新版本"""
        cursor = conn.cursor()

        # 检查表是否存在
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='homophonic_hanzi'")
        if not cursor.fetchone():
            return  # 表不存在，无需迁移

        # 检查旧表结构
        cursor.execute("PRAGMA table_info(homophonic_hanzi)")
        columns = [col[1] for col in cursor.fetchall()]

        if 'pinyin' in columns and 'standard_pinyin' not in columns:
            # 需要迁移
            logger.info("开始迁移数据库表结构...")
            try:
                # 创建临时表保存数据
                cursor.execute('''CREATE TABLE IF NOT EXISTS homophonic_hanzi_temp (
                             standard_pinyin TEXT PRIMARY KEY,
                             homophonic_hanzi TEXT NOT NULL,
                             last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                         )''')

                # 从旧表复制数据到临时表
                cursor.execute('''INSERT INTO homophonic_hanzi_temp
                              (standard_pinyin, homophonic_hanzi, last_updated)
                              SELECT pinyin, homophonic_hanzi, last_updated
                              FROM homophonic_hanzi''')

                # 删除旧表
                cursor.execute("DROP TABLE homophonic_hanzi")

                # 重命名临时表
                cursor.execute("ALTER TABLE homophonic_hanzi_temp RENAME TO homophonic_hanzi")

                conn.commit()
                logger.info("数据库表结构迁移完成")
            except sqlite3.Error as e:
                conn.rollback()
                logger.error(f"数据库迁移失败: {e}")
                raise

    def _create_table(self, conn: sqlite3.Connection) -> None:
        """创建拼音-汉字表"""
        cursor = conn.cursor()
        self._migrate_table(conn)  # 先尝试迁移

        cursor.execute('''CREATE TABLE IF NOT EXISTS homophonic_hanzi (
                     standard_pinyin TEXT PRIMARY KEY,
                     homophonic_hanzi TEXT NOT NULL,
                     last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                 )''')
        logger.info("拼音-汉字表创建/验证完成")

    def import_pinyin_data(self) -> int:
        """导入拼音-汉字数据"""
        count = 0
        try:
            with sqlite3.connect(self.db_path) as conn:
                # 启用WAL模式提高并发性能
                conn.execute("PRAGMA journal_mode=WAL")
                conn.isolation_level = None  # 禁用自动事务

                # 创建表结构
                self._create_table(conn)

                # 导入数据
                with open(self.json_path, 'r', encoding='utf-8') as f:
                    data: Dict[str, List[str]] = json.load(f)

                    for standard_pinyin, hanzi_list in data.items():
                        if not standard_pinyin or not hanzi_list:
                            logger.warning(f"跳过无效数据: standard_pinyin={standard_pinyin}, hanzi_list={hanzi_list}")
                            continue

                        hanzi_str = ''.join(hanzi_list)
                        try:
                            conn.execute('''INSERT OR REPLACE INTO homophonic_hanzi
                                        (standard_pinyin, homophonic_hanzi) VALUES (?, ?)''',
                                   (standard_pinyin, hanzi_str))
                            count += 1
                        except sqlite3.Error as e:
                            logger.error(f"导入拼音数据失败: {standard_pinyin} -> {hanzi_str}: {e}")

                # 提交所有更改
                conn.commit()
                logger.info(f"成功导入 {count} 条拼音-汉字映射")

        except Exception as e:
            logger.error(f"数据导入失败: {e}")
            raise

        return count

if __name__ == "__main__":
    mapper = PinyinHanziMapper()
    mapper.import_pinyin_data()