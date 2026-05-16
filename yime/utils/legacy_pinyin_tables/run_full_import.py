"""Legacy-compatible one-click import runner.

This script is kept only for older maintenance flows that still rely on
legacy Chinese tables and migration helpers.

It is NOT the current mainline rebuild entrypoint.

Current mainline rebuild chain:
1. internal_data/pinyin_source_db/build_source_pinyin_db.py
2. internal_data/pinyin_source_db/validate_source_pinyin_db.py
3. yime/import_danzi_into_prototype_tables.py
4. yime/import_duozi_into_prototype_tables.py
5. yime/refresh_runtime_yime_codes.py --apply

If you only need YAML to JSON export, use:
internal_data/pinyin_source_db/export_yaml_lexicon_json.py
"""

from pathlib import Path
import shutil
import sqlite3
import sys
import logging
from datetime import datetime

# minimal one-click pipeline runner for yime import steps
PROJECT_DIR = Path(__file__).resolve().parents[2]
DB_DEFAULT = PROJECT_DIR / "pinyin_hanzi.db"
BACKUP_DIR = PROJECT_DIR / "backup"
LOG_FILE = PROJECT_DIR / "run_full_import.log"

logger = logging.getLogger(__name__)


def configure_logging() -> None:
    if logger.handlers:
        return
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s - %(levelname)s - %(message)s",
        handlers=[
            logging.StreamHandler(),
            logging.FileHandler(str(LOG_FILE), encoding="utf-8"),
        ],
    )

LEGACY_WARNING = (
    "run_full_import.py 已降级为 legacy-compatible 入口；"
    "当前主线请改走 source_pinyin.db -> prototype tables -> refresh_runtime_yime_codes 链。"
)

def backup_db(db_path: Path) -> Path:
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    dst = BACKUP_DIR / f"{db_path.stem}.{datetime.now():%Y%m%d_%H%M%S}.db.bak"
    shutil.copy2(db_path, dst)
    logger.info(f"备份完成: {dst} (大小 {dst.stat().st_size} bytes)")
    # integrity check
    con = sqlite3.connect(str(dst))
    try:
        row = con.execute("PRAGMA integrity_check;").fetchone()
        logger.info(f"PRAGMA integrity_check -> {row[0] if row else None}")
        if row is None or row[0] != "ok":
            raise RuntimeError("备份文件 integrity_check 未通过")
    finally:
        con.close()
    return dst

def run():
    configure_logging()
    logger.warning(LEGACY_WARNING)

    # CLI args: [json_path] [db_path] [--apply-mapping]
    json_path = Path(sys.argv[1]) if len(sys.argv) > 1 and not sys.argv[1].startswith("--") else None
    db_path = Path(sys.argv[2]) if len(sys.argv) > 2 and not sys.argv[2].startswith("--") else DB_DEFAULT
    apply_mapping = "--apply" in sys.argv

    db_path = db_path.resolve()
    if not db_path.exists():
        logger.error(f"数据库文件不存在: {db_path}")
        sys.exit(2)

    # backup
    try:
        backup_db(db_path)
    except Exception as e:
        logger.error(f"备份或完整性检查失败: {e}")
        sys.exit(3)

    # run schema migrations
    try:
        import yime.legacy.pending_removal.db_manager as db_manager
        logger.info("确保 DB schema/索引...")
        if hasattr(db_manager, "run_schema_migrations"):
            db_manager.run_schema_migrations(db_path)
        else:
            logger.warning("db_manager.run_schema_migrations 未找到，跳过 schema 检查")
    except Exception as e:
        logger.exception("执行 schema 迁移失败")
        sys.exit(4)

    # Initialize mappings
    try:
        import yime.utils.legacy_pinyin_tables.Initialize_pinyin_mapping as init_map
        logger.info("初始化拼音映射 (Initialize_pinyin_mapping)...")
        # init_map.main expects argv-like list based on earlier code
        argv = ["Initialize_pinyin_mapping.py"]
        if json_path:
            argv.append(str(json_path))
        else:
            argv.append(str(PROJECT_DIR / "code_pinyin.json"))
        argv.append(str(db_path))
        if hasattr(init_map, "main"):
            init_map.main(argv)
        else:
            logger.warning("Initialize_pinyin_mapping.main 未找到，跳过")
    except Exception as e:
        logger.exception("初始化拼音映射失败")
        sys.exit(5)

    # import numeric pinyin (数字标调)
    try:
        import yime.utils.legacy_pinyin_tables.split_numeric_pinyin as imp_num
        logger.info("导入数字标调拼音 (split_numeric_pinyin)...")
        if hasattr(imp_num, "main"):
            imp_num.main()
        else:
            logger.warning("split_numeric_pinyin.main 未找到，跳过")
    except Exception as e:
        logger.exception("导入数字标调拼音失败")
        sys.exit(6)

    # import audio / yime pinyin (音元拼音)
    try:
        import yime.utils.legacy_pinyin_tables.rebuild_yinyuan_structure_table as importer_mod
        logger.info("导入音元拼音 (rebuild_yinyuan_structure_table)...")
        if hasattr(importer_mod, "main"):
            importer_mod.main()
        else:
            if hasattr(importer_mod, "PinyinImporter"):
                imp = importer_mod.PinyinImporter(db_path)
                mapping_rows = imp.load_mapping_rows_from_db()
                imp.import_pinyin(mapping_rows)
            else:
                logger.warning("rebuild_yinyuan_structure_table 没有 main 或 PinyinImporter，跳过")
    except Exception as e:
        logger.exception("导入音元拼音失败")
        sys.exit(7)

    # optional: run consolidation reports (dry-run) and optionally apply
    try:
        import yime.utils.legacy_pinyin_tables.consolidate_mappings as cons
        logger.info("运行一致性检测 (consolidate_mappings.py)...")
        if hasattr(cons, "main"):
            if apply_mapping:
                cons.main(argv=["consolidate_mappings.py", "--apply"])
            else:
                cons.main(argv=["consolidate_mappings.py"])
        else:
            # fallback call without argv param
            cons.main()
    except ModuleNotFoundError:
        logger.info("consolidate_mappings.py 未找到，跳过一致性检测")
    except Exception:
        logger.exception("运行一致性检测失败")

    logger.warning("legacy-compatible 导入流程完成。请优先迁移到当前主线 rebuild 入口。")

if __name__ == "__main__":
    try:
        run()
    except NameError as e:
        logger.exception("NameError 在导入流程中发生：%s", e)
        print("NameError: 发现未定义名称，已记录到日志。请搜索项目中 'code_tuple' 并修复引用位置。")
        sys.exit(1)
    except Exception as e:
        logger.exception("运行一键导入流程时发生未处理异常：%s", e)
        sys.exit(2)
