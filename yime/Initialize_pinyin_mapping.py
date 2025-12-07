"""
初始化拼音映射：从 JSON 文件加载映射并写入 pinyin_hanzi.db 中的表 "拼音映射关系"。
特点：
- 自动寻找常用 JSON 文件名或接受命令行参数指定路径
- 确保目标表存在并创建唯一索引以避免重复累加
- 读取 JSON，生成双向映射（数字标调 -> 音元，音元 -> 数字标调）
- 一次性写入并返回写入的实际记录数（按数据来源计数）
"""
from typing import Dict, List, Any, Tuple, Optional
import sqlite3
import logging
import json
import os
from pathlib import Path
from db_manager import DB_PATH
import sys

SCRIPT_DIR = Path(__file__).parent
DEFAULT_JSON = SCRIPT_DIR / "syllable_code.json"
DEFAULT_DB = SCRIPT_DIR / "pinyin_hanzi.db"

# 明确的拼音类型集合（需求 1）
PINYIN_TYPE = ['音元拼音', '数字标调', '标准拼音', '注音符号', '国际音标']

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

    for name in ("syllable_code.json",):
        for base in (Path.cwd(), Path(__file__).parent):
            path = base / name
            if path.is_file():
                logger.debug(f"找到 JSON 文件: {path}")
                return path

    raise FileNotFoundError("未找到 JSON 文件。请提供一个 JSON 文件。")


def validate_pinyin(p: Any) -> bool:
    """简单验证：非空字符串"""
    return isinstance(p, str) and bool(p.strip())


