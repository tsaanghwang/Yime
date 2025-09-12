# yime/map_code_to_hanzi.py (重构版)
import sqlite3
import time
import logging
import sys
from pathlib import Path

# 确保能正确导入utils模块
utils_path = Path("c:/Users/Freeman Golden/OneDrive/Yime/utils")
if utils_path.exists():
    sys.path.insert(0, str(utils_path))


# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class DatabaseManager:
    """封装数据库连接和基本操作"""
    def __init__(self, db_path: str):
        self.db_path = Path(db_path)

    def __enter__(self):
        self.conn = sqlite3.connect(self.db_path)
        self.conn.execute("PRAGMA journal_mode=WAL")
        self.conn.isolation_level = None
        return self.conn

    def __exit__(self, exc_type, exc_val, exc_tb):
        if exc_type is None:
            self.conn.commit()
        self.conn.close()

class TableManager:
    @staticmethod
    def create_tables(conn: sqlite3.Connection) -> None:
        """创建所有必要的数据库表"""
        cursor = conn.cursor()

        # 先删除旧表(如果存在)
        cursor.execute("DROP TABLE IF EXISTS code_to_homophonic_hanzi")

        # 创建新表结构 - 移除code的主键约束
        cursor.execute('''
            CREATE TABLE code_to_homophonic_hanzi (
                code TEXT NOT NULL,  -- 不再作为主键
                numeric_pinyin TEXT NOT NULL,
                homophonic_hanzi TEXT,
                last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        ''')

        # 创建索引 - 修改为普通索引
        cursor.execute('''
            CREATE INDEX idx_code_to_homophonic_hanzi_code
            ON code_to_homophonic_hanzi(code)
        ''')
        cursor.execute('''
            CREATE INDEX idx_code_to_homophonic_hanzi_pinyin
            ON code_to_homophonic_hanzi(numeric_pinyin)
        ''')

        logger.info("数据库表结构创建/验证完成")

class DataImporter:
    @staticmethod
    def import_code_to_hanzi_data(conn: sqlite3.Connection) -> int:
        """从code_to_pinyin表导入数据到code_to_homophonic_hanzi表"""
        cursor = conn.cursor()

        try:
            # 开始显式事务
            conn.execute("BEGIN")

            # 先清空目标表并立即提交
            cursor.execute("DELETE FROM code_to_homophonic_hanzi")
            conn.commit()

            # 开始新事务执行插入
            conn.execute("BEGIN")
            cursor.execute('''
                INSERT INTO code_to_homophonic_hanzi (code, numeric_pinyin)
                SELECT code, pinyin
                FROM code_to_pinyin
                ORDER BY code  -- 保持有序导入
            ''')

            count = cursor.rowcount
            conn.commit()

            if count > 0:
                logger.info(f"成功导入 {count} 条code-拼音映射(保留一对多关系)")
            else:
                logger.error("数据导入失败: 没有导入任何记录")

            return count

        except Exception as e:
            conn.rollback()
            logger.error(f"数据导入失败: {str(e)}")
            raise

class DatabaseMigrator:
    """重构后的主迁移类"""
    def __init__(self, db_path: str = None):
        self.db_path = Path(db_path) if db_path else Path(__file__).parent / "pinyin_hanzi.db"

    def migrate(self) -> None:
        """执行完整的数据迁移流程"""
        start_time = time.time()

        try:
            with sqlite3.connect(str(self.db_path)) as conn:
                # 启用WAL模式提高并发性能
                conn.execute("PRAGMA journal_mode=WAL")
                conn.isolation_level = None  # 禁用自动事务

                # 创建表结构
                TableManager.create_tables(conn)

                # 导入数据
                count = DataImporter.import_code_to_hanzi_data(conn)

                # 优化数据库
                conn.execute("VACUUM")

                total_time = time.time() - start_time
                logger.info(
                    f"数据迁移完成! 映射记录: {count}, 耗时: {total_time:.2f}秒"
                )

        except Exception as e:
            logger.error(f"数据迁移失败: {e}")
            raise

    def query_by_code(self, code: str) -> dict:
        """通过code查询对应的homophonic_hanzi"""
        with sqlite3.connect(str(self.db_path)) as conn:
            cursor = conn.cursor()

            cursor.execute('''
                SELECT code, homophonic_hanzi
                FROM code_to_homophonic_hanzi
                WHERE code = ?
            ''', (code,))

            result = cursor.fetchone()
            return {
                'code': result[0],
                'homophonic_hanzi': result[1]
            } if result else {}

    def query_by_hanzi(self, hanzi: str) -> list:
        """通过汉字反向查询所有对应的code"""
        with sqlite3.connect(str(self.db_path)) as conn:
            cursor = conn.cursor()

            cursor.execute('''
                SELECT code
                FROM code_to_homophonic_hanzi
                WHERE homophonic_hanzi LIKE ?
            ''', (f"%{hanzi}%",))

            return [row[0] for row in cursor.fetchall()]

