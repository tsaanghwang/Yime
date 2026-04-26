"""
音元拼音导入工具 - 完整版
功能：将音元拼音数据导入到"音元拼音"表，并为必填字段提供默认值
"""

import json
import logging
from pathlib import Path
import sqlite3
from typing import Dict, Generator
from contextlib import contextmanager

try:
    from syllable_structure import SyllableStructure
    from syllable_decoder import SyllableDecoder
except ModuleNotFoundError:
    from yime.syllable_structure import SyllableStructure
    from yime.syllable_decoder import SyllableDecoder

# 固定数据库路径为模块同目录下的 pinyin_hanzi.db
DB_PATH = Path(__file__).parent.resolve() / "pinyin_hanzi.db"
REPO_ROOT = Path(__file__).resolve().parent.parent
PROJECTION_PATH = REPO_ROOT / "internal_data" / "bmp_pua_trial_projection.json"
CANONICAL_SYMBOL_PATH = REPO_ROOT / "internal_data" / "key_to_symbol.json"


def _load_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def _build_bmp_to_canonical_map() -> dict[str, str]:
    projection = _load_json(PROJECTION_PATH)
    canonical_symbols = _load_json(CANONICAL_SYMBOL_PATH)
    bmp_to_canonical: dict[str, str] = {}

    for slot_key, slot_info in projection.get("used_mapping", {}).items():
        bmp_char = slot_info.get("char")
        canonical_char = canonical_symbols.get(slot_key)
        if bmp_char and canonical_char:
            bmp_to_canonical[str(bmp_char)] = str(canonical_char)

    return bmp_to_canonical


BMP_TO_CANONICAL = _build_bmp_to_canonical_map()

