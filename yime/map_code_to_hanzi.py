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

        cursor.execute("DROP TABLE IF EXISTS 音元拼音同音表")

        # 修改后的表结构 - 使用音元拼音id作为外键
        cursor.execute('''
            CREATE TABLE 音元拼音同音表 (
                音元拼音id INTEGER REFERENCES 音元拼音(id),
                数字标调拼音 TEXT NOT NULL,
                同音字列 TEXT,
                last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (音元拼音id) REFERENCES 拼音映射(音元拼音id)
            )
        ''')

        # 修改索引
        cursor.execute('''
            CREATE INDEX 索引_音元拼音同音字列映射_音元拼音id
            ON 音元拼音同音表(音元拼音id)
        ''')
        cursor.execute('''
            CREATE INDEX 索引_音元拼音同音字列映射_数字标调拼音
            ON 音元拼音同音表(数字标调拼音)
        ''')

    # 修改后的DataImporter.import_code_to_hanzi_data方法
    @staticmethod
    def import_code_to_hanzi_data(conn: sqlite3.Connection) -> int:
        """从code_to_pinyin表导入数据到音元拼音同音字列映射表"""
        cursor = conn.cursor()
        try:
            conn.execute("BEGIN")
            cursor.execute("DELETE FROM 音元拼音同音表")
            conn.commit()

            conn.execute("BEGIN")
            cursor.execute('''
                INSERT INTO 音元拼音同音表 (音元拼音id, 数字标调拼音)
                SELECT 音元拼音id, 数字标调拼音
                FROM 拼音映射
                ORDER BY 音元拼音id
            ''')
            count = cursor.rowcount
            conn.commit()
            return count
        except Exception as e:
            conn.rollback()
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

                # 导入数据 - 修改为调用TableManager中的方法
                count = TableManager.import_code_to_hanzi_data(conn)

                # 优化数据库
                conn.execute("VACUUM")

                total_time = time.time() - start_time
                logger.info(
                    f"数据迁移完成! 映射记录: {count}, 耗时: {total_time:.2f}秒"
                )

        except Exception as e:
            logger.error(f"数据迁移失败: {e}")
            raise

    def query_by_code(self, 音元拼音id: int) -> dict:
        """通过音元拼音id查询对应的同音字列"""
        with sqlite3.connect(str(self.db_path)) as conn:
            cursor = conn.cursor()
            cursor.execute('''
                SELECT m.同音字列, p.数字标调拼音
                FROM 音元拼音同音表 m
                JOIN 拼音映射 p ON m.音元拼音id = p.音元拼音id
                WHERE m.音元拼音id = ?
            ''', (音元拼音id,))
            result = cursor.fetchone()
            return {
                '同音字列': result[0],
                '数字标调拼音': result[1]
            } if result else {}

    def query_by_hanzi(self, hanzi: str) -> list:
        """通过汉字反向查询所有对应的code"""
        with sqlite3.connect(str(self.db_path)) as conn:
            cursor = conn.cursor()

            cursor.execute('''
                SELECT 音元拼音
                FROM 音元拼音同音表
                WHERE 同音字列 LIKE ?
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
    WHERE type='table' AND name='音元拼音同音表'
    """)
    if cursor.fetchone() is None:
        conn.close()
        raise RuntimeError(f"目标表 音元拼音同音表 不存在于数据库 {db_path}")

    # 准备SQL语句
    select_sql = "SELECT 1 FROM 音元拼音同音表 WHERE 数字标调拼音 = ?"
    update_sql = """
        UPDATE 音元拼音同音表
        SET 同音字列 = ?, last_updated = CURRENT_TIMESTAMP
        WHERE 数字标调拼音 = ?
    """
    insert_sql = """
        INSERT INTO 音元拼音同音表 (音元拼音, 数字标调拼音, 同音字列)
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
        print(f"汉字: {code_result['同音字列']}")
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
