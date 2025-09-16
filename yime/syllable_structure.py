# -*- coding: utf-8 -*-
"""
音节结构模块
定义汉语音节的层次结构及其相关操作方法

结构层次:
- 音节
  - 首音(噪音)
  - 干音
    - 呼音(乐音)
    - 韵音
      - 主音(乐音)
      - 末音(乐音)
"""

import sqlite3
from typing import Dict, List, Optional, Tuple


class SyllableStructure:
    """表示汉语音节的层次结构及其操作方法"""

    def __init__(
        self,
        initial: Optional[str] = None,
        ascender: Optional[str] = None,
        peak: Optional[str] = None,
        descender: Optional[str] = None
    ):
        """
        初始化音节对象

        参数:
            initial: 首音(噪音)
            ascender: 呼音(乐音)
            peak: 主音(乐音)
            descender: 末音(乐音)
        """
        self.initial = initial    # 首音(音节的首段)
        self.ascender = ascender  # 呼音(韵音、干音和音节的呼段)
        self.peak = peak          # 主音(韵音、干音和音节的主段)
        self.descender = descender  # 末音(韵音、干音和音节的末段)

    # 属性访问器
    @property
    def ganyin(self) -> str:
        """获取干音部分(由呼音和韵音组成)"""
        return (self.ascender or '') + (self.peak or '') + (self.descender or '')

    @property
    def rime(self) -> Dict[str, Optional[str]]:
        """获取韵音部分(由主音和末音组成)"""
        return {
            'peak': self.peak,
            'descender': self.descender
        }

    # 核心方法
    def classify_codes(self) -> Tuple[List[str], List[str]]:
        """分类音元为噪音和乐音

        返回:
            tuple: (noise_codes, musical_codes)
        """
        noise_codes = []
        musical_codes = []

        if self.initial:
            noise_codes.append(self.initial)
        if self.ascender:
            musical_codes.append(self.ascender)
        if self.peak:
            musical_codes.append(self.peak)
        if self.descender:
            musical_codes.append(self.descender)

        return noise_codes, musical_codes

    @staticmethod
    def split_encoded_syllable(encoded_syllable: str) -> 'SyllableStructure':
        """
        将编码音节分割为完整的音元结构

        参数:
            encoded_syllable: 编码后的音节字符串(如"abcd")

        返回:
            SyllableStructure: 包含所有音元部分的对象

        异常:
            ValueError: 如果输入无效
        """
        if not encoded_syllable:
            raise ValueError("编码音节不能为空")

        # 分割首音和干音
        initial = encoded_syllable[0] if len(encoded_syllable) > 0 else None
        ganyin = encoded_syllable[1:] if len(encoded_syllable) > 1 else ""

        # 分割呼音和韵音
        ascender = ganyin[0] if len(ganyin) > 0 else None
        yunyin = ganyin[1:] if len(ganyin) > 1 else ""

        # 分割韵音为主音和末音
        peak = yunyin[0] if len(yunyin) > 0 else None
        descender = yunyin[1:] if len(yunyin) > 1 else None

        return SyllableStructure(
            initial=initial,
            ascender=ascender,
            peak=peak,
            descender=descender
        )

    def simplify_codes(self) -> 'SyllableStructure':
        """合并连续相同的音元，返回新的Syllable实例

        规则:
            - 连续2个或3个相同音元合并为1个
        """
        codes = [
            self.initial,
            self.ascender,
            self.peak,
            self.descender
        ]

        simple_codes = []
        prev_code = None
        for code in codes:
            if code is None:
                continue
            if code == prev_code:
                continue
            simple_codes.append(code)
            prev_code = code

        return SyllableStructure(
            initial=simple_codes[0] if len(simple_codes) > 0 else None,
            ascender=simple_codes[1] if len(simple_codes) > 1 else None,
            peak=simple_codes[2] if len(simple_codes) > 2 else None,
            descender=simple_codes[3] if len(simple_codes) > 3 else None
        )

    # 数据库操作方法
    def to_db_dict(self) -> Dict[str, Optional[str]]:
        """
        将音节结构转换为数据库字典格式，匹配音元拼音表结构
        返回:
            dict: 包含音元拼音表所需字段的字典
        """
        simplified = self.simplify_codes()
        return {
            '全拼': self.get_full_code(),
            '简拼': simplified.get_full_code(),  # 使用简化后的完整编码作为简拼
            '首音': self.initial,
            '干音': self.get_ganyin_code(),
            '呼音': self.ascender,
            '主音': self.peak,
            '末音': self.descender,
            '间音': self.get_jianyin_code(),
            '韵音': self.get_yunyin_code()
        }

    def get_full_code(self) -> str:
        """获取完整的音节编码"""
        parts = []
        if self.initial: parts.append(self.initial)
        if self.ascender: parts.append(self.ascender)
        if self.peak: parts.append(self.peak)
        if self.descender: parts.append(self.descender)
        return ''.join(parts)

    def get_abbreviation(self) -> str:
        """获取简拼形式(直接使用simplify_codes的结果)"""
        simplified = self.simplify_codes()
        parts = []
        if simplified.initial: parts.append(simplified.initial)
        if simplified.ascender: parts.append(simplified.ascender)
        if simplified.peak: parts.append(simplified.peak)
        if simplified.descender: parts.append(simplified.descender)
        return ''.join(parts)

    def get_ganyin_code(self) -> str:
        """获取干音部分编码"""
        return (self.ascender or '') + (self.peak or '') + (self.descender or '')

    def get_jianyin_code(self) -> str:
        """获取间音部分编码(首音和末音之间的音元)

        返回:
            str: 由呼音和主音组成的字符串，如果不存在则返回空字符串
        """
        return (self.ascender or '') + (self.peak or '')

    def get_yunyin_code(self) -> str:
        """获取韵音部分编码"""
        return (self.peak or '') + (self.descender or '')

    @classmethod
    def from_db_dict(cls, db_dict: Dict) -> 'SyllableStructure':
        """
        从数据库字典创建音节结构对象
        参数:
            db_dict: 从音元拼音表查询得到的字典
        返回:
            SyllableStructure: 音节结构对象
        """
        return cls(
            initial=db_dict.get('首音'),
            ascender=db_dict.get('呼音'),
            peak=db_dict.get('主音'),
            descender=db_dict.get('末音')
        )

    def save_to_db(self, db_connection: sqlite3.Connection) -> None:
        """
        将音节结构保存到数据库
        参数:
            db_connection: SQLite数据库连接
        """
        data = self.to_db_dict()
        cursor = db_connection.cursor()
        cursor.execute("""
            INSERT OR REPLACE INTO 音元拼音 (
                全拼, 简拼, 首音, 干音, 呼音, 主音, 末音, 间音, 韵音
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, tuple(data.values()))
        db_connection.commit()

    @classmethod
    def load_from_db(
        cls,
        db_connection: sqlite3.Connection,
        full_code: str
    ) -> Optional['SyllableStructure']:
        """
        从数据库加载音节结构
        参数:
            db_connection: SQLite数据库连接
            full_code: 全拼编码
        返回:
            SyllableStructure: 音节结构对象，如果不存在则返回None
        """
        cursor = db_connection.cursor()
        cursor.execute("SELECT * FROM 音元拼音 WHERE 全拼=?", (full_code,))
        row = cursor.fetchone()
        if row:
            return cls.from_db_dict(dict(zip(
                ['编号', '全拼', '简拼', '首音', '干音', '呼音', '主音', '末音', '间音', '韵音', '最近更新'],
                row
            )))
        return None

    # 魔术方法
    def __str__(self) -> str:
        """返回音节的字符串表示"""
        parts = []
        if self.initial:
            parts.append(f"首音: {self.initial}")
        if self.ascender:
            parts.append(f"呼音: {self.ascender}")
        if self.peak:
            parts.append(f"主音: {self.peak}")
        if self.descender:
            parts.append(f"末音: {self.descender}")
        return " | ".join(parts)