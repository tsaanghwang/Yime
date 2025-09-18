"""
音元拼音导入工具 - 完整版
功能：将音元拼音数据导入到"音元拼音"表，并为必填字段提供默认值
"""

import json
import logging
from pathlib import Path
import sqlite3
from typing import Dict
from contextlib import contextmanager

from syllable_structure import SyllableStructure
from syllable_decoder import SyllableDecoder

# 指定固定数据库路径（相对或绝对，两个选其一即可）
DB_PATH = Path(__file__).parent / "pinyin_hanzi.db"
# 如果你更希望使用绝对路径，请取消下面一行注释并注释上面一行
# DB_PATH = Path(r"C:\Users\Freeman Golden\OneDrive\Yime\yime\pinyin_hanzi.db")

class PinyinImporter:
    """音元拼音导入器（完整字段导入）"""

    def __init__(self, db_path: str | Path = "pinyin_hanzi.db"):
        self.db_path = Path(db_path).absolute()
        self._setup_logging()

    def _setup_logging(self):
        """配置日志记录"""
        logging.basicConfig(
            level=logging.INFO,
            format="%(asctime)s - %(levelname)s - %(message)s",
            handlers=[
                logging.StreamHandler(),
                logging.FileHandler("pinyin_import.log", encoding="utf-8")
            ]
        )
        self.logger = logging.getLogger(__name__)

    @contextmanager
    def _get_connection(self) -> sqlite3.Connection:
        """获取数据库连接（上下文管理器）"""
        conn = sqlite3.connect(str(self.db_path))
        conn.row_factory = sqlite3.Row
        try:
            yield conn
        finally:
            conn.close()

    def check_table_exists(self) -> bool:
        """检查音元拼音表是否存在"""
        with self._get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(
                "SELECT name FROM sqlite_master "
                "WHERE type='table' AND name='音元拼音'"
            )
            return cursor.fetchone() is not None

    def check_index_exists(self) -> bool:
        """增强版索引检查，同时验证索引是否有效"""
        with self._get_connection() as conn:
            cursor = conn.cursor()
            # 检查索引是否存在
            cursor.execute(
                "SELECT name FROM sqlite_master "
                "WHERE type='index' AND name='sqlite_autoindex_音元拼音_1'"
            )
            if cursor.fetchone() is None:
                return False

            # 检查索引是否有效（验证索引列）
            cursor.execute("PRAGMA index_info('sqlite_autoindex_音元拼音_1')")
            index_info = cursor.fetchall()
            return len(index_info) > 0 and index_info[0][2] == "全拼"

    def clear_table(self) -> int:
        """删除音元拼音表中的所有记录（增强版）"""
        if not self.check_table_exists():
            self.logger.warning("音元拼音表不存在")
            return 0

        with self._get_connection() as conn:
            cursor = conn.cursor()
            try:
                # 先禁用外键约束
                cursor.execute("PRAGMA foreign_keys=OFF")

                # 使用更彻底的表清空方式
                cursor.execute('DELETE FROM "音元拼音"')

                # 先提交DELETE操作
                conn.commit()

                # 在事务外执行VACUUM
                cursor.execute("VACUUM")

                # 开始新的事务
                cursor.execute("BEGIN")

                # 重置自增计数器（如果有）
                cursor.execute("DELETE FROM sqlite_sequence WHERE name='音元拼音'")

                conn.commit()
                return 0  # 不再返回删除计数
            except Exception as e:
                conn.rollback()
                self.logger.error(f"清空表失败: {e}")
                raise
            finally:
                # 恢复外键约束
                cursor.execute("PRAGMA foreign_keys=ON")

    def load_json_data(self, json_path: str | Path) -> Dict[str, str]:
        """加载JSON格式的音元拼音数据"""
        json_path = Path(json_path).absolute()
        if not json_path.exists():
            raise FileNotFoundError(f"JSON文件不存在: {json_path}")

        with open(json_path, "r", encoding="utf-8") as f:
            data = json.load(f)

        self.logger.info(f"已从 {json_path} 加载 {len(data)} 条音元拼音数据")
        return data

    def _generate_default_values(self, input_str: str) -> dict:
        """生成默认值，支持直接处理PUA编码字符"""
        decoder = SyllableDecoder()

        try:
            # 判断输入是否为PUA字符(编码)
            is_pua = any(0xE000 <= ord(c) <= 0xF8FF or
                        0xF0000 <= ord(c) <= 0xFFFFF or
                        0x100000 <= ord(c) <= 0x10FFFF for c in input_str)

            if is_pua:
                # 直接处理PUA编码
                try:
                    result = decoder.split_encoded_syllable(input_str)
                    # 确保解包结构正确
                    initial, _, (ascender, yunyin), (peak, descender) = result
                    syllable = SyllableStructure(
                        initial=initial,
                        ascender=ascender,
                        peak=peak,
                        descender=descender
                    )
                    full_pinyin = input_str  # 保持原样
                    ganyin = decoder.get_ganyin(input_str)
                    yunyin = decoder.get_yunyin(input_str)
                    jianyin = decoder.get_jianyin_code(input_str)
                except Exception as e:
                    self.logger.warning(f"解析PUA编码'{input_str}'失败: {e}")
                    raise ValueError(f"无效的PUA编码格式: {input_str}")
            else:
                # 正常拼音处理流程
                try:
                    code = decoder._get_code(input_str)
                    if not code:
                        raise ValueError(f"未找到拼音 '{input_str}' 的编码")

                    # 确保code是字符串类型
                    if isinstance(code, (list, tuple)):
                        code = code[0] if code else input_str

                    result = decoder.split_encoded_syllable(code)
                    # 确保解包结构正确
                    initial, _, (ascender, yunyin), (peak, descender) = result
                    syllable = SyllableStructure(
                        initial=initial,
                        ascender=ascender,
                        peak=peak,
                        descender=descender
                    )
                    full_pinyin = code  # 这里改为使用code而不是input_str
                    ganyin = decoder.get_ganyin(code)
                    yunyin = decoder.get_yunyin(code)
                    jianyin = decoder.get_jianyin_code(code)
                except Exception as e:
                    self.logger.warning(f"解析输入'{input_str}'失败: {e}")
                    raise

            return {
                "全拼": full_pinyin,
                "简拼": syllable.simplify_codes().get_abbreviation(),
                "干音": ganyin,
                "首音": syllable.initial,
                "呼音": syllable.ascender,
                "主音": syllable.peak,
                "末音": syllable.descender,
                "间音": jianyin,
                "韵音": yunyin
            }

        except Exception as e:
            self.logger.warning(f"解析输入'{input_str}'失败: {e}")
            return {
                "全拼": input_str,
                "简拼": input_str[0] + (input_str[1] if len(input_str)>1 else ''),
                "干音": input_str[1:] if len(input_str)>1 else "",
                "首音": input_str[0] if input_str else None,
                "呼音": None,
                "主音": None,
                "末音": None,
                "间音": None,
                "韵音": None
            }

    def ensure_table(self) -> None:
        """确保 '音元拼音' 表存在；如果不存在则创建（保留 全拼 唯一约束，移除其它唯一约束）"""
        with self._get_connection() as conn:
            cursor = conn.cursor()
            conn.execute("PRAGMA foreign_keys = ON;")
            cursor.execute('''
                CREATE TABLE IF NOT EXISTS "音元拼音" (
                    "编号" INTEGER PRIMARY KEY AUTOINCREMENT,
                    "全拼" TEXT NOT NULL UNIQUE,
                    "简拼" TEXT,
                    "首音" TEXT,
                    "干音" TEXT,
                    "呼音" TEXT,
                    "主音" TEXT,
                    "末音" TEXT,
                    "间音" TEXT,
                    "韵音" TEXT,
                    "映射编号" INTEGER REFERENCES "拼音映射关系"("映射编号") ON DELETE CASCADE,
                    "最近更新" TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            ''')
            conn.commit()

    def import_pinyin(self, pinyin_data: Dict[str, str]) -> int:
        """
        导入音元拼音数据（完整字段）
        """
        # 确保表存在（若不存在则创建）
        self.ensure_table()

        if not self.check_table_exists():
            raise RuntimeError("'音元拼音'表不存在，请先创建表结构")

        # 清空表中原有记录
        self.clear_table()

        # 修改后的索引创建部分
        with self._get_connection() as conn:
            cursor = conn.cursor()
            if not self.check_index_exists():
                self.logger.info("创建唯一索引...")
                try:
                    cursor.execute("""
                        CREATE UNIQUE INDEX IF NOT EXISTS sqlite_autoindex_音元拼音_1
                        ON "音元拼音"("全拼")
                    """)
                    conn.commit()

                    # 立即验证索引
                    if not self.check_index_exists():
                        raise RuntimeError("索引创建失败")
                except sqlite3.Error as e:
                    self.logger.error(f"创建索引失败: {e}")
                    raise

        # 修改这部分代码 - 原来是使用values()，现在改为使用keys()
        unique_data = {}
        for num_pinyin, yime_pinyin in pinyin_data.items():
            unique_data[yime_pinyin] = num_pinyin  # 这里改为使用音元拼音作为key

        # 准备要插入的数据（生成完整字段）
        values_to_insert = []
        seen_pinyins = set()  # 内存级二次去重

        for yime_pinyin in unique_data.keys():  # 这里改为使用values()获取音元拼音
            default_values = self._generate_default_values(yime_pinyin)  # 传入音元拼音编码
            if default_values["全拼"] in seen_pinyins:
                continue
            seen_pinyins.add(default_values["全拼"])

            values_to_insert.append((
                default_values["全拼"],
                default_values["简拼"],
                default_values["首音"],
                default_values["干音"],
                default_values["呼音"],
                default_values["主音"],
                default_values["末音"],
                default_values["间音"],
                default_values["韵音"]
            ))

        if not values_to_insert:
            self.logger.warning("没有有效数据可导入")
            return 0

        with self._get_connection() as conn:
            cursor = conn.cursor()

            try:
                # 执行批量插入
                cursor.executemany(
                    '''INSERT INTO "音元拼音" (
                        "全拼", "简拼", "首音", "干音",
                        "呼音", "主音", "末音", "间音", "韵音"
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)''',
                    values_to_insert
                )
                conn.commit()

                inserted_count = cursor.rowcount
                self.logger.info(
                    f"导入完成: 尝试导入 {len(values_to_insert)} 条, "
                    f"实际新增 {inserted_count} 条记录"
                )
                return inserted_count

            except sqlite3.Error as e:
                self.logger.error(f"数据库错误: {e}")
                conn.rollback()
                raise

    def load_from_mapping_table(self) -> Dict[str, str]:
        """
        从数据库表 `拼音映射关系` 中读取原拼音（原拼音类型='音元拼音'）
        返回字典形式：{原拼音: 原拼音}
        """
        with sqlite3.connect(str(DB_PATH)) as conn:
            conn.row_factory = sqlite3.Row
            conn.execute("PRAGMA foreign_keys = ON;")
            cur = conn.cursor()
            cur.execute('''
                SELECT "原拼音"
                FROM "拼音映射关系"
                WHERE "原拼音类型" = '音元拼音'
            ''')
            rows = cur.fetchall()
            data = {row["原拼音"]: row["原拼音"] for row in rows}
            self.logger.info(f"已从拼音映射关系表加载 {len(data)} 条音元拼音数据")
            return data

def main():
    """命令行入口"""
    importer = PinyinImporter()
    try:
        # 不自动清空表，保持现有特殊编码数据安全
        # 现在从数据库表拼音映射关系加载原拼音数据
        data = importer.load_from_mapping_table()
        count = importer.import_pinyin(data)
        print(f"导入完成，共新增 {count} 条记录")
    except Exception as e:
        logging.error(f"导入失败: {e}")
        raise

if __name__ == "__main__":
    main()
