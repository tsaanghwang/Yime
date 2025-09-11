"""
拼音编码映射工具(面向对象重构版)

功能：
1. 封装SQLite数据库操作
2. 提供数据导入和查询接口
3. 支持编码与拼音的双向映射
"""

import sqlite3
import json
from pathlib import Path
from collections import defaultdict
from typing import List, Dict, Optional, Tuple, Iterator
import logging

class PinyinMapper:
    """拼音编码映射核心类"""

    def __init__(self, db_path: str = 'pinyin_hanzi.db'):
        """初始化数据库连接路径"""
        self.db_path = Path(db_path).absolute()
        self._setup_logging()

    def _setup_logging(self):
        """配置日志记录"""
        logging.basicConfig(
            level=logging.DEBUG,
            format='%(asctime)s - %(levelname)s - %(message)s'
        )
        self.logger = logging.getLogger(__name__)

    def _get_connection(self) -> sqlite3.Connection:
        """获取数据库连接"""
        conn = sqlite3.connect(str(self.db_path))
        conn.row_factory = sqlite3.Row
        return conn

    def init_database(self) -> None:
        """初始化数据库表结构"""
        with self._get_connection() as conn:
            cursor = conn.cursor()

            # 编码→拼音表
            cursor.execute('''
            CREATE TABLE IF NOT EXISTS code_to_pinyin (
                code TEXT NOT NULL,
                pinyin TEXT NOT NULL
            )''')

            # 拼音→编码表
            cursor.execute('''
            CREATE TABLE IF NOT EXISTS pinyin_to_code (
                pinyin TEXT NOT NULL,
                code TEXT NOT NULL,
                PRIMARY KEY (pinyin, code)
            )''')

            # 创建索引
            cursor.execute('CREATE INDEX IF NOT EXISTS idx_code ON code_to_pinyin(code)')
            cursor.execute('CREATE INDEX IF NOT EXISTS idx_pinyin ON pinyin_to_code(pinyin)')
            conn.commit()
            self.logger.debug("数据库表结构初始化完成")

    def load_json_data(self, json_path: str) -> Dict[str, str]:
        """加载JSON源数据"""
        json_path = Path(json_path).absolute()
        if not json_path.exists():
            raise FileNotFoundError(f"JSON文件 {json_path} 不存在")

        with open(json_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
            self.logger.debug(f"从 {json_path} 加载了 {len(data)} 条数据")
            return data

    def normalize_data(self, yinjie_data: Dict[str, str]) -> Tuple[Dict, Dict]:
        """标准化数据为两种映射关系"""
        code_map = defaultdict(list)
        pinyin_map = defaultdict(list)

        for pinyin, code in yinjie_data.items():
            code_map[code].append(pinyin)
            pinyin_map[pinyin].append(code)

        self.logger.debug(f"标准化数据完成: {len(code_map)}编码, {len(pinyin_map)}拼音")
        return code_map, pinyin_map

    def import_data(self, json_path: str) -> Tuple[Dict, Dict]:
        """导入数据到数据库"""
        try:
            # 初始化数据库
            self.init_database()

            # 加载并处理数据
            yinjie_data = self.load_json_data(json_path)
            code_map, pinyin_map = self.normalize_data(yinjie_data)

            with self._get_connection() as conn:
                cursor = conn.cursor()

                # 清空现有数据
                cursor.execute('DELETE FROM code_to_pinyin')
                cursor.execute('DELETE FROM pinyin_to_code')

                # 批量导入数据
                cursor.executemany(
                    'INSERT INTO code_to_pinyin (code, pinyin) VALUES (?, ?)',
                    ((code, pinyin) for code, pinyins in code_map.items() for pinyin in pinyins)
                )

                cursor.executemany(
                    'INSERT INTO pinyin_to_code (pinyin, code) VALUES (?, ?)',
                    ((pinyin, code) for pinyin, codes in pinyin_map.items() for code in codes)
                )

                conn.commit()
                self.logger.info(
                    f"数据导入完成: {len(code_map)}编码 → {sum(len(v) for v in pinyin_map.values())}拼音映射"
                )

            return code_map, pinyin_map

        except Exception as e:
            self.logger.error(f"数据导入失败: {str(e)}")
            raise

    def query(self, table_name: str, condition: str = None, params: tuple = None) -> List[Dict]:
        """通用查询接口"""
        with self._get_connection() as conn:
            query = f"SELECT * FROM {table_name}"
            if condition:
                query += f" WHERE {condition}"

            cursor = conn.cursor()
            cursor.execute(query, params or ())
            return [dict(row) for row in cursor.fetchall()]

    def get_pinyin_by_code(self, code: str) -> List[str]:
        """根据编码获取拼音列表"""
        return [row['pinyin'] for row in self.query('code_to_pinyin', 'code = ?', (code,))]

    def get_code_by_pinyin(self, pinyin: str) -> List[str]:
        """根据拼音获取编码列表"""
        return [row['code'] for row in self.query('pinyin_to_code', 'pinyin = ?', (pinyin,))]

if __name__ == '__main__':
    # 使用示例
    mapper = PinyinMapper()
    code_map, pinyin_map = mapper.import_data('yinjie_code.json')

    # 查询示例
    print("编码'abc'对应的拼音:", mapper.get_pinyin_by_code('abc'))
    print("拼音'ni'对应的编码:", mapper.get_code_by_pinyin('ni'))