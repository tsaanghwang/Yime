"""
音元拼音结构表导入工具。

用途：
- 从库内基础映射面 `pinyin_yime_code` 读取单音节完整音元编码。
- 重建兼容映射表 `mapping_yime_code`，按唯一 `yime_code` 重新编号，编号从 1 开始。
- 为每个完整编码解析出 `简拼` 与 `首音/干音/呼音/主音/末音/间音/韵音` 等结构字段。
- 把结果写入保留结构表（优先 `syllable_structure`，否则 `音元拼音`），并让 `映射编号` 对齐 `mapping_yime_code.mapping_id`。

定位：
- 这张表是简拼实验和音节结构分析的基础层，不是当前 runtime 主线候选表。
- 当前 runtime 主线仍然是 `source_pinyin.db -> prototype tables -> refresh_runtime_yime_codes`。
"""

import sqlite3
import json
import logging
from pathlib import Path
from typing import Dict
from contextlib import contextmanager

try:
    from syllable_structure import SyllableStructure
    from syllable_decoder import SyllableDecoder
    from utils_charfilter import is_allowed_code_char
except ModuleNotFoundError:
    from yime.syllable_structure import SyllableStructure
    from yime.syllable_decoder import SyllableDecoder
    from yime.utils_charfilter import is_allowed_code_char

