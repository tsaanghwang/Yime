# yime/map_pinyin_to_hanzi.py
import sqlite3
import json
from pathlib import Path
from typing import Dict, List
import logging

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class PinyinHanziMapper:
    def __init__(self, db_path: str = None, json_path: str = None):
        self.module_dir = Path(__file__).parent
        self.db_path = Path(db_path) if db_path else self.module_dir / "pinyin_hanzi.db"
        self.json_path = Path(json_path) if json_path else self.module_dir / "pinyin_hanzi.json"

    def _migrate_table(self, conn: sqlite3.Connection) -> None:
        """迁移表结构从旧版本到新版本"""
        cursor = conn.cursor()

        # 检查表是否存在
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='标准拼音同音字表'")
        if not cursor.fetchone():
            return  # 表不存在，无需迁移

        # 检查旧表结构
        cursor.execute("PRAGMA table_info(标准拼音同音字表)")
        columns = [col[1] for col in cursor.fetchall()]

        if 'pinyin' in columns and '标准拼音' not in columns:
            # 需要迁移
            logger.info("开始迁移数据库表结构...")
            try:
                # 创建临时表保存数据
                cursor.execute('''CREATE TABLE IF NOT EXISTS 临时字表 (
                             标准拼音 TEXT PRIMARY KEY,
                             同音字集 TEXT NOT NULL,
                             最近更新 TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                         )''')

                # 从旧表复制数据到临时表
                cursor.execute('''INSERT INTO 临时字表
                              (标准拼音, 同音字集, 最近更新)
                              SELECT pinyin, 同音字集, 最近更新
                              FROM 标准拼音同音字表''')

                # 删除旧表
                cursor.execute("DROP TABLE 标准拼音同音字表")

                # 重命名临时表
                cursor.execute("ALTER TABLE 临时字表 RENAME TO 标准拼音同音字表")

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

        cursor.execute('''CREATE TABLE IF NOT EXISTS 标准拼音同音字表 (
                     标准拼音 TEXT PRIMARY KEY,
                     同音字集 TEXT NOT NULL,
                     最近更新 TIMESTAMP DEFAULT CURRENT_TIMESTAMP
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

                    for 标准拼音, hanzi_list in data.items():
                        if not 标准拼音 or not hanzi_list:
                            logger.warning(f"跳过无效数据: 标准拼音={标准拼音}, hanzi_list={hanzi_list}")
                            continue

                        hanzi_str = ''.join(hanzi_list)
                        try:
                            conn.execute('''INSERT OR REPLACE INTO 标准拼音同音字表
                                        (标准拼音, 同音字集) VALUES (?, ?)''',
                                   (标准拼音, hanzi_str))
                            count += 1
                        except sqlite3.Error as e:
                            logger.error(f"导入拼音数据失败: {标准拼音} -> {hanzi_str}: {e}")

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