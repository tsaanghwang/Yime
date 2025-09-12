"""
拼音编码映射工具(面向对象重构版)

功能：
1. 封装SQLite数据库操作
2. 提供数据导入和查询接口
3. 支持编码与拼音的双向映射
"""

import sqlite3
import json
from pathlib import Path
from collections import defaultdict
from typing import List, Dict, Optional, Tuple, Iterator
import logging

class 拼音映射器:
    """拼音编码映射核心类"""

    def __init__(self, 数据库路径: str = 'pinyin_hanzi.db'):
        """初始化数据库连接路径"""
        self.数据库路径 = Path(数据库路径).absolute()
        self._配置日志()

    def _配置日志(self):
        """配置日志记录"""
        logging.basicConfig(
            level=logging.DEBUG,
            format='%(asctime)s - %(levelname)s - %(message)s'
        )
        self.日志 = logging.getLogger(__name__)

    def _获取连接(self) -> sqlite3.Connection:
        """获取数据库连接"""
        连接 = sqlite3.connect(str(self.数据库路径))
        连接.row_factory = sqlite3.Row
        return 连接

    def 初始化数据库(self) -> None:
        """初始化数据库表结构"""
        with self._获取连接() as 连接:
            游标 = 连接.cursor()

            # 创建音元拼音表
            游标.execute('''
            CREATE TABLE IF NOT EXISTS 音元拼音 (
                id INTEGER PRIMARY KEY,
                全拼 TEXT NOT NULL UNIQUE,
                简拼 TEXT,
                首音 TEXT,
                干音 TEXT,
                呼音 TEXT,
                主音 TEXT,
                末音 TEXT,
                间音 TEXT,
                韵音 TEXT,
                创建时间 TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )''')

            # 创建音元拼音_数字标调拼音表
            游标.execute('''
            CREATE TABLE IF NOT EXISTS 音元拼音_数字标调拼音 (
                音元_id INTEGER REFERENCES 音元拼音(id),
                拼音_id INTEGER REFERENCES 拼音(id),
                标准拼音 TEXT NOT NULL,
                注音符号 TEXT NOT NULL,
                PRIMARY KEY (音元_id, 拼音_id)
            )''')

            # 创建编码到拼音映射表
            游标.execute('''
            CREATE TABLE IF NOT EXISTS 编码到拼音 (
                id INTEGER PRIMARY KEY,
                编码 TEXT NOT NULL,
                拼音 TEXT NOT NULL
            )''')

            # 创建拼音到编码映射表
            游标.execute('''
            CREATE TABLE IF NOT EXISTS 拼音到编码 (
                id INTEGER PRIMARY KEY,
                拼音 TEXT NOT NULL,
                编码 TEXT NOT NULL
            )''')

            # 创建索引
            游标.execute('CREATE INDEX IF NOT EXISTS 音元拼音_全拼索引 ON 音元拼音(全拼)')
            游标.execute('CREATE UNIQUE INDEX IF NOT EXISTS 音元拼音_全拼唯一索引 ON 音元拼音(全拼)')
            游标.execute('CREATE INDEX IF NOT EXISTS 音元拼音_数字标调拼音_音元_id ON 音元拼音_数字标调拼音(音元_id)')
            游标.execute('CREATE INDEX IF NOT EXISTS 音元拼音_数字标调拼音_拼音_id ON 音元拼音_数字标调拼音(拼音_id)')
            游标.execute('CREATE UNIQUE INDEX IF NOT EXISTS 音元拼音_数字标调拼音_音元_id_拼音_id ON 音元拼音_数字标调拼音(音元_id, 拼音_id)')
            游标.execute('CREATE INDEX IF NOT EXISTS 编码到拼音_编码 ON 编码到拼音(编码)')
            游标.execute('CREATE INDEX IF NOT EXISTS 拼音到编码_拼音 ON 拼音到编码(拼音)')

            连接.commit()
            self.日志.debug("数据库表结构初始化完成")

    def 加载JSON数据(self, json路径: str) -> Dict[str, str]:
        """加载JSON源数据"""
        json路径 = Path(json路径).absolute()
        if not json路径.exists():
            raise FileNotFoundError(f"JSON文件 {json路径} 不存在")

        with open(json路径, 'r', encoding='utf-8') as 文件:
            数据 = json.load(文件)
            self.日志.debug(f"从 {json路径} 加载了 {len(数据)} 条数据到数据库 {self.数据库路径} 中")
            return 数据

    def 标准化数据(self, 音节数据: Dict[str, str]) -> Tuple[Dict, Dict]:
        """标准化数据为两种映射关系"""
        编码映射 = defaultdict(list)
        拼音映射 = defaultdict(list)

        for 拼音, 编码 in 音节数据.items():
            编码映射[编码].append(拼音)
            拼音映射[拼音].append(编码)

        self.日志.debug(f"标准化数据完成: {len(编码映射)}唯一编码, 共{sum(len(v) for v in 编码映射.values())}条编码-拼音映射")
        self.日志.info(f"数据库更新完成: 保存了{sum(len(v) for v in 编码映射.values())}条映射关系: ({len(编码映射)}个编码对应{sum(len(v) for v in 编码映射.values())}个拼音)")
        return 编码映射, 拼音映射

    def 导入数据(self, json路径: str) -> Tuple[Dict, Dict]:
        """导入数据到数据库"""
        try:
            # 初始化数据库
            self.初始化数据库()

            # 加载并处理数据
            音节数据 = self.加载JSON数据(json路径)
            编码映射, 拼音映射 = self.标准化数据(音节数据)

            with self._获取连接() as 连接:
                游标 = 连接.cursor()

                # 清空现有数据
                游标.execute('DELETE FROM 编码到拼音')
                游标.execute('DELETE FROM 拼音到编码')

                # 批量导入数据
                游标.executemany(
                    'INSERT INTO 编码到拼音 (编码, 拼音) VALUES (?, ?)',
                    ((编码, 拼音) for 编码, 拼音列表 in 编码映射.items() for 拼音 in 拼音列表)
                )

                游标.executemany(
                    'INSERT INTO 拼音到编码 (拼音, 编码) VALUES (?, ?)',
                    ((拼音, 编码) for 拼音, 编码列表 in 拼音映射.items() for 编码 in 编码列表)
                )

                连接.commit()
                self.日志.info(
                    f"数据导入完成: {len(编码映射)}编码 → {sum(len(v) for v in 拼音映射.values())}拼音映射"
                )

            return 编码映射, 拼音映射

        except Exception as 错误:
            self.日志.error(f"数据导入失败: {str(错误)}")
            raise

    def 查询(self, 表名: str, 条件: str = None, 参数: tuple = None) -> List[Dict]:
        """通用查询接口"""
        with self._获取连接() as 连接:
            查询语句 = f"SELECT * FROM {表名}"
            if 条件:
                查询语句 += f" WHERE {条件}"

            游标 = 连接.cursor()
            游标.execute(查询语句, 参数 or ())
            return [dict(行) for 行 in 游标.fetchall()]

    def _显示字符(self, 字符):
        """辅助函数：直接返回字符本身而不是Unicode转义序列"""
        return 字符 if 字符 else ''

    def _显示编码列表(self, 编码列表):
        """改进的编码列表显示方法"""
        if not 编码列表:
            return "[]"
        return "[" + ", ".join(f"'{self._显示字符(编码)}'" for 编码 in 编码列表) + "]"

    def 根据编码获取拼音(self, 编码: str) -> List[str]:
        """根据编码获取拼音列表"""
        return [行['拼音'] for 行 in self.查询('编码到拼音', '编码 = ?', (编码,))]

    def 根据编码获取格式化拼音(self, 编码: str) -> str:
        """获取格式化显示的拼音列表(用于打印)"""
        拼音列表 = self.根据编码获取拼音(编码)
        return self._显示编码列表(拼音列表)

    def 根据拼音获取编码(self, 拼音: str) -> List[str]:
        """根据拼音获取编码列表"""
        return [行['编码'] for 行 in self.查询('拼音到编码', '拼音 = ?', (拼音,))]

    def 根据拼音获取格式化编码(self, 拼音: str) -> str:
        """获取格式化显示的编码列表(用于打印)"""
        编码列表 = self.根据拼音获取编码(拼音)
        return self._显示编码列表(编码列表)

if __name__ == '__main__':
    # 使用示例
    映射器 = 拼音映射器()
    编码映射, 拼音映射 = 映射器.导入数据('yinjie_code.json')

    # 查询示例
    print("编码'􀀇􀀢􀀢􀀢'对应的拼音:", 映射器.根据编码获取格式化拼音('􀀇􀀢􀀢􀀢'))  # 修改这里
    print("拼音'ni3'对应的编码:", 映射器.根据拼音获取格式化编码('ni3'))