REPO_ROOT = Path(__file__).resolve().parent.parent
DB_PATH = Path(__file__).resolve().parent / "pinyin_hanzi.db"
PROJECTION_PATH = REPO_ROOT / "internal_data" / "bmp_pua_trial_projection.json"
CANONICAL_SYMBOL_PATH = REPO_ROOT / "internal_data" / "key_to_symbol.json"
TABLE_NAME_CANDIDATES = ("syllable_structure", "音元拼音")
BASE_YIME_CODE_TABLE = "pinyin_yime_code"
COMPAT_MAPPING_TABLE = "mapping_yime_code"
UNIQUE_FULL_PINYIN_INDEX = "idx_syllable_structure_full_pinyin_unique"
LEGACY_WARNING = (
    "rebuild_yinyuan_structure_table.py 仅保留 legacy-compatible 用途；"
    "当前主线请改走 source_pinyin.db -> prototype tables -> refresh_runtime_yime_codes 链。"
)


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
    """把完整音元编码拆解后写入保留音节结构表。"""

    STRUCTURE_TABLE_DDL = f'''
        CREATE TABLE IF NOT EXISTS "音元拼音" (
            "编号" INTEGER PRIMARY KEY AUTOINCREMENT,
            "全拼" TEXT NOT NULL UNIQUE,
            "简拼" TEXT UNIQUE,
            "首音" TEXT NOT NULL,
            "干音" TEXT NOT NULL,
            "呼音" TEXT,
            "主音" TEXT,
            "末音" TEXT,
            "间音" TEXT,
            "韵音" TEXT,
            "映射编号" INTEGER REFERENCES "{COMPAT_MAPPING_TABLE}"("mapping_id") ON DELETE SET NULL,
            "最近更新" TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    '''

    def __init__(self, db_path: str | Path | None = None):
        self.db_path = Path(db_path).resolve() if db_path is not None else DB_PATH.resolve()
        self.table_name: str | None = None
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

    @staticmethod
    def _quote_identifier(identifier: str) -> str:
        return '"' + identifier.replace('"', '""') + '"'

    @staticmethod
    def _collapse_consecutive_codes(encoded: str) -> str:
        if not encoded:
            return ""
        merged: list[str] = []
        previous: str | None = None
        for char in encoded:
            if char == previous:
                continue
            merged.append(char)
            previous = char
        return "".join(merged)

    def _detect_table_name(self, conn: sqlite3.Connection) -> str | None:
        placeholders = ",".join("?" for _ in TABLE_NAME_CANDIDATES)
        row = conn.execute(
            f"SELECT name FROM sqlite_master WHERE type='table' AND name IN ({placeholders})",
            TABLE_NAME_CANDIDATES,
        ).fetchone()
        return str(row[0]) if row else None

    def _require_table_name(self) -> str:
        if self.table_name:
            return self.table_name
        with self._get_connection() as conn:
            table_name = self._detect_table_name(conn)
            if table_name is None:
                self._ensure_structure_table_exists(conn)
                table_name = self._detect_table_name(conn)
        if table_name is None:
            raise RuntimeError(
                f"未找到音节结构表；已检查: {', '.join(TABLE_NAME_CANDIDATES)}。当前数据库: {self.db_path}"
            )
        self.table_name = table_name
        return table_name

    def _ensure_structure_table_exists(self, conn: sqlite3.Connection) -> None:
        conn.execute(self.STRUCTURE_TABLE_DDL)
        conn.commit()

    def _ensure_mapping_table_exists(self, conn: sqlite3.Connection) -> None:
        conn.execute(
            f'''
            CREATE TABLE IF NOT EXISTS {COMPAT_MAPPING_TABLE} (
                mapping_id INTEGER PRIMARY KEY,
                yime_code TEXT NOT NULL,
                source_pinyin_tone TEXT,
                updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
            '''
        )
        conn.execute(
            f"CREATE INDEX IF NOT EXISTS idx_mapping_yime_code_yime_code ON {COMPAT_MAPPING_TABLE}(yime_code)"
        )

    def _get_structure_fk_target(self, conn: sqlite3.Connection, table_name: str) -> str | None:
        quoted_table = self._quote_identifier(table_name)
        for row in conn.execute(f"PRAGMA foreign_key_list({quoted_table})").fetchall():
            from_column = row[3]
            target_table = row[2]
            if from_column == "映射编号":
                return str(target_table)
        return None

    def _collect_structure_dependent_views(
        self,
        conn: sqlite3.Connection,
        table_name: str,
        legacy_table_name: str,
    ) -> list[tuple[str, str]]:
        rows = conn.execute(
            "SELECT name, sql FROM sqlite_master WHERE type='view' AND sql IS NOT NULL"
        ).fetchall()
        dependencies: list[tuple[str, str]] = []
        for view_name, view_sql in rows:
            sql_text = str(view_sql)
            if table_name in sql_text or legacy_table_name in sql_text:
                normalized_sql = sql_text.replace(legacy_table_name, table_name)
                dependencies.append((str(view_name), normalized_sql))
        return dependencies

    def _structure_table_requires_rebuild(self, conn: sqlite3.Connection, table_name: str) -> bool:
        quoted_table = self._quote_identifier(table_name)
        columns = conn.execute(f"PRAGMA table_info({quoted_table})").fetchall()
        for column in columns:
            name = column[1]
            is_not_null = bool(column[3])
            if name == "首音":
                return not is_not_null
        return False

    def _migrate_structure_table_foreign_key(self) -> None:
        with self._get_connection() as conn:
            table_name = self._detect_table_name(conn)
            if table_name != "音元拼音":
                return

            current_target = self._get_structure_fk_target(conn, table_name)
            requires_rebuild = self._structure_table_requires_rebuild(conn, table_name)
            if current_target == COMPAT_MAPPING_TABLE and not requires_rebuild:
                return

            self._ensure_mapping_table_exists(conn)
            legacy_table_name = "音元拼音__legacy_fk_backup"
            quoted_table = self._quote_identifier(table_name)
            quoted_legacy = self._quote_identifier(legacy_table_name)
            dependent_views = self._collect_structure_dependent_views(conn, table_name, legacy_table_name)

            conn.execute("PRAGMA foreign_keys=OFF")
            try:
                conn.execute("BEGIN")
                for view_name, _view_sql in dependent_views:
                    conn.execute(f"DROP VIEW IF EXISTS {self._quote_identifier(view_name)}")
                conn.execute(f"DROP TABLE IF EXISTS {quoted_legacy}")
                conn.execute(f"ALTER TABLE {quoted_table} RENAME TO {quoted_legacy}")
                conn.execute(self.STRUCTURE_TABLE_DDL)
                conn.execute(
                    f'''
                    INSERT INTO {quoted_table} (
                        "编号", "全拼", "简拼", "首音", "干音",
                        "呼音", "主音", "末音", "间音", "韵音", "映射编号", "最近更新"
                    )
                    SELECT
                        "编号", "全拼", "简拼", "首音", "干音",
                        "呼音", "主音", "末音", "间音", "韵音", "映射编号", "最近更新"
                    FROM {quoted_legacy}
                    '''
                )
                conn.execute(f"DROP TABLE {quoted_legacy}")
                for _view_name, view_sql in dependent_views:
                    conn.execute(view_sql)
                conn.commit()
            except Exception:
                conn.rollback()
                raise
            finally:
                conn.execute("PRAGMA foreign_keys=ON")

            rebuilt_reasons = []
            if current_target != COMPAT_MAPPING_TABLE:
                rebuilt_reasons.append(f"物理外键从 {current_target or '无'} 迁移到 {COMPAT_MAPPING_TABLE}")
            if requires_rebuild:
                rebuilt_reasons.append("首音列改为 NOT NULL")
            self.logger.info(f"已重建 {table_name}：{'；'.join(rebuilt_reasons)}")

    def rebuild_mapping_yime_code(self) -> int:
        with self._get_connection() as conn:
            row = conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
                (BASE_YIME_CODE_TABLE,),
            ).fetchone()
            if row is None:
                raise RuntimeError(f"基础映射表不存在: {BASE_YIME_CODE_TABLE}")

            self._ensure_mapping_table_exists(conn)

            source_rows = conn.execute(
                f'''
                SELECT yime_code, MIN(pinyin_tone) AS source_pinyin_tone
                FROM {BASE_YIME_CODE_TABLE}
                WHERE TRIM(COALESCE(yime_code, '')) <> ''
                GROUP BY yime_code
                ORDER BY source_pinyin_tone, yime_code
                '''
            ).fetchall()
            mapping_rows = [
                (index, row[0], row[1])
                for index, row in enumerate(source_rows, start=1)
            ]

            conn.execute(f"DELETE FROM {COMPAT_MAPPING_TABLE}")
            conn.executemany(
                f'''
                INSERT INTO {COMPAT_MAPPING_TABLE} (mapping_id, yime_code, source_pinyin_tone, updated_at)
                VALUES (?, ?, ?, CURRENT_TIMESTAMP)
                ''',
                mapping_rows,
            )
            conn.commit()
            return len(mapping_rows)

    def check_table_exists(self) -> bool:
        """检查音节结构表是否存在；若缺失则按当前兼容结构创建。"""
        with self._get_connection() as conn:
            table_name = self._detect_table_name(conn)
            if table_name is None:
                self._ensure_structure_table_exists(conn)
                table_name = self._detect_table_name(conn)
        if table_name is not None:
            self.table_name = table_name
            return True
        return False

    def check_index_exists(self) -> bool:
        """增强版索引检查，同时验证索引是否有效"""
        with self._get_connection() as conn:
            table_name = self._detect_table_name(conn)
            if table_name is None:
                return False
            self.table_name = table_name
            quoted_table = self._quote_identifier(table_name)
            index_rows = conn.execute(f"PRAGMA index_list({quoted_table})").fetchall()
            for row in index_rows:
                index_name = row[1]
                is_unique = bool(row[2])
                if not is_unique:
                    continue
                quoted_index = self._quote_identifier(index_name)
                index_info = conn.execute(f"PRAGMA index_info({quoted_index})").fetchall()
                columns = [info[2] for info in index_info]
                if columns == ["全拼"]:
                    return True
            return False

    def clear_table(self) -> int:
        """删除音元拼音表中的所有记录（增强版）"""
        if not self.check_table_exists():
            self.logger.warning("音节结构表不存在")
            return 0

        table_name = self._require_table_name()
        quoted_table = self._quote_identifier(table_name)
        with self._get_connection() as conn:
            cursor = conn.cursor()
            try:
                # 先禁用外键约束
                cursor.execute("PRAGMA foreign_keys=OFF")

                # 使用更彻底的表清空方式
                cursor.execute(f"DELETE FROM {quoted_table}")

                # 先提交DELETE操作
                conn.commit()

                # 在事务外执行VACUUM
                cursor.execute("VACUUM")

                # 开始新的事务
                cursor.execute("BEGIN")

                # 重置自增计数器（如果有）
                cursor.execute("DELETE FROM sqlite_sequence WHERE name=?", (table_name,))

                conn.commit()
                return 0  # 不再返回删除计数
            except Exception as e:
                conn.rollback()
                self.logger.error(f"清空表失败: {e}")
                raise
            finally:
                # 恢复外键约束
                cursor.execute("PRAGMA foreign_keys=ON")

    def load_mapping_rows_from_db(self) -> list[tuple[int, str, str]]:
        """从库内映射面读取 `(mapping_id, source_pinyin_tone, yime_code)`。"""
        rebuilt_count = self.rebuild_mapping_yime_code()
        with self._get_connection() as conn:
            rows = conn.execute(
                f'''
                SELECT mapping_id, source_pinyin_tone, yime_code
                FROM {COMPAT_MAPPING_TABLE}
                ORDER BY mapping_id
                '''
            ).fetchall()
        mapping_rows = [(int(row[0]), str(row[1] or ""), str(row[2])) for row in rows]
        self.logger.info(
            f"已从库内基础映射面 {BASE_YIME_CODE_TABLE} 重建 {COMPAT_MAPPING_TABLE}，"
            f"共 {rebuilt_count} 条；本次读取 {len(mapping_rows)} 条音元结构记录"
        )
        return mapping_rows

    @staticmethod
    def _coerce_syllable_structure(result: object) -> SyllableStructure:
        if all(hasattr(result, attr) for attr in ("initial", "ascender", "peak", "descender")):
            return result
        if isinstance(result, (list, tuple)) and len(result) >= 4:
            initial = result[0]
            third = tuple(result[2]) if len(result) > 2 and isinstance(result[2], (list, tuple)) else (None, None)
            fourth = tuple(result[3]) if len(result) > 3 and isinstance(result[3], (list, tuple)) else (None, None)
            ascender = third[0] if len(third) > 0 else None
            peak = fourth[0] if len(fourth) > 0 else None
            descender = fourth[1] if len(fourth) > 1 else None
            return SyllableStructure(
                initial=initial,
                ascender=ascender,
                peak=peak,
                descender=descender,
            )
        raise ValueError(f"无法识别的音节结构返回值: {type(result)!r}")

    def _generate_default_values(self, input_str: str) -> dict:
        """从完整音元编码生成简拼与多角度音节结构字段。"""
        decoder = SyllableDecoder()

        # 判断输入是否为PUA字符(编码)
        is_pua = any(0xE000 <= ord(c) <= 0xF8FF or
                    0xF0000 <= ord(c) <= 0xFFFFD or
                    0x100000 <= ord(c) <= 0x10FFFD for c in input_str)

        try:
            if is_pua:
                result = decoder.split_encoded_syllable(input_str)
                syllable = self._coerce_syllable_structure(result)
                full_pinyin = input_str
            else:
                code = decoder._get_code(input_str)
                if not code:
                    raise ValueError(f"未找到拼音 '{input_str}' 的编码")

                if isinstance(code, (list, tuple)):
                    code = code[0] if code else input_str

                result = decoder.split_encoded_syllable(code)
                syllable = self._coerce_syllable_structure(result)
                full_pinyin = code

            if len(full_pinyin) != 4:
                raise ValueError(f"全拼必须是四音等长编码，实际长度为 {len(full_pinyin)}: {input_str}")
            if not syllable.initial:
                raise ValueError(f"首音切分失败: {input_str}")
            if full_pinyin[0] != syllable.initial:
                raise ValueError(
                    f"首音与全拼首位不一致: full={full_pinyin!r}, initial={syllable.initial!r}, input={input_str!r}"
                )

            ganyin = full_pinyin[1:]
            if len(ganyin) != 3:
                raise ValueError(f"干音必须是切除首音后的后三音，实际长度为 {len(ganyin)}: {input_str}")

            huyin = full_pinyin[1]
            zhuyin = full_pinyin[2]
            moyin = full_pinyin[3]
            yunyin = full_pinyin[2:4]

            if (syllable.ascender or "") != huyin:
                raise ValueError(
                    f"呼音必须等于全拼第二音: ascender={syllable.ascender!r}, expected={huyin!r}, input={input_str!r}"
                )
            if (syllable.peak or "") != zhuyin:
                raise ValueError(
                    f"主音必须等于全拼第三音: peak={syllable.peak!r}, expected={zhuyin!r}, input={input_str!r}"
                )
            if (syllable.descender or "") != moyin:
                raise ValueError(
                    f"末音必须等于全拼第四音: descender={syllable.descender!r}, expected={moyin!r}, input={input_str!r}"
                )

            jianyin = full_pinyin[1:3]
            if len(jianyin) != 2:
                raise ValueError(f"间音必须是切除首音和末音后的中间两音，实际长度为 {len(jianyin)}: {input_str}")

            expected_jianyin = huyin + zhuyin
            if jianyin != expected_jianyin:
                raise ValueError(
                    f"间音与呼音+主音不一致: jianyin={jianyin!r}, ascender+peak={expected_jianyin!r}, input={input_str!r}"
                )

            expected_yunyin = zhuyin + moyin
            if yunyin != expected_yunyin:
                raise ValueError(
                    f"韵音必须等于主音+末音: yunyin={yunyin!r}, peak+descender={expected_yunyin!r}, input={input_str!r}"
                )

            jianpin = syllable.simplify_codes().get_abbreviation()
            expected_jianpin = self._collapse_consecutive_codes(full_pinyin)
            if jianpin != expected_jianpin:
                raise ValueError(
                    f"简拼必须等于把音节中连续相同的两音或三音合并后的结果: "
                    f"jianpin={jianpin!r}, expected={expected_jianpin!r}, input={input_str!r}"
                )

            return {
                "全拼": full_pinyin,
                "简拼": jianpin,
                "干音": ganyin,
                "首音": syllable.initial,
                "呼音": huyin,
                "主音": zhuyin,
                "末音": moyin,
                "间音": jianyin,
                "韵音": yunyin
            }
        except Exception as e:
            self.logger.warning(f"解析输入'{input_str}'失败: {e}")
            raise

    def _normalize_to_canonical(self, encoded: str | None) -> str:
        if not encoded:
            return ""
        return "".join(BMP_TO_CANONICAL.get(char, char) for char in encoded)

    def import_pinyin(self, mapping_rows: list[tuple[int, str, str]]) -> int:
        """
        导入音元拼音结构数据（完整字段）
        参数:
            mapping_rows: `(mapping_id, source_pinyin_tone, 完整音元编码)` 行列表
        返回:
            实际导入的记录数
        """
        if not self.check_table_exists():
            raise RuntimeError(
                f"未找到音节结构表；已检查: {', '.join(TABLE_NAME_CANDIDATES)}。当前数据库: {self.db_path}"
            )

        self._migrate_structure_table_foreign_key()

        table_name = self._require_table_name()
        quoted_table = self._quote_identifier(table_name)

        # 清空表中原有记录
        self.clear_table()

        # 修改后的索引创建部分
        with self._get_connection() as conn:
            cursor = conn.cursor()
            if not self.check_index_exists():
                self.logger.info("创建唯一索引...")
                try:
                    cursor.execute("""
                        CREATE UNIQUE INDEX IF NOT EXISTS idx_syllable_structure_full_pinyin_unique
                        ON """ + quoted_table + """("全拼")
                    """)
                    conn.commit()

                    # 立即验证索引
                    if not self.check_index_exists():
                        raise RuntimeError("索引创建失败")
                except sqlite3.Error as e:
                    self.logger.error(f"创建索引失败: {e}")
                    raise

        # 准备要插入的数据（生成完整字段）
        values_to_insert = []
        seen_pinyins = set()

        for mapping_id, source_pinyin_tone, yime_pinyin in mapping_rows:
            canonical_pinyin = self._normalize_to_canonical(yime_pinyin)
            default_values = self._generate_default_values(canonical_pinyin)  # 统一落 canonical SPUA-B
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
                default_values["韵音"],
                mapping_id,
            ))

        if not values_to_insert:
            self.logger.warning("没有有效数据可导入")
            return 0

        with self._get_connection() as conn:
            cursor = conn.cursor()

            try:
                # 执行批量插入
                cursor.executemany(
                    f'''INSERT INTO {quoted_table} (
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

    # 在需要验证编码有效性的地方（示例）
    def _is_valid_encoded_value(val: str) -> bool:
        # 旧：可能用 ord()/isalpha() 写死范围
        return bool(val) and all(is_allowed_code_char(ch) for ch in val)

def main():
    """命令行入口"""
    importer = PinyinImporter()
    try:
        importer.logger.warning(LEGACY_WARNING)
        mapping_rows = importer.load_mapping_rows_from_db()
        count = importer.import_pinyin(mapping_rows)
        print(f"导入完成，共新增 {count} 条记录")
    except Exception as e:
        logging.error(f"导入失败: {e}")
        raise

if __name__ == "__main__":
    main()
