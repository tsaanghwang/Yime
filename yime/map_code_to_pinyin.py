"""
    1. 在pinyin_hanzi.db中创建一个表：
    - 表名：yinjie_code
        - 字段：code, pinyin
    2. 加载yinjie_code.json字典文件：
    - 将字典中的键（用数字标调的拼音）作为表yinjie_code的pinyin字段
    - 将字典中值（拼音对应的编码）作为表yinjie_code的code字段
    3. 暂不合并重复的 code 字段
    """

import sqlite3
import json
from pathlib import Path

def create_table_and_load_data(db_path='pinyin_hanzi.db', json_path='yinjie_code.json', table_name='yinjie_code'):
    """
    创建表并加载数据

    参数:
        db_path (str): SQLite数据库文件路径，默认为'pinyin_hanzi.db'
        json_path (str): JSON数据文件路径，默认为'yinjie_code.json'
        table_name (str): 表名，默认为'yinjie_code'
    """
    try:
        # 转换为绝对路径
        db_path = Path(db_path).absolute()
        json_path = Path(json_path).absolute()

        print(f"准备从 {json_path} 导入数据到 {db_path} 的 {table_name} 表")

        if not json_path.exists():
            raise FileNotFoundError(f"JSON文件 {json_path} 不存在")

        # 读取JSON文件
        with open(json_path, 'r', encoding='utf-8') as f:
            yinjie_data = json.load(f)

        # 连接数据库
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()

        # 删除已存在的表
        cursor.execute(f'DROP TABLE IF EXISTS {table_name}')
        print(f"已删除存在的表: {table_name}")

        # 创建新表
        record_count = 0
        cursor.execute(f'''
        CREATE TABLE {table_name} (
            code TEXT NOT NULL,
            pinyin TEXT NOT NULL
        )
        ''')
        # 插入数据
        for pinyin, code in yinjie_data.items():
            cursor.execute(f'INSERT INTO {table_name} (code, pinyin) VALUES (?, ?)', (code, pinyin))
            record_count += 1

        # 提交更改并关闭连接
        conn.commit()
        print(f"成功导入 {record_count} 条记录到 {table_name} 表")

    except Exception as e:
        print(f"导入过程中发生错误: {str(e)}")
        raise
    finally:
        if 'conn' in locals():
            conn.close()

if __name__ == '__main__':
    # 保持原有调用方式不变，使用默认参数
    create_table_and_load_data()
