"""
将yime/shengmu.csv导入数据库中的initial表
表结构：
- id: 自增主键
- initial: 声母
- ipa: 国际音标
- place_of_articulation: 发音部位
- manner_of_articulation: 发音方法
- remarks: 备注
"""

import csv
import sqlite3
from pathlib import Path

def import_shengmu_to_db(csv_path: str = 'shengmu.csv',
                        db_path: str = 'pinyin.db',
                        table_name: str = 'initial'):
    """
    将声母CSV文件导入SQLite数据库
    参数:
        csv_path: CSV文件路径
        db_path: 数据库文件路径
        table_name: 目标表名
    """
    try:
        # 转换为绝对路径
        csv_path = Path(csv_path).absolute()
        db_path = Path(db_path).absolute()

        print(f"准备从 {csv_path} 导入数据到 {db_path} 的 {table_name} 表")

        # 确保CSV文件存在
        if not csv_path.exists():
            raise FileNotFoundError(f"CSV文件不存在: {csv_path}")

        # 连接数据库
        conn = sqlite3.connect(str(db_path))
        cursor = conn.cursor()

        # 删除已存在的表(如果存在)
        cursor.execute(f"DROP TABLE IF EXISTS {table_name}")
        print(f"已删除存在的表: {table_name}")


        # 创建表(如果不存在)
        cursor.execute(f"""
        CREATE TABLE {table_name} (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            initial TEXT NOT NULL,
            ipa TEXT NOT NULL,
            place_of_articulation TEXT NOT NULL,
            manner_of_articulation TEXT NOT NULL,
            remarks TEXT
        )
        """)

        # 读取CSV并插入数据
        record_count = 0
        with open(csv_path, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            for row in reader:
                cursor.execute(f"""
                INSERT INTO {table_name} (
                    initial, ipa, place_of_articulation,
                    manner_of_articulation, remarks
                ) VALUES (?, ?, ?, ?, ?)
                """, (
                    row['声母'],
                    row['国际音标(IPA)'],
                    row['发音部位'],
                    row['发音方法'],
                    row['备注']
                ))
                record_count += 1

        conn.commit()
        print(f"成功导入 {record_count} 条记录到 {table_name} 表")

    except Exception as e:
        print(f"导入过程中发生错误: {str(e)}")
        raise
    finally:
        if 'conn' in locals():
            conn.close()

if __name__ == '__main__':
    import_shengmu_to_db()