def migrate_pinyin_danzi_to_db(db_path: str | Path = None, json_path: str = 'pinyin/hanzi_pinyin/pinyin_danzi.json') -> int:
    """将pinyin_danzi.json的同音字数据迁移到数据库（模块级函数，可直接调用）

    db_path: 数据库文件路径；如果为 None，使用本模块同目录下的 pinyin_hanzi.db
    """
    import json
    from pathlib import Path

    # 统一处理 db_path 默认为模块目录下的 pinyin_hanzi.db
    if db_path is None:
        db_path = Path(__file__).parent / "pinyin_hanzi.db"
    db_path = Path(db_path)

    # 读取JSON文件
    json_path = Path(__file__).parent.parent / "pinyin/hanzi_pinyin/pinyin_danzi.json"
    with open(json_path, 'r', encoding='utf-8') as f:
        pinyin_danzi = json.load(f)

    # 连接数据库（使用模块顶部已导入的sqlite3）
    conn = sqlite3.connect(str(db_path))
    cursor = conn.cursor()

    # 确保目标表存在（防止在不同路径的 DB 上误操作）
    cursor.execute("""
    SELECT name FROM sqlite_master
    WHERE type='table' AND name='code_to_homophonic_hanzi'
    """)
    if cursor.fetchone() is None:
        conn.close()
        raise RuntimeError(f"目标表 code_to_homophonic_hanzi 不存在于数据库 {db_path}")

    # 准备SQL语句
    select_sql = "SELECT 1 FROM code_to_homophonic_hanzi WHERE numeric_pinyin = ?"
    update_sql = """
        UPDATE code_to_homophonic_hanzi
        SET homophonic_hanzi = ?, last_updated = CURRENT_TIMESTAMP
        WHERE numeric_pinyin = ?
    """
    insert_sql = """
        INSERT INTO code_to_homophonic_hanzi (code, numeric_pinyin, homophonic_hanzi)
        VALUES (?, ?, ?)
    """

    # 遍历JSON数据
    for pinyin, hanzi_list in pinyin_danzi.items():
        # 将汉字列表转换为字符串，用逗号分隔
        hanzi_str = ','.join(hanzi_list)

        # 检查数据库中是否已存在该拼音
        cursor.execute(select_sql, (pinyin,))
        exists = cursor.fetchone()

        if exists:
            # 更新现有记录
            cursor.execute(update_sql, (hanzi_str, pinyin))
        else:
            # 插入新记录，使用拼音作为code（因为code不是唯一且我们不知道对应的code）
            cursor.execute(insert_sql, (pinyin, pinyin, hanzi_str))

    # 提交事务并关闭连接
    conn.commit()
    conn.close()

    logger.info(f"成功迁移 {len(pinyin_danzi)} 条拼音数据到数据库 {db_path}")
    return len(pinyin_danzi)

if __name__ == "__main__":
    migrator = DatabaseMigrator()
    migrator.migrate()

    # 传递与 migrator 相同的数据库路径，确保在同一个 DB 文件上操作
    migrate_pinyin_danzi_to_db(db_path=migrator.db_path)

    # 测试通过code查询
    test_code = "1234"  # 替换为实际code
    code_result = migrator.query_by_code(test_code)
    print(f"\n通过code '{test_code}'查询结果:")
    if code_result:
        print(f"汉字: {code_result['homophonic_hanzi']}")
    else:
        print(f"未找到code '{test_code}'的信息")

    # 测试通过汉字反向查询
    test_hanzi = "你"  # 替换为实际汉字
    hanzi_result = migrator.query_by_hanzi(test_hanzi)
    print(f"\n通过汉字 '{test_hanzi}'反向查询结果:")
    if hanzi_result:
        print("对应的code列表:", hanzi_result)
    else:
        print(f"未找到汉字 '{test_hanzi}'对应的code")