class PinyinImporter:
    """音元拼音导入器（完整字段导入）"""

    def __init__(self, db_path: str | Path | None = None):
        # 默认使用模块目录下的 DB_PATH，外部可传入自定义路径
        if db_path is None:
            self.db_path = DB_PATH
        else:
            self.db_path = Path(db_path).expanduser().resolve()
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
    def _get_connection(self) -> Generator[sqlite3.Connection, None, None]:
        """上下文管理器：返回启用并校验 foreign_keys 的 sqlite3 连接"""
        conn = sqlite3.connect(str(self.db_path))
        conn.row_factory = sqlite3.Row
        try:
            # 尝试启用外键约束
            conn.execute("PRAGMA foreign_keys = ON;")
            # 验证外键约束是否已启用
            cur = conn.execute("PRAGMA foreign_keys;")
            fk_on = (cur.fetchone() or [0])[0]
            if fk_on != 1:
                # 记录警告（若需要，可在此抛异常以强制要求外键开启）
                try:
                    conn.execute("PRAGMA foreign_keys = ON;")
                except Exception:
                    self.logger.warning("无法启用 sqlite 外键约束 (PRAGMA foreign_keys)。请检查 SQLite 版本/连接模式。")
                else:
                    self.logger.warning("sqlite 外键约束尝试启用，但 PRAGMA 检查未返回 1，已再次尝试。")
            else:
                self.logger.debug("sqlite 外键约束已启用 (PRAGMA foreign_keys = 1)")
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
        """生成默认值：干音/间音/韵音使用未化简的全拼片段；简拼仅计算但不影响这些字段。"""
        try:
            from syllable_decoder import SyllableDecoder
        except Exception:
            from yime.syllable_decoder import SyllableDecoder

        try:
            from syllable_structure import SyllableStructure
        except Exception:
            try:
                from yime.syllable_structure import SyllableStructure
            except Exception:
                SyllableStructure = None

        decoder = SyllableDecoder()
        full_pinyin = input_str or ""

        # 尝试让 decoder 提供标准化的 full_pinyin（若有）
        try:
            if hasattr(decoder, "get_full_pinyin"):
                full_pinyin = decoder.get_full_pinyin(full_pinyin)
        except Exception:
            # 忽略，使用原始输入
            pass

        # 解析基础部件（用于首音/呼音/主音/末音）
        split_res = None
        try:
            split_res = decoder.split_encoded_syllable(full_pinyin)
        except Exception:
            split_res = None

        if split_res is None:
            initial = ascender = peak = descender = None
        elif hasattr(split_res, "initial") and hasattr(split_res, "ascender"):
            initial = getattr(split_res, "initial", None)
            ascender = getattr(split_res, "ascender", None)
            peak = getattr(split_res, "peak", None)
            descender = getattr(split_res, "descender", None)
        else:
            try:
                initial = split_res[0] if len(split_res) > 0 else None
                ascender = split_res[2][0] if len(split_res) > 2 and split_res[2] else None
                peak = split_res[3][0] if len(split_res) > 3 and split_res[3] else None
                descender = split_res[3][1] if len(split_res) > 3 and split_res[3] and len(split_res[3]) > 1 else None
            except Exception:
                initial = ascender = peak = descender = None

        # 保证为字符串
        def s(x):
            return x if x is None or isinstance(x, str) else str(x)

        # 干音/间音/韵音：严格使用未化简的 full_pinyin 片段（便于观察编码系统）
        # 干音 = 全拼去首音（原始、不化简）
        if full_pinyin and len(full_pinyin) > 1:
            ganyin = full_pinyin[1:]
        else:
            ganyin = ""

        # 间音 = 中间两音（若不足则尽可能取）
        if len(full_pinyin) >= 3:
            jianyin = full_pinyin[1:3]
        elif len(full_pinyin) > 1:
            jianyin = full_pinyin[1:]
        else:
            jianyin = ""

        # 韵音 = 后两音（未化简）
        if len(full_pinyin) >= 2:
            yunyin_val = full_pinyin[-2:]
        elif len(full_pinyin) > 1:
            yunyin_val = full_pinyin[1:]
        else:
            yunyin_val = ""

        # 简拼仍计算（但不用于上面字段）
        jian = None
        try:
            if SyllableStructure is not None and hasattr(SyllableStructure, "simplify_full_to_abbreviation"):
                jian = SyllableStructure.simplify_full_to_abbreviation(full_pinyin)
            elif hasattr(decoder, "get_abbreviation"):
                jian = decoder.get_abbreviation(full_pinyin)
            elif hasattr(decoder, "get_jianpin"):
                jian = decoder.get_jianpin(full_pinyin)
        except Exception:
            jian = None
        if not jian:
            # 保守默认：取全拼前两位（仅作记录）
            jian = (full_pinyin[0] + (full_pinyin[1] if len(full_pinyin) > 1 else "")) if full_pinyin else ""

        return {
            "全拼": s(full_pinyin),
            "简拼": s(jian),
            "干音": s(ganyin),
            "首音": s(initial),
            "呼音": s(ascender),
            "主音": s(peak),
            "末音": s(descender),
            "间音": s(jianyin),
            "韵音": s(yunyin_val)
        }

    def _normalize_to_canonical(self, encoded: str | None) -> str:
        if not encoded:
            return ""
        return "".join(BMP_TO_CANONICAL.get(char, char) for char in encoded)

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

        # pinyin_data expected: {映射编号: 原拼音}
        for mapping_id, yime_pinyin in pinyin_data.items():
            canonical_pinyin = self._normalize_to_canonical(yime_pinyin)
            # yime_pinyin 是要插入的全拼编码
            # 去重：只处理每个全拼一次
            if canonical_pinyin in seen_pinyins:
                continue
            seen_pinyins.add(canonical_pinyin)

            default_values = self._generate_default_values(canonical_pinyin)  # 统一落 canonical SPUA-B

            values_to_insert.append((
                default_values["全拼"],
                default_values["简拼"],
                default_values["首音"],
                default_values["干音"],
                default_values["呼音"],
                default_values["主音"],
                default_values["末音"],
                default_values["间音"],
                default_values["韵音"],
                mapping_id  # 将映射编号写入最后一列
            ))

        if not values_to_insert:
            self.logger.warning("没有有效数据可导入")
            return 0

        with self._get_connection() as conn:
            cursor = conn.cursor()

            try:
                # 执行批量插入（使用 INSERT OR IGNORE 保持幂等性；若需更新可改为 UPSERT）
                cursor.executemany(
                    '''INSERT OR IGNORE INTO "音元拼音" (
                        "全拼", "简拼", "首音", "干音",
                        "呼音", "主音", "末音", "间音", "韵音", "映射编号"
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
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

    def load_from_mapping_table(self) -> Dict[int, str]:
        """
        从数据库表 `拼音映射关系` 中读取映射编号与原拼音（原拼音类型='音元拼音'）
        返回字典形式：{映射编号: 原拼音}
        """
        with self._get_connection() as conn:
            cur = conn.cursor()
            cur.execute('''
                SELECT "映射编号", "原拼音"
                FROM "拼音映射关系"
                WHERE "原拼音类型" = '音元拼音'
            ''')
            rows = cur.fetchall()
            data: Dict[int, str] = {}
            for row in rows:
                # row 是 sqlite3.Row，支持 name 索引
                mapping_id = row["映射编号"]
                original = row["原拼音"]
                data[mapping_id] = original
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
