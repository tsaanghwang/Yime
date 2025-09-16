"""
数字标调拼音数据导入工具

说明：
- 该模块专门负责将数字标调拼音数据导入到SQLite数据库
- 仅处理"数字标调拼音"表的相关操作
"""

import sqlite3
import json
import logging
from pathlib import Path
from typing import Dict, List

class 数字标调拼音导入器:
    """专门处理数字标调拼音数据导入的类"""

    REQUIRED_TABLE = "数字标调拼音"

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

    def _检查表存在(self, conn: sqlite3.Connection) -> bool:
        """检查目标表是否存在"""
        cursor = conn.cursor()
        cursor.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
            (self.REQUIRED_TABLE,)
        )
        return cursor.fetchone() is not None

    def 加载JSON数据(self, json路径: str) -> Dict[str, str]:
        """加载包含数字标调拼音的JSON文件"""
        json_path = Path(json路径).absolute()
        if not json_path.exists():
            raise FileNotFoundError(f"JSON文件不存在: {json_path}")
        with open(json_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        self.日志.info(f"已从 {json_path} 加载 {len(data)} 条数字标调拼音数据")
        return data

    def 解析拼音(self, pinyin_str: str) -> dict:
        """将数字标调拼音解析为声母、韵母、声调"""
        # 示例解析逻辑，您需要根据实际格式调整
        tone = int(pinyin_str[-1]) if pinyin_str[-1].isdigit() else 1
        base = pinyin_str[:-1] if pinyin_str[-1].isdigit() else pinyin_str

        # 简单声母识别逻辑（需根据您的拼音系统完善）
        initials = ["b", "p", "m", "f", "d", "t", "n", "l", "g", "k", "h",
                   "j", "q", "x", "zh", "ch", "sh", "r", "z", "c", "s", "y", "w"]
        shengmu = next((sm for sm in initials if base.startswith(sm)), "")
        yunmu = base[len(shengmu):]

        return {
            "声母": shengmu,
            "韵母": yunmu,
            "声调": tone
        }

    def 导入数据(self, 数字标调拼音数据: Dict[str, str]) -> int:
        """增强版导入方法，自动解析拼音成分"""
        with self._获取连接() as conn:
            cursor = conn.cursor()

            # 准备数据：解析每条拼音
            data = []
            for pinyin_str in 数字标调拼音数据.keys():
                components = self.解析拼音(pinyin_str)
                data.append((
                    pinyin_str,
                    components["声母"],
                    components["韵母"],
                    components["声调"]
                ))

            # 批量插入
            cursor.executemany(
                '''INSERT OR IGNORE INTO "数字标调拼音"
                (全拼, 声母, 韵母, 声调)
                VALUES (?, ?, ?, ?)''',
                data
            )
            conn.commit()
            return cursor.rowcount


if __name__ == "__main__":
    导入器 = 数字标调拼音导入器()
    try:
        数据 = 导入器.加载JSON数据("syllable_code.json")  # 或指定其他JSON文件
        结果 = 导入器.导入数据(数据)
        print(f"导入结果: {结果} 条记录")
    except Exception as e:
        print(f"错误: {e}")