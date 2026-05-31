# unicode_hanzi_db.py
import csv
import json
from pathlib import Path
import sqlite3
from typing import Any, TypeAlias, cast

DB_FILE = Path(__file__).resolve().with_name("unicode_hanzi.db")
UNICODE_HANZI_FILE = Path(__file__).resolve().with_name("unicode_hanzi.txt")

PinyinMap: TypeAlias = dict[str, list[str]]
HanziRow: TypeAlias = tuple[str, str, str, str, float, str]

DEFAULT_FREQ = 0.00001

BLOCKS = [
    (0x3007, 0x3007,       "零的小写"),
    (0x4E00, 0x9FFF,       "基本汉字"),
    (0x3400, 0x4DBF,       "扩展A"),
    (0x20000, 0x2A6DF,     "扩展B"),
    (0x2A700, 0x2B73F,     "扩展C"),
    (0x2B740, 0x2B81F,     "扩展D"),
    (0x2B820, 0x2CEAF,     "扩展E"),
    (0x2CEB0, 0x2EBEF,     "扩展F"),
    (0x30000, 0x3134F,     "扩展G"),
    (0x31350, 0x323AF,     "扩展H"),
    (0x2EBF0, 0x2EE5F,     "扩展I"),
    (0xF900, 0xFAFF,       "兼容汉字"),
    (0x2F800, 0x2FA1F,     "兼容补充"),
    (0x2F00, 0x2FDF,       "康熙部首"),
    (0x2FF0, 0x2FFF,       "表意文字描述符"),
    (0x31C0, 0x31EF,       "CJK笔画"),
]


def load_pinyin_data() -> PinyinMap:
    """从当前目录下的 unicode_hanzi.txt 读取单字拼音数据。"""
    if not UNICODE_HANZI_FILE.exists():
        raise FileNotFoundError(f"未找到拼音数据文件: {UNICODE_HANZI_FILE}")

    pinyin_map: PinyinMap = {}

    with UNICODE_HANZI_FILE.open("r", encoding="utf-8", newline="") as file_obj:
        reader = csv.reader(file_obj, delimiter="\t")
        for row in reader:
            if not row:
                continue
            if row[0].startswith("#") or row[0] == "codepoint":
                continue
            if len(row) < 4:
                continue

            codepoint = row[0].strip().upper()
            primary = row[2].strip()
            candidates_json = row[3].strip()
            if not codepoint:
                continue

            try:
                parsed_candidates: Any = json.loads(candidates_json) if candidates_json else []
            except json.JSONDecodeError:
                parsed_candidates = []

            raw_candidates: list[Any]
            if isinstance(parsed_candidates, list):
                raw_candidates = cast(list[Any], parsed_candidates)
            else:
                raw_candidates = []
            candidates: list[str] = []
            for item in raw_candidates:
                if isinstance(item, str) and item.strip():
                    candidates.append(item.strip())

            if primary and primary not in candidates:
                candidates.insert(0, primary)

            if candidates:
                pinyin_map[codepoint] = candidates

    return pinyin_map


def get_pinyin_values(codepoint: str, pinyin_map: PinyinMap) -> tuple[str, str]:
    """返回基础注音和多音候选。"""
    candidates = pinyin_map.get(codepoint, [])
    primary = candidates[0] if candidates else ""
    return primary, json.dumps(candidates, ensure_ascii=False)


def build_db():
    pinyin_map = load_pinyin_data()

    conn = sqlite3.connect(DB_FILE)
    cur = conn.cursor()

    cur.execute("DROP VIEW IF EXISTS view_hanzi_long")
    cur.execute("DROP VIEW IF EXISTS view_basic_hanzi")
    cur.execute("DROP VIEW IF EXISTS view_hanzi_by_frequency")
    cur.execute("DROP VIEW IF EXISTS view_hanzi_zhong")
    cur.execute("DROP VIEW IF EXISTS view_hanzi_polyphonic")
    cur.execute("DROP VIEW IF EXISTS view_hanzi_with_pinyin")
    cur.execute("DROP VIEW IF EXISTS view_hanzi_without_pinyin")
    cur.execute("DROP VIEW IF EXISTS view_hanzi_single_candidate_not_toned")
    cur.execute("DROP TABLE IF EXISTS hanzi")

    cur.execute("""
        CREATE TABLE hanzi (
            codepoint   TEXT PRIMARY KEY,
            hanzi       TEXT NOT NULL,
            pinyin      TEXT,
            pinyin_candidates TEXT,
            frequency   REAL,
            block       TEXT
        )
    """)

    cur.execute("CREATE INDEX IF NOT EXISTS idx_block ON hanzi(block)")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_hanzi_hanzi ON hanzi(hanzi)")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_pinyin ON hanzi(pinyin)")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_freq ON hanzi(frequency DESC)")

    conn.commit()

    batch: list[HanziRow] = []
    total = 0

    for start, end, block_name in BLOCKS:
        count = 0
        for cp in range(start, end + 1):
            codepoint = f"U+{cp:X}"
            char = chr(cp)
            py, pinyin_candidates = get_pinyin_values(codepoint, pinyin_map)
            freq = DEFAULT_FREQ

            batch.append((
                codepoint,
                char,
                py,
                pinyin_candidates,
                freq,
                block_name
            ))
            count += 1
            total += 1

            if len(batch) >= 5000:
                cur.executemany(
                    "INSERT INTO hanzi VALUES (?,?,?,?,?,?)",
                    batch
                )
                batch = []
                conn.commit()

        if batch:
            cur.executemany(
                "INSERT INTO hanzi VALUES (?,?,?,?,?,?)",
                batch
            )
            batch = []
            conn.commit()

        print(f"{block_name}: {count:,} 个")

    conn.close()
    print(f"\n合计: {total:,} 个汉字")
    print(f"数据库: {DB_FILE}")