def ensure_mapping_table_exists(conn: sqlite3.Connection) -> None:
    """创建表（若不存在），不自动 DROP，以免丢失其它来源数据。"""
    cur = conn.cursor()
    cur.execute('''
        CREATE TABLE IF NOT EXISTS "拼音映射关系" (
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
    logger.info("确保表 '拼音映射关系' 存在（若不存在已创建）")


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


def build_records_from_json_obj(data: Any) -> List[Dict[str, Any]]:
    """
    支持三种 JSON 结构并对“类型->类型”的误用做检测：
    1) 旧的简单 dict: {原拼音: 目标拼音}  -> 假定 原=数字标调, 目标=音元拼音（并生成反向）
    2) 嵌套 dict: { "原拼音类型": { "原拼音": "目标拼音", ... }, ... } （推荐）
    3) 记录列表: [{原拼音类型, 原拼音, 目标拼音类型, 目标拼音, ...}, ...]
    如果检测到 top-level dict 的键/值看起来像是“类型名而非拼音串”，会抛出 ValueError 并提示正确格式。
    """
    records: List[Dict[str, Any]] = []

    # 安全检查：若 data 是 dict 且键或值看起来全是类型名，则视为格式错误（避免把类型名误当作拼音条目）
    if isinstance(data, dict):
        all_keys_are_types = all(isinstance(k, str) and k.strip() in PINYIN_TYPE for k in data.keys())
        all_values_are_types = all(isinstance(v, str) and v.strip() in PINYIN_TYPE for v in data.values())
        if all_keys_are_types and all_values_are_types:
            raise ValueError(
                "JSON 内容像是“类型->类型”的映射（例如 {\"数字标调\":\"标准拼音\"}）。\n"
                "请改用嵌套映射格式：{ \"数字标调\": { \"a1\": \"abcc\", ... }, ... } "
                "或使用记录列表：[{'原拼音类型':'数字标调','原拼音':'a1','目标拼音类型':'音元拼音','目标拼音':'abcc'}, ...]\n"
                "若你意图只是指定要导入哪些 原拼音类型，请使用脚本第三个参数或环境变量 INCLUDE_TYPES。"
            )

    # 1) 旧式简单 dict：顶层为 {原: 目标}（且 values 不是 dict）
    if isinstance(data, dict) and all(not isinstance(v, dict) for v in data.values()):
        for k, v in data.items():
            if not (validate_pinyin(k) and validate_pinyin(v)):
                continue
            src = k.strip(); dst = v.strip()
            records.append({
                '原拼音类型': '数字标调', '原拼音': src,
                '目标拼音类型': '音元拼音', '目标拼音': dst,
                '数据来源': '音元输入法', '版本号': '0.1', '备注': ''
            })
            records.append({
                '原拼音类型': '音元拼音', '原拼音': dst,
                '目标拼音类型': '数字标调', '目标拼音': src,
                '数据来源': '音元输入法', '版本号': '0.1', '备注': ''
            })
        return records

    # 2) 嵌套 dict: { 原类型: { 原拼音: 目标拼音, ... }, ... }
    if isinstance(data, dict) and any(isinstance(v, dict) for v in data.values()):
        for orig_type, mapping in data.items():
            if not validate_pinyin(orig_type):
                continue
            if not isinstance(mapping, dict):
                continue
            for orig, tgt in mapping.items():
                if not (validate_pinyin(orig) and validate_pinyin(tgt)):
                    continue
                records.append({
                    '原拼音类型': str(orig_type).strip(),
                    '原拼音': str(orig).strip(),
                    '目标拼音类型': '音元拼音',
                    '目标拼音': str(tgt).strip(),
                    '数据来源': '音元输入法',
                    '版本号': '',
                    '备注': ''
                })
                records.append({
                    '原拼音类型': '音元拼音',
                    '原拼音': str(tgt).strip(),
                    '目标拼音类型': str(orig_type).strip(),
                    '目标拼音': str(orig).strip(),
                    '数据来源': '音元输入法',
                    '版本号': '',
                    '备注': ''
                })
        return records

    # 3) 列表记录格式（优先使用显式类型）
    if isinstance(data, list):
        for item in data:
            if not isinstance(item, dict):
                continue
            orig_t = item.get('原拼音类型') or item.get('原_type') or item.get('from_type')
            orig = item.get('原拼音') or item.get('原') or item.get('from')
            tgt_t = item.get('目标拼音类型') or item.get('目标_type') or item.get('to_type')
            tgt = item.get('目标拼音') or item.get('目标') or item.get('to')
            if not (validate_pinyin(orig_t) and validate_pinyin(tgt_t) and validate_pinyin(orig) and validate_pinyin(tgt)):
                continue
            records.append({
                '原拼音類型': orig_t.strip(),
                '原拼音': orig.strip(),
                '目标拼音类型': tgt_t.strip(),
                '目标拼音': tgt.strip(),
                '数据来源': item.get('数据来源', '音元输入法'),
                '版本号': item.get('版本号', ''),
                '备注': item.get('备注', '')
            })
        return records

    # 其它格式不支持
    logger.warning("Unsupported JSON shape for build_records_from_json_obj: %s", type(data))
    return records


def filter_records_by_types(records: List[Dict[str, Any]], include_types: Optional[List[str]] = None) -> List[Dict[str, Any]]:
    """
    按规则筛选要写入的方向（满足需求 2），并可按 include_types 限制哪些 原拼音类型 会被考虑。
    include_types=None 表示不限制；否则只有 原拼音类型 在 include_types 中的记录会被考虑。
    """
    out: List[Dict[str, Any]] = []
    for rec in records:
        orig_t = rec.get("原拼音类型")
        tgt_t = rec.get("目标拼音类型")
        if include_types and orig_t not in include_types:
            continue
        if orig_t in PINYIN_TYPE and orig_t != '音元拼音' and tgt_t == '音元拼音':
            out.append(rec); continue
        if orig_t == '音元拼音' and tgt_t in PINYIN_TYPE and tgt_t != '音元拼音':
            out.append(rec); continue
    return out


def import_mappings_from_json(conn: sqlite3.Connection, json_path: Path, include_types: Optional[List[str]] = None) -> int:
    """主导入流程：加载 json -> 生成记录 -> 按类型规则筛选 -> 插入数据库。返回插入条数。"""
    logger.info(f"开始加载 JSON: {json_path}")
    with open(json_path, 'r', encoding='utf-8-sig') as f:
        data = json.load(f)

    all_records = build_records_from_json_obj(data)
    logger.debug(f"生成中间记录数（含双向）: {len(all_records)}")
    selected = filter_records_by_types(all_records, include_types=include_types)
    logger.info(f"按 PINYIN_TYPE 规则与 include_types 筛选后待写入记录数: {len(selected)}")
    if not selected:
        logger.warning("没有符合规则的记录将被写入。")
        return 0

    ensure_mapping_table_exists(conn)
    cur = conn.cursor()
    insert_sql = '''
        INSERT OR IGNORE INTO "拼音映射关系"
        ("原拼音类型","原拼音","目标拼音类型","目标拼音","数据来源","版本号","备注")
        VALUES(:原拼音类型,:原拼音,:目标拼音类型,:目标拼音,:数据来源,:版本号,:备注)
    '''
    cur.executemany(insert_sql, selected)
    conn.commit()
    cur.execute('SELECT COUNT(*) FROM "拼音映射关系" WHERE "数据来源" = ?', ('音元输入法',))
    exact_count = int(cur.fetchone()[0] or 0)
    logger.info(f"写入完成，数据库中该来源记录数: {exact_count}")
    _inspect_db(conn)
    return exact_count


def get_json_template() -> dict:
    """返回供编辑的 JSON 字典结构说明与示例（需求 3）。"""
    return {
        "说明": "支持三种 JSON 结构：1) 简单 dict {原:目标}（兼容旧版）；2) 嵌套 dict {原拼音类型: {原:目标}}（推荐）；3) 记录列表 [{原拼音类型, 原拼音, 目标拼音类型, 目标拼音}, ...]",
        "PINYIN_TYPE": PINYIN_TYPE,
        "示例_嵌套": {
            "数字标调": {"a1": "abcc", "a2": "abbb"},
            "标准拼音": {"shang": "abcc_alt"}
        },
        "示例_记录列表": [
            {"原拼音类型":"数字标调","原拼音":"a1","目标拼音类型":"音元拼音","目标拼音":"abcc"}
        ],
        "备注": "可通过命令行第三个参数或环境变量 INCLUDE_TYPES 指定只导入哪些 原拼音类型（逗号分隔），例如: 数字标调,标准拼音"
    }


def resolve_paths(argv=None) -> Tuple[Path, Path, Optional[List[str]]]:
    """返回 (json_path: Path, db_path: Path) —— 支持 argv、环境变量或默认值"""
    argv = list(argv or [])
    json_arg = argv[0] if len(argv) > 0 else None
    db_arg = argv[1] if len(argv) > 1 else None
    include_arg = argv[2] if len(argv) > 2 else None
    json_path = Path(json_arg) if json_arg else Path(os.environ.get("SYLLABLE_JSON") or DEFAULT_JSON)
    db_path = Path(db_arg) if db_arg else Path(os.environ.get("PINYIN_DB") or DEFAULT_DB)
    include_types = None
    if include_arg:
        include_types = [s.strip() for s in include_arg.split(",") if s.strip()]
    else:
        env_includes = os.environ.get("INCLUDE_TYPES")
        if env_includes:
            include_types = [s.strip() for s in env_includes.split(",") if s.strip()]
    return json_path.resolve(), db_path.resolve(), include_types


def main(argv=None):
    # argv 可为 sys.argv[1:] 或传入的参数列表
    argv = argv if argv is not None else sys.argv[1:]
    json_path, db_path, include_types = resolve_paths(argv)
    logger.info("使用 JSON: %s", json_path)
    logger.info("使用 DB:   %s", db_path)
    if include_types:
        logger.info("只导入 原拼音类型: %s", include_types)

    try:
        with sqlite3.connect(str(DB_PATH)) as conn:
            conn.row_factory = sqlite3.Row
            count = import_mappings_from_json(conn, json_path, include_types=include_types)
        logger.info(f"转换完成，共写入 {count} 条记录到数据库 {db_path}")
        print(f"转换完成，共写入 {count} 条记录到数据库 {db_path}")
        return 0
    except Exception as e:
        logger.error(f"执行出错: {e}", exc_info=True)
        print(f"意外错误: {e}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
