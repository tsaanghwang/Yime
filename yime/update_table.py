"""
yime/update_table.py
功能：
1. 当initial_ipa.json文件中的键与pinyin.db中的表initial中的initial相同时，
   用initial_ipa.json中的音标来更新pinyin.db中的表initial中的ipa
2. 如果initial_ipa.json文件中的键与pinyin.db中的表initial中的initial不同时，
   则在pinyin.db中的表initial中添加新的记录，其中initial为键，ipa为值
"""

import json
import sqlite3
from pathlib import Path

def update_initial_table(json_path: str = 'initial_ipa.json',
                        db_path: str = 'pinyin.db',
                        table_name: str = 'initial'):
    # 文件路径
    json_path = Path(json_path).absolute()
    db_path = Path(db_path).absolute()

    # 读取JSON文件
    try:
        with open(json_path, 'r', encoding='utf-8') as f:
            initial_ipa = json.load(f)
    except Exception as e:
        print(f"读取JSON文件失败: {str(e)}")
        return

    # 连接数据库
    try:
        conn = sqlite3.connect(str(db_path))
        cursor = conn.cursor()
    except Exception as e:
        print(f"连接数据库失败: {str(e)}")
        return

    try:
        # 遍历JSON中的每个声母和音标
        for initial, ipa_list in initial_ipa.items():
            # 将音标列表转换为字符串，用逗号分隔
            ipa_str = ', '.join(f"[{ipa}]" for ipa in ipa_list)

            # 检查声母是否已存在 - 使用参数table_name
            cursor.execute(f"SELECT id FROM {table_name} WHERE initial = ?", (initial,))
            existing_record = cursor.fetchone()

            if existing_record:
                # 更新现有记录 - 使用参数table_name
                cursor.execute(
                    f"UPDATE {table_name} SET ipa = ? WHERE initial = ?",
                    (ipa_str, initial)
                )
                print(f"已更新声母 '{initial}' 的音标为: {ipa_str}")
            else:
                # 插入新记录 - 使用参数table_name
                cursor.execute(
                    f"""INSERT INTO {table_name}
                    (initial, ipa, place_of_articulation, manner_of_articulation, remarks)
                    VALUES (?, ?, '', '', '')""",
                    (initial, ipa_str)
                )
                print(f"已添加新声母 '{initial}' 音标: {ipa_str}")

        # 提交事务
        conn.commit()
        print("所有声母音标更新完成")

    except Exception as e:
        print(f"更新数据库时出错: {str(e)}")
        conn.rollback()
    finally:
        conn.close()

if __name__ == '__main__':
    # 主调用使用默认参数，但可以传入自定义路径和表名
    update_initial_table(json_path='initial_ipa.json',
                        db_path='pinyin.db',
                        table_name='initial')