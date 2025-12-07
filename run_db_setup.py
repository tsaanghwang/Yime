from pathlib import Path
import sqlite3
import logging
import sys

PROJECT = Path(__file__).parent
DB = PROJECT / "pinyin_hanzi.db"

logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")
logger = logging.getLogger(__name__)

def main():
    # 显示将要操作的数据库路径，避免混淆“根目录”与模块目录
    logger.info("使用数据库文件: %s", DB.resolve())

    # 只负责建表/索引/简单校验，不 import 任何实验性模块
    try:
        import yime.db_manager as dbm
    except Exception as e:
        logger.error("无法导入 db_manager: %s", e)
        sys.exit(1)

    # 首选：如果 db_manager 提供 run_schema_migrations，就调用它
    try:
        if hasattr(dbm, "run_schema_migrations"):
            logger.info("调用 db_manager.run_schema_migrations()")
            dbm.run_schema_migrations(DB)
        else:
            # 回退：尝试使用表管理器的接口创建表（兼容旧接口）
            logger.info("run_schema_migrations 未发现，尝试使用 表管理器.创建表 回退路径")
            conn = sqlite3.connect(str(DB))
            try:
                conn.execute("PRAGMA foreign_keys = ON;")
                if hasattr(dbm, "表管理器") and hasattr(dbm.表管理器, "创建表"):
                    dbm.表管理器.创建表(conn)
                else:
                    # 最后手段：如果 db_manager 中有 名为 '创建表' 的函数，尝试调用
                    if hasattr(dbm, "创建表"):
                        dbm.创建表(conn)
                    else:
                        logger.error("无法在 db_manager 中找到可用的迁移/创建表接口（run_schema_migrations / 表管理器.创建表 / 创建表）。")
                        sys.exit(2)
                conn.commit()
            finally:
                conn.close()
        logger.info("schema/索引 已确保")
    except Exception as e:
        logger.exception("执行 schema 创建/迁移 失败: %s", e)
        sys.exit(2)

    # 简单完整性检查
    try:
        con = sqlite3.connect(str(DB))
        ok = con.execute("PRAGMA integrity_check;").fetchone()
        con.close()
        logger.info("PRAGMA integrity_check -> %s", ok[0] if ok else None)
    except Exception as e:
        logger.exception("完整性检查失败: %s", e)
        sys.exit(3)

    logger.info("数据库建立/检查完成。下一步：用你的 JSON 生成器输出文件并用 Initialize_pinyin_mapping/import 脚本导入。")

if __name__ == "__main__":
    main()
