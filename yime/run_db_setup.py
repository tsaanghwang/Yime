from pathlib import Path
import sqlite3
import logging
import sys

PROJECT = Path(__file__).parent
# 默认使用与本脚本同目录下的数据库文件
DB = PROJECT / "pinyin_hanzi.db"

logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")
logger = logging.getLogger(__name__)

def main():
    # 允许通过命令行覆盖 DB 路径： python run_db_setup.py C:\path\to\db
    if len(sys.argv) > 1:
        db_path = Path(sys.argv[1]).resolve()
    else:
        db_path = DB.resolve()
    logger.info("使用数据库文件: %s", db_path)

    # 简单建表/完整性检查示例（假设 yime.db_manager 提供可用接口）
    # 尝试以包名导入，若脚本直接在模块目录运行则回退为本地导入
    try:
        import yime.db_manager as dbm
    except Exception as e:
        logger.warning("import yime.db_manager 失败，尝试本地导入：%s", e)
        try:
            import db_manager as dbm
        except Exception as e2:
            logger.error("无法导入 db_manager: %s", e2)
            sys.exit(1)

    try:
        if hasattr(dbm, "run_schema_migrations"):
            dbm.run_schema_migrations(db_path)
        else:
            # 回退接口：创建连接并尽量调用兼容函数
            conn = sqlite3.connect(str(db_path))
            try:
                conn.execute("PRAGMA foreign_keys = ON;")
                if hasattr(dbm, "表管理器") and hasattr(dbm.表管理器, "创建表"):
                    dbm.表管理器.创建表(conn)
                elif hasattr(dbm, "创建表"):
                    dbm.创建表(conn)
                else:
                    logger.error("未找到可用的创建表接口，跳过")
                conn.commit()
            finally:
                conn.close()
        logger.info("schema/索引 已确保")
    except Exception as e:
        logger.exception("执行 schema 创建/迁移 失败: %s", e)
        sys.exit(2)

    try:
        con = sqlite3.connect(str(db_path))
        ok = con.execute("PRAGMA integrity_check;").fetchone()
        con.close()
        logger.info("PRAGMA integrity_check -> %s", ok[0] if ok else None)
    except Exception as e:
        logger.exception("完整性检查失败: %s", e)
        sys.exit(3)

    logger.info("数据库建立/检查完成。下一步：用你的 JSON 生成器输出文件并用 Initialize_pinyin_mapping/import 脚本导入。")

if __name__ == "__main__":
    main()
