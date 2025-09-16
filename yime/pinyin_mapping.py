"""
拼音映射关系导入工具

说明：
- 专门负责将拼音映射关系导入到 "音元拼音已有拼音映射" 表
- 直接从数据库中的"数字标调拼音"表获取数据
"""

import sqlite3
import logging
from pathlib import Path
from typing import Dict, List, Tuple

from utils.pinyin_normalizer import PinyinNormalizer
from utils.pinyin_zhuyin import PinyinZhuyinConverter


class 拼音映射导入器:
    """专职处理拼音映射关系导入的类"""

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
        """返回缺失的表名列表"""
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

    def 从数据库加载数据(self) -> Dict[str, str]:
        """从数据库加载数字标调拼音到音元拼音的映射关系"""
        with self._获取连接() as conn:
            cursor = conn.cursor()

            # 获取表结构信息
            cursor.execute('PRAGMA table_info("数字标调拼音")')
            数字标调拼音结构 = cursor.fetchall()

            cursor.execute('PRAGMA table_info("音元拼音")')
            音元拼音结构 = cursor.fetchall()

            # 调试输出表结构
            self.日志.debug("数字标调拼音表结构: %s", [col[1] for col in 数字标调拼音结构])
            self.日志.debug("音元拼音表结构: %s", [col[1] for col in 音元拼音结构])

            # 使用更灵活的JOIN条件
            cursor.execute('''
                SELECT d.全拼 AS 数字标调拼音, y.全拼 AS 音元拼音
                FROM "数字标调拼音" d
                JOIN "音元拼音" y ON
                    (d.声母 = y.声母 OR (d.声母 IS NULL AND y.声母 IS NULL))
                    AND d.韵母 = y.韵母
                    AND d.声调 = y.声调
            ''')

            映射数据 = {row["数字标调拼音"]: row["音元拼音"] for row in cursor.fetchall()}
            self.日志.info(f"从数据库加载 {len(映射数据)} 条映射数据")
            return 映射数据

    def 导入映射数据(self, 映射数据: Dict[str, str]) -> int:
        """
        导入拼音映射关系数据
        参数:
            - 映射数据: 字典格式 {数字标调拼音: 音元拼音}
        返回:
            - 插入/替换的记录数
        """
        with self._获取连接() as conn:
            missing = self._检查表存在(conn)
            if missing:
                raise RuntimeError(
                    f"数据库缺少以下必要表: {', '.join(missing)}"
                )

            cursor = conn.cursor()
            拼音列表 = list(映射数据.keys())
            标准化字典, _ = PinyinNormalizer.process_pinyin_dict({p: p for p in 拼音列表})
            注音字典, _ = PinyinZhuyinConverter.process_pinyin_dict({p: p for p in 拼音列表})

            params = []
            for 数字标调拼音, 音元拼音 in 映射数据.items():
                # 获取音元拼音编号
                cursor.execute('SELECT "编号" FROM "音元拼音" WHERE "全拼" = ?', (音元拼音,))
                音元拼音结果 = cursor.fetchone()
                if not 音元拼音结果:
                    self.日志.error(f"音元拼音表中找不到拼音: {音元拼音}")
                    continue
                音元拼音编号 = 音元拼音结果[0]

                # 获取数字标调拼音编号
                cursor.execute('SELECT "编号" FROM "数字标调拼音" WHERE "全拼" = ?', (数字标调拼音,))
                数字标调拼音结果 = cursor.fetchone()
                if not 数字标调拼音结果:
                    self.日志.error(f"数字标调拼音表中找不到拼音: {数字标调拼音}")
                    continue
                数字标调拼音编号 = 数字标调拼音结果[0]

                # 准备插入参数
                标准拼音 = 标准化字典.get(数字标调拼音, 数字标调拼音)
                注音符号 = 注音字典.get(数字标调拼音, "")
                params.append((音元拼音编号, 数字标调拼音编号, 标准拼音, 注音符号))

            if not params:
                raise RuntimeError("没有有效的拼音映射可以导入")

            # 批量插入映射关系
            cursor.executemany('''
                INSERT OR REPLACE INTO "音元拼音已有拼音映射"
                ("音元拼音", "带数拼音", "标准拼音", "注音符号")
                VALUES (?, ?, ?, ?)
            ''', params)

            conn.commit()
            count = cursor.rowcount
            self.日志.info(f"导入拼音映射: 插入/替换了 {count} 条记录")
            return count


if __name__ == "__main__":
    导入器 = 拼音映射导入器()
    try:
        映射数据 = 导入器.从数据库加载数据()
        结果 = 导入器.导入映射数据(映射数据)
        print(f"导入结果: {结果} 条记录")
    except RuntimeError as e:
        print(f"运行时错误: {e}")
    except Exception as e:
        print(f"意外错误: {e}")