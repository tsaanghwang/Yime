# yime/db_migration.py
import sqlite3
import json
from pathlib import Path
import time
from typing import Dict, List, Tuple
import logging

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class DatabaseMigrator:
    def __init__(self):
        self.base_dir = Path(__file__).parent
        self.db_path = self.base_dir / "pinyin_hanzi.db"
        self.json_path = self.base_dir / "pinyin_hanzi.json"
        self.yinjie_path = self.base_dir / "enhanced_yinjie_mapping.json"

    def _create_tables(self, conn: sqlite3.Connection) -> None:
        """创建所有必要的数据库表"""
        c = conn.cursor()

        # 拼音-汉字主表
        c.execute('''CREATE TABLE IF NOT EXISTS pinyin_hanzi (
                     pinyin TEXT PRIMARY KEY,
                     hanzi TEXT NOT NULL,
                     last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                 )''')

        # 音元符号表
        c.execute('''CREATE TABLE IF NOT EXISTS yinjie_mapping (
                     symbol TEXT PRIMARY KEY,
                     num_tone TEXT NOT NULL,
                     mark_tone TEXT NOT NULL,
                     zhuyin TEXT NOT NULL,
                     last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                 )''')

        # 反向映射表
        c.execute('''CREATE TABLE IF NOT EXISTS yinjie_reverse (
                     key TEXT NOT NULL,
                     key_type TEXT NOT NULL CHECK(key_type IN ('num', 'mark', 'zhuyin')),
                     symbol TEXT NOT NULL,
                     last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                     PRIMARY KEY (key, key_type)
                 )''')

        # 创建索引
        c.execute('''CREATE INDEX IF NOT EXISTS idx_yinjie_reverse_symbol
                     ON yinjie_reverse(symbol)''')

        logger.info("数据库表结构创建/验证完成")

    def _import_pinyin_data(self, conn: sqlite3.Connection) -> int:
        """导入拼音-汉字数据"""
        c = conn.cursor()
        count = 0

        with open(self.json_path, 'r', encoding='utf-8') as f:
            data: Dict[str, List[str]] = json.load(f)

            for pinyin, hanzi_list in data.items():
                if not pinyin or not hanzi_list:
                    logger.warning(f"跳过无效数据: pinyin={pinyin}, hanzi_list={hanzi_list}")
                    continue

                hanzi_str = ''.join(hanzi_list)
                try:
                    c.execute('''INSERT OR REPLACE INTO pinyin_hanzi
                                 (pinyin, hanzi) VALUES (?, ?)''',
                             (pinyin, hanzi_str))
                    count += 1
                except sqlite3.Error as e:
                    logger.error(f"导入拼音数据失败: {pinyin} -> {hanzi_str}: {e}")

        logger.info(f"成功导入 {count} 条拼音-汉字映射")
        return count

    def _import_yinjie_data(self, conn: sqlite3.Connection) -> int:
        """导入音元符号数据"""
        c = conn.cursor()
        count = 0

        with open(self.yinjie_path, 'r', encoding='utf-8') as f:
            yinjie_data: Dict[str, Dict] = json.load(f)

            for category, symbols in yinjie_data.items():
                for symbol, mappings in symbols.items():
                    # 验证数据完整性
                    if not all(k in mappings for k in ['数字标调', '调号标调', '注音符号', '反向映射']):
                        logger.warning(f"音元数据不完整: {symbol}")
                        continue

                    try:
                        # 主映射
                        c.execute('''INSERT OR REPLACE INTO yinjie_mapping
                                    (symbol, num_tone, mark_tone, zhuyin)
                                    VALUES (?, ?, ?, ?)''',
                                (symbol,
                                mappings['数字标调'],
                                mappings['调号标调'],
                                mappings['注音符号']))

                        # 反向映射 - 修正key_type值
                        reverse_mapping = {
                            '数字': 'num',
                            '调号': 'mark',
                            '注音': 'zhuyin'
                        }

                        for key, mapping_types in mappings['反向映射'].items():
                            for mtype, db_type in reverse_mapping.items():
                                if mtype in mapping_types:
                                    c.execute('''INSERT OR REPLACE INTO yinjie_reverse
                                                (key, key_type, symbol)
                                                VALUES (?, ?, ?)''',
                                            (key, db_type, symbol))
                                    count += 1
                    except sqlite3.Error as e:
                        logger.error(f"导入音元数据失败: {symbol}: {e}")

        logger.info(f"成功导入 {count} 条音元映射")
        return count

    def migrate(self) -> None:
        """执行完整的数据迁移流程"""
        start_time = time.time()

        try:
            with sqlite3.connect(self.db_path) as conn:
                # 启用WAL模式提高并发性能
                conn.execute("PRAGMA journal_mode=WAL")
                conn.isolation_level = None  # 禁用自动事务

                # 创建表结构
                self._create_tables(conn)

                # 导入数据
                pinyin_count = self._import_pinyin_data(conn)
                yinjie_count = self._import_yinjie_data(conn)

                # 提交所有更改
                conn.commit()

                # 现在可以安全执行VACUUM
                conn.execute("VACUUM")

                total_time = time.time() - start_time
                logger.info(
                    f"数据迁移完成! "
                    f"拼音记录: {pinyin_count}, "
                    f"音元记录: {yinjie_count}, "
                    f"耗时: {total_time:.2f}秒"
                )

        except Exception as e:
            logger.error(f"数据迁移失败: {e}")
            raise

if __name__ == "__main__":
    migrator = DatabaseMigrator()
    migrator.migrate()