"""
拼音数据导入工具（专职数据导入版）

说明：
- 该模块负责将 JSON 格式的映射数据导入到已有的 SQLite 数据库表中。
- 不默认创建复杂表结构，但会在导入前检查所需表是否存在并给出友好提示。
"""

import sqlite3
import json
import logging
from pathlib import Path
from typing import Dict, List

from utils.pinyin_normalizer import PinyinNormalizer
from utils.pinyin_zhuyin import PinyinZhuyinConverter


class 拼音数据导入器:
    """专职处理拼音数据导入的类"""

    REQUIRED_TABLES = [
        "音元拼音",
        "数字标调拼音",
        "音元拼音已有拼音映射"
    ]

    def __init__(self, 数据库路径: str | Path = "pinyin_hanzi.db"):
        self.数据库路径 = Path(数据库路径).absolute()
        self._配置日志()

    def _配置日志(self):
        logging.basicConfig(
            level=logging.INFO,
            format="%(asctime)s - %(levelname)s - %(message)s"
        )
        self.日志 = logging.getLogger(__name__)

    def _获取连接(self) -> sqlite3.Connection:
        conn = sqlite3.connect(str(self.数据库路径))
        conn.row_factory = sqlite3.Row
        return conn

    def _检查表存在(self, conn: sqlite3.Connection) -> List[str]:
        """返回缺失的表名列表（若全部存在返回空列表）"""
        cursor = conn.cursor()
        missing = []
        for 表名 in self.REQUIRED_TABLES:
            cursor.execute(
                "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
                (表名,)
            )
            if cursor.fetchone() is None:
                missing.append(表名)
        return missing

    def 加载JSON数据(self, json路径: str) -> Dict[str, str]:
        json路径 = Path(json路径).absolute()
        if not json路径.exists():
            raise FileNotFoundError(f"JSON文件不存在: {json路径}")
        with open(json路径, "r", encoding="utf-8") as f:
            data = json.load(f)
        self.日志.info(f"已从 {json路径} 加载 {len(data)} 条映射数据")
        return data

    def 导入音元拼音数据(self, 音元拼音数据: Dict[str, str]) -> int:
        """导入音元拼音表（只写入全拼列的去重项）"""
        with self._获取连接() as conn:
            missing = self._检查表存在(conn)
            if "音元拼音" in missing:
                raise RuntimeError(f"目标表缺失: 音元拼音。请先创建表或检查数据库: {self.数据库路径}")
            cursor = conn.cursor()
            去重音元拼音 = set(音元拼音数据.values())
            cursor.executemany(
                'INSERT OR IGNORE INTO "音元拼音" ("全拼") VALUES (?)',
                [(p,) for p in 去重音元拼音]
            )
            conn.commit()
            count = cursor.rowcount
            self.日志.info(f"导入音元拼音: 插入/忽略了 {count} 条记录")
            return count

    def 导入数字标调拼音数据(self, 数字标调拼音数据: Dict[str, str]) -> int:
        """导入数字标调拼音表（写入数字标调拼音字段）"""
        with self._获取连接() as conn:
            missing = self._检查表存在(conn)
            if "数字标调拼音" in missing:
                raise RuntimeError(f"目标表缺失: 数字标调拼音。请先创建表或检查数据库: {self.数据库路径}")
            cursor = conn.cursor()
            cursor.executemany(
                'INSERT OR IGNORE INTO "数字标调拼音" ("全拼") VALUES (?)',
                [(p,) for p in 数字标调拼音数据.keys()]
            )
            conn.commit()
            count = cursor.rowcount
            self.日志.info(f"导入数字标调拼音: 插入/忽略了 {count} 条记录")
            return count

    def 导入拼音映射数据(self, 映射数据: Dict[str, str]) -> int:
        """
        将映射数据写入 音元拼音已有拼音映射 表。
        假定映射数据格式为 {数字标调拼音: 音元拼音}
        """
        with self._获取连接() as conn:
            missing = self._检查表存在(conn)
            if "音元拼音已有拼音映射" in missing:
                raise RuntimeError(f"目标表缺失: 音元拼音已有拼音映射。请先创建表或检查数据库: {self.数据库路径}")

            cursor = conn.cursor()

            拼音列表 = list(映射数据.keys())

            # 标准化与注音转换
            标准化字典, _ = PinyinNormalizer.process_pinyin_dict(
                {p: p for p in 拼音列表}
            )
            注音字典, _ = PinyinZhuyinConverter.process_pinyin_dict(
                {p: p for p in 拼音列表}
            )

            params = []
            for 数字标调拼音, 音元拼音 in 映射数据.items():
                标准拼音 = 标准化字典.get(数字标调拼音, 数字标调拼音)
                注音符号 = 注音字典.get(数字标调拼音, "")
                params.append((音元拼音, 数字标调拼音, 标准拼音, 注音符号))

            cursor.executemany('''
                INSERT OR REPLACE INTO "音元拼音已有拼音映射"
                ("音元拼音", "带数拼音", "标准拼音", "注音符号")
                VALUES (?, ?, ?, ?)
            ''', params)

            conn.commit()
            count = cursor.rowcount
            self.日志.info(f"导入拼音映射: 插入/替换了 {count} 条记录")
            return count

    def 导入所有数据(self, 映射数据: Dict[str, str]) -> Dict[str, int]:
        """按顺序导入三类数据并返回每类导入数量"""
        with self._获取连接() as conn:
            missing = self._检查表存在(conn)
            if missing:
                raise RuntimeError(
                    "数据库缺少以下必要表: " + ", ".join(missing)
                    + f"。请先运行表结构创建脚本（例如 pinyin_db_manager.py）或提供包含这些表的数据库。数据库路径: {self.数据库路径}"
                )

        # 进行导入操作
        音元拼音数据 = {k: v for k, v in 映射数据.items()}
        数字标调拼音数据 = {k: k for k in 映射数据.keys()}

        结果 = {
            "音元拼音": self.导入音元拼音数据(音元拼音数据),
            "数字标调拼音": self.导入数字标调拼音数据(数字标调拼音数据),
            "拼音映射": self.导入拼音映射数据(映射数据)
        }
        self.日志.info(f"导入完成: {结果}")
        return 结果


if __name__ == "__main__":
    导入器 = 拼音数据导入器()
    try:
        映射数据 = 导入器.加载JSON数据("yinjie_code.json")
        结果 = 导入器.导入所有数据(映射数据)
        print(f"导入结果: {结果}")
    except FileNotFoundError as e:
        print(f"文件错误: {e}")
    except RuntimeError as e:
        print(f"运行时错误: {e}")
    except Exception as e:
        print(f"意外错误: {e}")
