"""
初始化拼音映射：从 JSON 文件加载映射并写入 pinyin_hanzi.db 中的表 "拼音映射关系"。
特点：
- 自动寻找常用 JSON 文件名或接受命令行参数指定路径
- 确保目标表存在并创建唯一索引以避免重复累加
- 读取 JSON，生成双向映射（数字标调 -> 音元，音元 -> 数字标调）
- 一次性写入并返回写入的实际记录数（按数据来源计数）
"""
from pathlib import Path
from typing import Dict, List, Any
import sqlite3
import logging
import json
import sys
import os
from db_manager import DB_PATH

# 配置常量（可被命令行参数或环境变量覆盖）
DEFAULT_JSON_FILES = [
    "syllable_code.json",
    "yinjie_code.json",
    "yinjie_code_full.json",
    "enhanced_yinjie_mapping.json"
]
# 默认使用脚本所在目录的上级目录（项目根）中的数据库，避免因工作目录不同写入到不同文件
DB_FILE = Path(__file__).parent / "pinyin_hanzi.db"

logger = logging.getLogger(__name__)
logger.setLevel(logging.DEBUG)
if not logger.handlers:
    _handler = logging.StreamHandler()
    _handler.setFormatter(logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s'))
    logger.addHandler(_handler)


def find_json_path(candidate: str | None) -> Path:
    """确定要使用的 JSON 文件路径：优先使用参数/环境变量，否则在候选列表中查找第一个存在的文件。"""
    if candidate:
        p = Path(candidate)
        if p.is_file():
            return p
        alt = Path(__file__).parent / candidate
        if alt.is_file():
            return alt
        alt2 = Path.cwd() / candidate
        if alt2.is_file():
            return alt2
        raise FileNotFoundError(f"指定的 JSON 文件不存在: {candidate}")

    for name in DEFAULT_JSON_FILES:
        for base in (Path.cwd(), Path(__file__).parent):
            path = base / name
            if path.is_file():
                logger.debug(f"找到 JSON 文件: {path}")
                return path

    raise FileNotFoundError(
        "未找到 JSON 文件。请提供一个 JSON 文件，优先查找: "
        + ", ".join(DEFAULT_JSON_FILES)
        + "；或通过命令行传入文件路径或设置环境变量 SYLLABLE_JSON。"
    )


def validate_pinyin(p: Any) -> bool:
    """简单验证：非空字符串"""
    return isinstance(p, str) and bool(p.strip())


def ensure_mapping_table_exists(conn: sqlite3.Connection) -> None:
    cur = conn.cursor()
    cur.execute('DROP TABLE IF EXISTS "拼音映射关系"')
    conn.commit()
    cur.execute('''
        CREATE TABLE "拼音映射关系" (
            "映射编号" INTEGER PRIMARY KEY AUTOINCREMENT,
            "原拼音类型" TEXT NOT NULL,
            "原拼音" TEXT NOT NULL,
            "目标拼音类型" TEXT NOT NULL,
            "目标拼音" TEXT NOT NULL,
            "数据来源" TEXT,
            "版本号" TEXT,
            "备注" TEXT,
            "创建时间" TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE("原拼音类型", "原拼音", "目标拼音类型", "目标拼音", "数据来源")
        )
    ''')
    conn.commit()
    logger.info("已重建表 '拼音映射关系' 并设置唯一约束")


def _inspect_db(conn: sqlite3.Connection) -> None:
    """写入后做诊断：列出表、计数并采样展示，便于验证是哪份 DB 文件被写入。"""
    cur = conn.cursor()
    cur.execute("SELECT name FROM sqlite_master WHERE type='table'")
    tables = [r[0] for r in cur.fetchall()]
    logger.info(f"数据库表: {tables}")
    if "拼音映射关系" in tables:
        try:
            cur.execute('SELECT COUNT(*) FROM "拼音映射关系" WHERE "数据来源" = ?', ('音元输入法',))
            cnt = cur.fetchone()[0] or 0
            logger.info(f"'拼音映射关系'（来源=音元输入法）记录数: {cnt}")
            cur.execute('SELECT "原拼音","目标拼音" FROM "拼音映射关系" WHERE "数据来源" = ? LIMIT 10', ('音元输入法',))
            samples = cur.fetchall()
            logger.info(f"样例记录（最多10条）: {samples}")
        except sqlite3.Error as e:
            logger.error(f"读取表样例失败: {e}")


def 转换音节编码到数据库格式(conn: sqlite3.Connection, json_path: Path) -> int:
    """从 JSON 加载映射并写入数据库（生成双向映射）。返回写入的记录数（按数据来源计数）。"""
    logger.info(f"开始加载 JSON: {json_path}")
    with open(json_path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    if not isinstance(data, dict):
        raise ValueError("JSON 顶层必须为对象(dict)，格式为 {数字标调拼音: 音元编码}")

    total_items = len(data)
    logger.info(f"JSON 包含 {total_items} 条原始映射")

    records: List[Dict[str, str]] = []
    valid_count = 0
    skipped = 0

    for k, v in data.items():
        if not (validate_pinyin(k) and validate_pinyin(v)):
            skipped += 1
            continue
        src = k.strip()
        dst = v.strip()
        records.append({
            '原拼音类型': '数字标调',
            '原拼音': src,
            '目标拼音类型': '音元拼音',
            '目标拼音': dst,
            '数据来源': '音元输入法',
            '版本号': '0.1',
            '备注': '数字标调转音元'
        })
        records.append({
            '原拼音类型': '音元拼音',
            '原拼音': dst,
            '目标拼音类型': '数字标调',
            '目标拼音': src,
            '数据来源': '音元输入法',
            '版本号': '0.1',
            '备注': '音元转数字标调'
        })
        valid_count += 1

    logger.info(f"有效原始映射: {valid_count}，生成数据库记录: {len(records)}，跳过: {skipped}")

    if not records:
        raise ValueError("没有有效数据可导入")

    ensure_mapping_table_exists(conn)
    cur = conn.cursor()

    # 彻底清空表，防止历史重复导致唯一约束冲突
    try:
        cur.execute('DELETE FROM "拼音映射关系"')
        conn.commit()
        logger.info("已清空表 '拼音映射关系'")
    except sqlite3.OperationalError as e:
        cur.execute("SELECT name FROM sqlite_master WHERE type='table'")
        tables = [r[0] for r in cur.fetchall()]
        logger.error(f"DELETE 出错: {e}；当前表: {tables}")
        raise RuntimeError(f"删除旧数据失败: {e}")

    insert_sql = '''
        INSERT INTO "拼音映射关系"
        ("原拼音类型","原拼音","目标拼音类型","目标拼音","数据来源","版本号","备注")
        VALUES(:原拼音类型,:原拼音,:目标拼音类型,:目标拼音,:数据来源,:版本号,:备注)
    '''
    try:
        cur.executemany(insert_sql, records)
        conn.commit()
        cur.execute('SELECT COUNT(*) FROM "拼音映射关系" WHERE "数据来源" = ?', ('音元输入法',))
        exact_count = int(cur.fetchone()[0] or 0)
        logger.info(f"写入完成，数据库中该来源记录数: {exact_count}")
        _inspect_db(conn)
        return exact_count
    except sqlite3.Error as e:
        conn.rollback()
        logger.exception("写入失败，已回滚")
        raise RuntimeError(f"数据库写入失败: {e}")


def main(argv: List[str]) -> int:
    # argv[1] 可指定 JSON 文件，argv[2] 可指定数据库文件（可选）
    candidate = argv[1] if len(argv) > 1 else os.getenv("SYLLABLE_JSON")
    db_arg = argv[2] if len(argv) > 2 else os.getenv("SYLLABLE_DB")
    try:
        json_path = find_json_path(candidate)
    except FileNotFoundError as e:
        logger.error(str(e))
        return 2

    # 选择数据库路径：优先命令行/环境指定，否则使用脚本默认位置
    db_path = Path(db_arg) if db_arg else DB_FILE
    db_path = db_path.expanduser().resolve()
    logger.info(f"将使用数据库文件: {db_path}")

    db_path.parent.mkdir(parents=True, exist_ok=True)

    try:
        with sqlite3.connect(str(DB_PATH)) as conn:
            conn.row_factory = sqlite3.Row
            count = 转换音节编码到数据库格式(conn, json_path)
        logger.info(f"转换完成，共写入 {count} 条记录到数据库 {db_path}")
        print(f"转换完成，共写入 {count} 条记录到数据库 {db_path}")
        return 0
    except Exception as e:
        logger.error(f"执行出错: {e}", exc_info=True)
        print(f"意外错误: {e}")
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
