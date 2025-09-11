"""
拼音编码映射工具

功能：
1. 创建SQLite数据库表结构：
   - code_to_pinyin: 编码到拼音的映射(一对多)
   - pinyin_to_code: 拼音到编码的映射(多对多)
2. 从JSON文件加载数据并导入数据库
3. 提供基础CRUD操作接口
"""

import sqlite3
import json
from pathlib import Path
from collections import defaultdict
from typing import List, Dict, Optional, Tuple

# ========== 数据库操作 ==========
def init_database(db_path: str = 'pinyin_hanzi.db') -> None:
    """初始化数据库表结构"""
    conn = None
    try:
        conn = sqlite3.connect(db_path)
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
        cursor.execute('''
        CREATE INDEX IF NOT EXISTS idx_code ON code_to_pinyin(code)
        ''')
        cursor.execute('''
        CREATE INDEX IF NOT EXISTS idx_pinyin ON pinyin_to_code(pinyin)
        ''')

        conn.commit()
    except Exception as e:
        if conn:
            conn.rollback()
        raise
    finally:
        if conn:
            conn.close()

# ========== 数据处理 ==========
def load_json_data(json_path: str) -> Dict[str, str]:
    """加载JSON源数据"""
    json_path = Path(json_path).absolute()
    if not json_path.exists():
        raise FileNotFoundError(f"JSON文件 {json_path} 不存在")

    with open(json_path, 'r', encoding='utf-8') as f:
        return json.load(f)

def normalize_data(yinjie_data: Dict[str, str]) -> Tuple[Dict, Dict]:
    """标准化数据为两种映射关系"""
    code_map = defaultdict(list)
    pinyin_map = defaultdict(list)

    for pinyin, code in yinjie_data.items():
        code_map[code].append(pinyin)
        pinyin_map[pinyin].append(code)

    return code_map, pinyin_map

# ========== 主功能 ==========
def create_table_and_load_data(db_path='pinyin_hanzi.db', json_path='yinjie_code.json'):
    """主功能：创建表并加载数据"""
    try:
        # 初始化数据库
        init_database(db_path)

        # 加载并处理数据
        yinjie_data = load_json_data(json_path)
        code_map, pinyin_map = normalize_data(yinjie_data)

        # 连接数据库
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()

        # 清空现有数据
        cursor.execute('DELETE FROM code_to_pinyin')
        cursor.execute('DELETE FROM pinyin_to_code')

        # 导入code_to_pinyin数据
        for code, pinyins in code_map.items():
            cursor.executemany(
                'INSERT INTO code_to_pinyin (code, pinyin) VALUES (?, ?)',
                [(code, pinyin) for pinyin in pinyins]
            )

        # 导入pinyin_to_code数据
        for pinyin, codes in pinyin_map.items():
            cursor.executemany(
                'INSERT INTO pinyin_to_code (pinyin, code) VALUES (?, ?)',
                [(pinyin, code) for code in codes]
            )

        conn.commit()
        print(f"数据导入完成: {len(code_map)}编码 → {sum(len(v) for v in pinyin_map.values())}拼音映射")
        print(f"成功从 {Path(json_path).absolute()} 导入数据到: {Path(db_path).absolute()}")

    except Exception as e:
        print(f"错误: {str(e)}")
        raise
    finally:
        if 'conn' in locals():
            conn.close()

# ========== 辅助功能 ==========
def query_data(db_path: str = 'pinyin_hanzi.db',
              table_name: str = 'code_to_pinyin',
              condition: Optional[str] = None,
              params: Optional[tuple] = None) -> List[Dict]:
    """通用查询接口"""
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    try:
        query = f"SELECT * FROM {table_name}"
        if condition:
            query += f" WHERE {condition}"
        cursor = conn.cursor()
        cursor.execute(query, params or ())
        return [dict(row) for row in cursor.fetchall()]
    finally:
        conn.close()

if __name__ == '__main__':
    create_table_and_load_data()