def create_views():
    conn = sqlite3.connect(DB_FILE)
    cur = conn.cursor()

    print("\n── 创建视图 ──")

    cur.execute("CREATE INDEX IF NOT EXISTS idx_hanzi_hanzi ON hanzi(hanzi)")

    cur.execute("DROP VIEW IF EXISTS view_hanzi_long")
    cur.execute("DROP VIEW IF EXISTS view_basic_hanzi")
    cur.execute("DROP VIEW IF EXISTS view_hanzi_by_frequency")
    cur.execute("DROP VIEW IF EXISTS view_hanzi_zhong")
    cur.execute("DROP VIEW IF EXISTS view_hanzi_polyphonic")
    cur.execute("DROP VIEW IF EXISTS view_hanzi_with_pinyin")
    cur.execute("DROP VIEW IF EXISTS view_hanzi_without_pinyin")
    cur.execute("DROP VIEW IF EXISTS view_hanzi_single_candidate_not_toned")

    cur.execute("""
        CREATE VIEW view_hanzi_long AS
        SELECT codepoint, hanzi, pinyin, pinyin_candidates, frequency, block
        FROM hanzi
        WHERE hanzi = '龙'
    """)

    cur.execute("""
        CREATE VIEW view_basic_hanzi AS
        SELECT codepoint, hanzi, pinyin, pinyin_candidates, frequency, block
        FROM hanzi
        WHERE block = '基本汉字'
    """)

    cur.execute("""
        CREATE VIEW view_hanzi_by_frequency AS
        SELECT codepoint, hanzi, pinyin, pinyin_candidates, frequency, block
        FROM hanzi
        ORDER BY frequency DESC, codepoint ASC
    """)

    cur.execute("""
        CREATE VIEW view_hanzi_zhong AS
        SELECT codepoint, hanzi, pinyin, pinyin_candidates, frequency, block
        FROM hanzi
        WHERE EXISTS (
            SELECT 1
            FROM json_each(hanzi.pinyin_candidates)
            WHERE json_each.value = 'zhōng'
        )
    """)

    cur.execute("""
        CREATE VIEW view_hanzi_polyphonic AS
        SELECT codepoint, hanzi, pinyin, pinyin_candidates, frequency, block
        FROM hanzi
        WHERE json_array_length(pinyin_candidates) > 1
    """)

    cur.execute("""
        CREATE VIEW view_hanzi_with_pinyin AS
        SELECT codepoint, hanzi, pinyin, pinyin_candidates, frequency, block
        FROM hanzi
        WHERE pinyin <> ''
    """)

    cur.execute("""
        CREATE VIEW view_hanzi_without_pinyin AS
        SELECT codepoint, hanzi, pinyin, pinyin_candidates, frequency, block
        FROM hanzi
        WHERE pinyin = ''
    """)

    cur.execute("""
        CREATE VIEW view_hanzi_single_candidate_not_toned AS
        SELECT codepoint, hanzi, pinyin, pinyin_candidates, frequency, block
        FROM hanzi
        WHERE pinyin <> ''
          AND pinyin_candidates IS NOT NULL
          AND pinyin_candidates <> ''
          AND json_array_length(pinyin_candidates) = 1
          AND NOT (
              pinyin GLOB '*[āáǎàēéěèīíǐìōóǒòūúǔùǖǘǚǜńňǹḿ]*'
          )
    """)

    conn.commit()

    cur.execute("SELECT * FROM view_hanzi_long")
    print(f"view_hanzi_long: {cur.fetchone()}")

    cur.execute("SELECT hanzi, pinyin, pinyin_candidates, frequency FROM view_basic_hanzi LIMIT 5")
    print(f"view_basic_hanzi 前5个: {cur.fetchall()}")

    cur.execute(
        "SELECT hanzi, pinyin, pinyin_candidates, frequency "
        "FROM view_hanzi_by_frequency WHERE block = '基本汉字' LIMIT 10"
    )
    print(f"view_hanzi_by_frequency 前10个: {cur.fetchall()}")

    cur.execute("SELECT hanzi, pinyin_candidates, frequency FROM view_hanzi_zhong LIMIT 5")
    print(f"view_hanzi_zhong 前5个: {cur.fetchall()}")

    cur.execute("SELECT hanzi, pinyin_candidates FROM view_hanzi_polyphonic LIMIT 5")
    print(f"view_hanzi_polyphonic 前5个: {cur.fetchall()}")

    cur.execute("SELECT hanzi, pinyin FROM view_hanzi_with_pinyin LIMIT 5")
    print(f"view_hanzi_with_pinyin 前5个: {cur.fetchall()}")

    cur.execute("SELECT codepoint, hanzi FROM view_hanzi_without_pinyin LIMIT 5")
    print(f"view_hanzi_without_pinyin 前5个: {cur.fetchall()}")

    cur.execute("SELECT codepoint, hanzi, pinyin, block FROM view_hanzi_single_candidate_not_toned LIMIT 5")
    print(f"view_hanzi_single_candidate_not_toned 前5个: {cur.fetchall()}")

    conn.close()


if __name__ == "__main__":
    build_db()
    create_views()
