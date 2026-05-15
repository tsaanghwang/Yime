"""
初始化拼音映射：从库内基础映射面重建 pinyin_hanzi.db 中的表 "多式拼音映射关系"。
特点：
- 数据源固定为库内 `pinyin_yime_code`
- 每次刷新时整表重建，编号从 1 开始连续重排
- 生成双向映射（数字标调 -> 音元拼音，音元拼音 -> 数字标调）
- 写入完成后返回当前表中的实际记录数
"""
from typing import List, Tuple
import sqlite3
import logging
from pathlib import Path
from db_manager import DB_PATH
from yime.utils.pinyin_zhuyin import PinyinZhuyinConverter
import sys

CANONICAL_MAPPING_TABLE = "多式拼音映射关系"
SOURCE_TABLE = "pinyin_yime_code"
SOURCE_LABEL = "库内基础映射面"
NUMERIC_TYPE = "数字标调"
YIME_TYPE = "音元拼音"
ZHUYIN_TYPE = "注音符号"

SCRIPT_DIR = Path(__file__).parent
DEFAULT_DB = SCRIPT_DIR / "pinyin_hanzi.db"
LEGACY_WARNING = (
    "Initialize_pinyin_mapping.py 仅保留 legacy-compatible 用途；"
    "当前主线请改走 source_pinyin.db -> prototype tables -> refresh_runtime_yime_codes 链。"
)

logger = logging.getLogger(__name__)
logger.setLevel(logging.DEBUG)
if not logger.handlers:
    _handler = logging.StreamHandler()
    _handler.setFormatter(logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s'))
    logger.addHandler(_handler)

def ensure_mapping_table_exists(conn: sqlite3.Connection) -> None:
    """创建规范资料层表。"""
    cur = conn.cursor()
    cur.execute('''
        CREATE TABLE IF NOT EXISTS "多式拼音映射关系" (
            "映射编号" INTEGER PRIMARY KEY AUTOINCREMENT,
            "原拼音类型" TEXT NOT NULL,
            "原拼音" TEXT NOT NULL,
            "目标拼音类型" TEXT NOT NULL,
            "目标拼音" TEXT NOT NULL,
            "关系类型" TEXT NOT NULL DEFAULT '对应',
            "时期标签" TEXT,
            "数据来源" TEXT,
            "版本号" TEXT,
            "备注" TEXT,
            "创建时间" TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE("原拼音类型", "原拼音", "目标拼音类型", "目标拼音", "关系类型", "数据来源")
        )
    ''')
    conn.commit()
    logger.info("确保表 '多式拼音映射关系' 存在（若不存在已创建）")


def _inspect_db(conn: sqlite3.Connection) -> None:
    """写入后做诊断：列出表、计数并采样展示，便于验证是哪份 DB 文件被写入。"""
    cur = conn.cursor()
    cur.execute("SELECT name FROM sqlite_master WHERE type='table'")
    tables = [r[0] for r in cur.fetchall()]
    logger.info(f"数据库表: {tables}")
    if CANONICAL_MAPPING_TABLE in tables:
        try:
            cur.execute(f'SELECT COUNT(*) FROM "{CANONICAL_MAPPING_TABLE}" WHERE "数据来源" = ?', (SOURCE_LABEL,))
            cnt = cur.fetchone()[0] or 0
            logger.info(f"'{CANONICAL_MAPPING_TABLE}'（来源={SOURCE_LABEL}）记录数: {cnt}")
            cur.execute(f'SELECT "映射编号","原拼音","目标拼音" FROM "{CANONICAL_MAPPING_TABLE}" WHERE "数据来源" = ? ORDER BY "映射编号" LIMIT 10', (SOURCE_LABEL,))
            samples = cur.fetchall()
            logger.info(f"样例记录（最多10条）: {samples}")
        except sqlite3.Error as e:
            logger.error(f"读取表样例失败: {e}")


def _load_source_rows(conn: sqlite3.Connection) -> list[tuple[str, str, str]]:
    cur = conn.cursor()
    source_exists = cur.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
        (SOURCE_TABLE,),
    ).fetchone()
    if source_exists is None:
        raise RuntimeError(f"未找到库内基础映射面: {SOURCE_TABLE}")

    rows = cur.execute(
        f'''
        SELECT pinyin_tone, yime_code, MIN(code_source) AS code_source
        FROM "{SOURCE_TABLE}"
        WHERE TRIM(COALESCE(pinyin_tone, '')) <> ''
          AND TRIM(COALESCE(yime_code, '')) <> ''
        GROUP BY pinyin_tone, yime_code
        ORDER BY pinyin_tone, yime_code
        '''
    ).fetchall()
    return [(str(row[0]), str(row[1]), str(row[2] or "")) for row in rows]


