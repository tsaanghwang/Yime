"""
拼音数据导入工具(专职数据导入版)

功能：
1. 专注于将字典中的两种拼音数据导入数据库的三个表
2. 不负责表结构创建，只处理数据导入
"""

import sqlite3
import json
from pathlib import Path
from typing import Dict
import logging

from utils.pinyin_normalizer import PinyinNormalizer
from utils.pinyin_zhuyin import PinyinZhuyinConverter


class 拼音数据导入器:
    """专职处理拼音数据导入的类"""

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

    def 加载JSON数据(self, json路径: str) -> Dict[str, str]:
        """加载JSON源数据"""
        json路径 = Path(json路径).absolute()
        if not json路径.exists():
            raise FileNotFoundError(f"JSON文件 {json路径} 不存在")

        with open(json路径, 'r', encoding='utf-8') as 文件:  # 将 json_path 改为 json路径
            数据 = json.load(文件)
            self.日志.debug(f"从 {json路径} 加载了 {len(数据)} 条数据")
            return 数据

    def 导入音元拼音数据(self, 音元拼音数据: Dict[str, str]) -> int:
        """导入音元拼音数据到音元拼音表，处理重复值"""
        with self._获取连接() as 连接:
            游标 = 连接.cursor()

            # 清空现有数据
            游标.execute('DELETE FROM 音元拼音')

            # 获取去重后的音元拼音值
            去重音元拼音 = set(音元拼音数据.values())

            # 批量插入数据
            游标.executemany('''
                INSERT OR IGNORE INTO 音元拼音 (全拼) VALUES (?)
            ''', [(音元拼音,) for 音元拼音 in 去重音元拼音])

            连接.commit()
            return 游标.rowcount

    def 导入数字标调拼音数据(self, 数字标调拼音数据: Dict[str, str]) -> int:
        """导入数字标调拼音数据到数字标调拼音表"""
        with self._获取连接() as 连接:
            游标 = 连接.cursor()

            # 清空现有数据
            游标.execute('DELETE FROM 数字标调拼音')

            # 批量插入数据
            游标.executemany('''
                INSERT INTO 数字标调拼音 (数字标调拼音) VALUES (?)
            ''', [(数字标调拼音,) for 数字标调拼音 in 数字标调拼音数据.keys()])

            连接.commit()
            return 游标.rowcount

    def 导入拼音映射数据(self, 映射数据: Dict[str, str]) -> int:
        """导入拼音映射数据到音元拼音已有拼音映射表"""
        with self._获取连接() as 连接:
            游标 = 连接.cursor()

            # 清空现有数据
            游标.execute('DELETE FROM 音元拼音已有拼音映射')

            # 获取所有数字标调拼音
            拼音列表 = list(映射数据.keys())

            # 处理标准拼音
            标准化字典, _ = PinyinNormalizer.process_pinyin_dict(
                {数字标调拼音: 数字标调拼音 for 数字标调拼音 in 拼音列表}
            )

            # 处理注音符号
            注音字典, _ = PinyinZhuyinConverter.process_pinyin_dict(
                {数字标调拼音: 数字标调拼音 for 数字标调拼音 in 拼音列表}
            )

            # 批量插入数据
            游标.executemany('''
                INSERT INTO 音元拼音已有拼音映射 (
                    音元拼音id, 数字标调拼音id, 标准拼音, 注音符号
                ) VALUES (
                    (SELECT id FROM 音元拼音 WHERE 全拼 = ?),
                    (SELECT id FROM 数字标调拼音 WHERE 数字标调拼音 = ?),
                    ?, ?
                )
            ''', [
                (音元拼音,
                数字标调拼音,
                标准化字典.get(数字标调拼音, 数字标调拼音),  # 使用标准化后的拼音
                注音字典.get(数字标调拼音, ""))  # 使用转换后的注音符号
                for 数字标调拼音, 音元拼音 in 映射数据.items()
            ])

            连接.commit()
            return 游标.rowcount

    def 导入所有数据(self, 映射数据: Dict[str, str]) -> Dict[str, int]:
        """导入所有拼音数据到数据库"""
        try:
            self.日志.info("开始导入拼音数据...")

            # 准备两种拼音数据
            音元拼音数据 = {k: v for k, v in 映射数据.items()}
            数字标调拼音数据 = {k: k for k in 映射数据.keys()}  # 修复了变量名错误

            结果 = {
                '音元拼音': self.导入音元拼音数据(音元拼音数据),
                '数字标调拼音': self.导入数字标调拼音数据(数字标调拼音数据),
                '拼音映射': self.导入拼音映射数据(映射数据)
            }

            self.日志.info(
                f"数据导入完成: "
                f"音元拼音={结果['音元拼音']}条, "
                f"数字标调拼音={结果['数字标调拼音']}条, "
                f"拼音映射={结果['拼音映射']}条"
            )

            return 结果

        except Exception as 错误:
            self.日志.error(f"数据导入失败: {str(错误)}")
            raise

if __name__ == '__main__':
    # 使用示例
    导入器 = 拼音数据导入器()

    # 加载音节编码数据 - 修改路径为当前目录下的文件
    映射数据 = 导入器.加载JSON数据('yinjie_code.json')

    # 实际导入
    结果 = 导入器.导入所有数据(映射数据)
    print(f"导入结果: {结果}")