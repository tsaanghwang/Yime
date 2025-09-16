"""
音元拼音导入工具 - 完整版
功能：将音元拼音数据导入到"音元拼音"表，并为必填字段提供默认值
"""

import sqlite3
import json
import logging
from pathlib import Path
from typing import Dict
from contextlib import contextmanager

from syllable_decoder import SyllableDecoder

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

    def clear_table(self) -> int:
        """删除音元拼音表中的所有记录"""
        with self._get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute('DELETE FROM "音元拼音"')
            deleted_count = cursor.rowcount
            conn.commit()
            self.logger.info(f"已清空音元拼音表，删除 {deleted_count} 条记录")
            return deleted_count

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
            is_pua = any(0xE000 <= ord(c) <= 0xF8FF for c in input_str)

            if is_pua:
                # 直接处理PUA编码
                try:
                    initial, _, (ascender, yunyin), (peak, descender) = decoder.split_encoded_syllable(input_str)
                    syllable = SyllableStructure(
                        initial=initial,
                        ascender=ascender,
                        peak=peak,
                        descender=descender
                    )
                    full_pinyin = f"[PUA]{input_str}"
                    ganyin = decoder.get_ganyin(input_str)
                    yunyin = decoder.get_yunyin(input_str)
                except Exception as e:
                    self.logger.warning(f"解析PUA编码'{input_str}'失败: {e}")
                    raise ValueError(f"无效的PUA编码格式: {input_str}")
            else:
                # 正常拼音处理流程
                syllable = decoder.decode(input_str)
                full_pinyin = input_str
                ganyin = decoder.get_ganyin(syllable.code)
                yunyin = decoder.get_yunyin(syllable.code)

            return {
                "全拼": full_pinyin,
                "简拼": syllable.simplify_codes().get_abbreviation(),
                "干音": ganyin,
                "首音": syllable.initial,
                "呼音": syllable.ascender,
                "主音": syllable.peak,
                "末音": syllable.descender,
                "间音": None,
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

    def import_pinyin(self, pinyin_data: Dict[str, str]) -> int:
        """
        导入音元拼音数据（完整字段）
        参数:
            pinyin_data: {数字标调拼音: 音元拼音} 的映射字典
        返回:
            实际导入的记录数
        """
        if not self.check_table_exists():
            raise RuntimeError("'音元拼音'表不存在，请先创建表结构")

        # 清空表中原有记录
        self.clear_table()

        # 准备要插入的数据（生成完整字段）
        values_to_insert = []
        for pinyin in pinyin_data.values():
            default_values = self._generate_default_values(pinyin)
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

def main():
    """命令行入口"""
    importer = PinyinImporter()
    try:
        data = importer.load_json_data("syllable_code.json")
        count = importer.import_pinyin(data)
        print(f"导入完成，共新增 {count} 条记录")
    except Exception as e:
        logging.error(f"导入失败: {e}")
        raise

if __name__ == "__main__":
    main()