def _build_records_from_db_rows(source_rows: list[tuple[str, str, str]]) -> list[tuple[str, str, str, str, str, str, str, str, str]]:
    records: list[tuple[str, str, str, str, str, str, str, str, str]] = []
    for pinyin_tone, yime_code, code_source in source_rows:
        version = code_source or SOURCE_TABLE
        zhuyin = PinyinZhuyinConverter.convert_pinyin_to_zhuyin(pinyin_tone)
        records.append((
            NUMERIC_TYPE,
            pinyin_tone,
            YIME_TYPE,
            yime_code,
            "对应",
            "",
            SOURCE_LABEL,
            version,
            "数字标调转音元",
        ))
        records.append((
            YIME_TYPE,
            yime_code,
            NUMERIC_TYPE,
            pinyin_tone,
            "对应",
            "",
            SOURCE_LABEL,
            version,
            "音元转数字标调",
        ))
        records.append((
            NUMERIC_TYPE,
            pinyin_tone,
            ZHUYIN_TYPE,
            zhuyin,
            "对应",
            "",
            SOURCE_LABEL,
            version,
            "数字标调转注音",
        ))
        records.append((
            ZHUYIN_TYPE,
            zhuyin,
            NUMERIC_TYPE,
            pinyin_tone,
            "对应",
            "",
            SOURCE_LABEL,
            version,
            "注音转数字标调",
        ))
    return records


def rebuild_mappings_from_db(conn: sqlite3.Connection) -> int:
    """从库内 `pinyin_yime_code` 全量重建 `多式拼音映射关系`。"""
    ensure_mapping_table_exists(conn)
    source_rows = _load_source_rows(conn)
    records = _build_records_from_db_rows(source_rows)
    logger.info(f"从库内基础映射面 {SOURCE_TABLE} 读取 {len(source_rows)} 组数字标调/音元关系")

    cur = conn.cursor()
    cur.execute(f'DELETE FROM "{CANONICAL_MAPPING_TABLE}"')
    cur.execute("DELETE FROM sqlite_sequence WHERE name=?", (CANONICAL_MAPPING_TABLE,))
    cur.executemany(
        f'''
        INSERT INTO "{CANONICAL_MAPPING_TABLE}"
        ("原拼音类型","原拼音","目标拼音类型","目标拼音","关系类型","时期标签","数据来源","版本号","备注")
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        records,
    )
    conn.commit()

    exact_count = int(
        cur.execute(f'SELECT COUNT(*) FROM "{CANONICAL_MAPPING_TABLE}"').fetchone()[0] or 0
    )
    logger.info(f"重建完成，{CANONICAL_MAPPING_TABLE} 当前记录数: {exact_count}")
    _inspect_db(conn)
    return exact_count


def resolve_db_path(argv=None) -> Path:
    """兼容 legacy argv 形状，只解析数据库路径。"""
    argv = list(argv or [])
    if argv and str(argv[0]).lower().endswith(".py"):
        argv = argv[1:]

    db_arg = next((value for value in reversed(argv) if str(value).lower().endswith(".db")), None)
    return Path(db_arg).resolve() if db_arg else DEFAULT_DB.resolve()


def main(argv=None):
    argv = argv if argv is not None else sys.argv[1:]
    logger.warning(LEGACY_WARNING)
    db_path = resolve_db_path(argv)
    logger.info("使用 DB:   %s", db_path)

    try:
        with sqlite3.connect(str(db_path)) as conn:
            conn.row_factory = sqlite3.Row
            count = rebuild_mappings_from_db(conn)
        logger.info(f"重建完成，共写入 {count} 条记录到数据库 {db_path}")
        print(f"重建完成，共写入 {count} 条记录到数据库 {db_path}")
        return 0
    except Exception as e:
        logger.error(f"执行出错: {e}", exc_info=True)
        print(f"意外错误: {e}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
