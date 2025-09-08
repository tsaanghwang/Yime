"""
把数据表yime/shengmu.csv转换成数据库中的表:
表名：initial
字段：id,initial,ipa,place_of_articulation,manner_of_articulation,remarks
"""
import csv
import os
import sys
from pathlib import Path
import sqlite3

def create_database_tables(db_path: str = 'pinyin.db'):
    """
    创建拼音输入法所需的数据库表结构
    参数:
        db_path: 数据库文件路径，默认为pinyin.db
    """
    conn = None  # 初始化变量
    try:
        # 转换为绝对路径
        db_path = Path(db_path).absolute()
        print(f"数据库将创建在: {db_path}")

        # 确保目录存在
        db_path.parent.mkdir(parents=True, exist_ok=True)
        print(f"目录已确认存在: {db_path.parent}")

        conn = sqlite3.connect(str(db_path))
        cursor = conn.cursor()
        print("数据库连接已建立")

        # 1. 创建基础拼音-汉字映射表
        cursor.execute("""
        CREATE TABLE IF NOT EXISTS pinyin_hanzi (
            pinyin TEXT NOT NULL,
            hanzi TEXT NOT NULL,
            PRIMARY KEY (pinyin, hanzi)
        )""")

        # 2. 创建频率调整表
        cursor.execute("""
        CREATE TABLE IF NOT EXISTS frequency_adjustment (
            pinyin TEXT NOT NULL,
            hanzi TEXT NOT NULL,
            base_freq INTEGER DEFAULT 100,
            user_freq INTEGER DEFAULT 0,
            last_used TIMESTAMP,
            context_freq INTEGER DEFAULT 0,
            boost_factor REAL DEFAULT 1.0,
            PRIMARY KEY (pinyin, hanzi),
            FOREIGN KEY (pinyin, hanzi) REFERENCES pinyin_hanzi(pinyin, hanzi)
        )""")

        # 3. 创建用户输入日志表
        cursor.execute("""
        CREATE TABLE IF NOT EXISTS user_input_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            pinyin TEXT NOT NULL,
            hanzi TEXT NOT NULL,
            input_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            context TEXT,
            FOREIGN KEY (pinyin, hanzi) REFERENCES pinyin_hanzi(pinyin, hanzi)
        )""")

        # 4. 创建频率更新触发器
        cursor.execute("""
        CREATE TRIGGER IF NOT EXISTS update_frequency
        AFTER INSERT ON user_input_log
        FOR EACH ROW
        BEGIN
            UPDATE frequency_adjustment
            SET user_freq = user_freq + 1,
                last_used = CURRENT_TIMESTAMP
            WHERE pinyin = NEW.pinyin AND hanzi = NEW.hanzi;
        END;
        """)

        # 5. 创建通用映射表(用于音元直接转换)
        cursor.execute("""
        CREATE TABLE IF NOT EXISTS universal_map (
            yinjie TEXT NOT NULL,
            pinyin TEXT NOT NULL,
            hanzi TEXT NOT NULL,
            PRIMARY KEY (yinjie, pinyin, hanzi)
        )""")

        conn.commit()
        print(f"数据库表结构已成功创建于: {db_path}")

        # 检查文件是否真的存在
        if db_path.exists():
            print(f"数据库文件已确认存在，大小: {db_path.stat().st_size} 字节")
        else:
            print("警告: 数据库文件未创建成功")

    except Exception as e:
        print(f"创建数据库表时出错: {str(e)}")
    finally:
        if 'conn' in locals() and conn:
            conn.close()
            print("数据库连接已关闭")

if __name__ == '__main__':
    create_database_tables()