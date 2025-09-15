import sqlite3
from pathlib import Path

DB_PATH = Path(__file__).parent / "pinyin_hanzi.db"

CREATE_STMTS = [
    '''
    CREATE TABLE IF NOT EXISTS "音元拼音" (
        "编号" INTEGER PRIMARY KEY,
        "全拼" TEXT NOT NULL UNIQUE,
        "简拼" TEXT,
        "首音" TEXT,
        "干音" TEXT,
        "呼音" TEXT,
        "主音" TEXT,
        "末音" TEXT,
        "间音" TEXT,
        "韵音" TEXT,
        "最近更新" TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS "数字标调拼音" (
        "编号" INTEGER PRIMARY KEY AUTOINCREMENT,
        "全拼" TEXT NOT NULL UNIQUE,
        "声母" TEXT,
        "韵母" TEXT NOT NULL,
        "声调" INTEGER DEFAULT 1,
        "最近更新" TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE ("全拼", "声母", "韵母", "声调")
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS "音元拼音已有拼音映射" (
        "音元拼音" INTEGER REFERENCES "音元拼音"("编号"),
        "数字标调拼音" INTEGER REFERENCES "数字标调拼音"("编号"),
        "标准拼音" TEXT NOT NULL,
        "注音符号" TEXT NOT NULL,
        "最近更新" TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY ("音元拼音", "数字标调拼音")
    )
    '''
]

def main():
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(DB_PATH))
    try:
        cur = conn.cursor()
        for stmt in CREATE_STMTS:
            cur.execute(stmt)
        cur.execute('CREATE INDEX IF NOT EXISTS "索引_数字标调拼音_数字标调拼音" ON "数字标调拼音"("全拼")')
        cur.execute('CREATE INDEX IF NOT EXISTS "索引_音元拼音已有拼音映射_标准拼音" ON "音元拼音已有拼音映射"("标准拼音")')
        cur.execute('CREATE INDEX IF NOT EXISTS "索引_音元拼音已有拼音映射_注音符号" ON "音元拼音已有拼音映射"("注音符号")')
        conn.commit()
        print(f"已创建/验证表结构: {DB_PATH}")
    finally:
        conn.close()

if __name__ == "__main__":
    main()
    # del "c:\Users\Freeman Golden\OneDrive\Yime\pinyin_hanzi.db"
