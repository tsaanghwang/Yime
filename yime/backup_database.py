from pathlib import Path
import shutil
import sqlite3
import hashlib
import sys
from datetime import datetime

SRC = (Path(__file__).resolve().parent / "pinyin_hanzi.db").resolve()
BACKUP_DIR = SRC.parent / "backup"


def sha256_of_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    if not SRC.exists():
        print(f"错误：源数据库不存在：{SRC}")
        sys.exit(1)

    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    dst = BACKUP_DIR / f"pinyin_hanzi.{datetime.now():%Y%m%d_%H%M%S}.db.bak"
    try:
        shutil.copy2(SRC, dst)
    except Exception as e:
        print(f"备份失败: {e}")
        sys.exit(1)

    print(f"备份完成: {dst}")
    print(f"大小: {dst.stat().st_size} bytes")
    try:
        digest = sha256_of_file(dst)
        print(f"SHA256: {digest}")
    except Exception as e:
        print(f"计算哈希失败: {e}")

    # SQLite 内部一致性检查
    try:
        con = sqlite3.connect(str(dst))
        cur = con.cursor()
        cur.execute("PRAGMA integrity_check;")
        res = cur.fetchone()
        con.close()
        status = res[0] if res else None
        print(f"PRAGMA integrity_check -> {status!r}")
        if status != "ok":
            print("警告：数据库完整性检查未通过，请勿替换生产文件。")
            sys.exit(2)
    except Exception as e:
        print(f"运行 integrity_check 时出错: {e}")
        sys.exit(1)

    print("备份与完整性检查通过。")


if __name__ == "__main__":
    main()
