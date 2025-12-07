import sqlite3
from pathlib import Path

def 迁移数字标调拼音表(db_path: str):
    """安全迁移数字标调拼音表结构"""
    db_file = Path(db_path)
    if not db_file.exists():
        raise FileNotFoundError(f"数据库文件不存在: {db_path}")

    with sqlite3.connect(str(db_file)) as conn:
        cursor = conn.cursor()

        # 1. 创建临时表备份数据
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS temp_数字标调拼音 AS
            SELECT * FROM "数字标调拼音"
        ''')

        # 2. 删除原表
        cursor.execute('DROP TABLE IF EXISTS "数字标调拼音"')

        # 3. 创建新表结构
        cursor.execute('''
            CREATE TABLE "数字标调拼音" (
                "编号" INTEGER PRIMARY KEY AUTOINCREMENT,
                "全拼" TEXT NOT NULL UNIQUE,
                "声母" TEXT,
                "韵母" TEXT NOT NULL,
                "声调" INTEGER DEFAULT 1,
                "映射编号" INTEGER REFERENCES "拼音映射关系"("映射编号"),
                "最近更新" TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                UNIQUE ("全拼", "声母", "韵母", "声调")
            )
        ''')

        # 4. 恢复数据
        cursor.execute('''
            INSERT INTO "数字标调拼音"
            SELECT 编号, 全拼, 声母, 韵母, 声调, NULL, 最近更新
            FROM temp_数字标调拼音
        ''')

        # 5. 删除临时表
        cursor.execute('DROP TABLE temp_数字标调拼音')

        conn.commit()
        print("数字标调拼音表迁移完成")

if __name__ == "__main__":
    迁移数字标调拼音表("yime/pinyin_hanzi.db")