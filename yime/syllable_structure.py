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

    @staticmethod
    def simplify_full_to_abbreviation(full_code) -> str:
        """
        将全拼字符串化简为简拼（合并干音部分中连续相同的音元）。

        规则（基于你的编码约束）：
        - 输入可为字符串或 list/tuple；先将每个元素归一为字符串单位（PUA 单字符或元素表示一个音元）；
        - 全拼总长为 4（首音 + 干音(3)）或 3（省略首音，仅干音3）；
        - 仅对干音（最后 3 个音元）做“相邻重复合并”：连续相同的元素合并为 1 个；
          这覆盖了三相同、前两相同或后两相同的情况；
        - 不在首音与干音边界跨越合并（即首音即使与第一个干音相同也保留）；
        - 返回合并后的字符串（每个元素已转为字符串并拼接）。

        方法名：simplify_full_to_abbreviation(full_code) -> str
        """
        if full_code is None:
            return ""

        # 归一化为元素序列（每个元素为字符串）
        if isinstance(full_code, (list, tuple)):
            seq = [str(x) for x in full_code if x is not None]
        else:
            s = str(full_code)
            seq = [ch for ch in s]  # 保持 PUA 单字符单位

        if not seq:
            return ""

        # 分割首音（如果存在）与干音部分
        if len(seq) == 4:
            head = seq[0]            # 首音
            ganyin_seq = seq[1:4]    # 干音部分（3个）
            has_head = True
        elif len(seq) == 3:
            head = None
            ganyin_seq = seq[0:3]
            has_head = False
        else:
            # 兼容性处理：若长度非 3/4，则对整个序列执行相邻合并（但不跨首音边界）
            # 视第一个元素为首音（如果长度>3），其余为干音
            head = seq[0] if len(seq) > 1 else None
            ganyin_seq = seq[1:] if len(seq) > 1 else []
            has_head = head is not None

        # 对干音部分做相邻重复合并
        simple_ganyin = []
        prev = None
        for item in ganyin_seq:
            if prev is not None and item == prev:
                continue
            simple_ganyin.append(item)
            prev = item

        # 组合结果：保留首音（若存在），然后追加已合并的干音部分
        result_parts = []
        if has_head and head is not None:
            result_parts.append(str(head))
        result_parts.extend(str(x) for x in simple_ganyin)

        return ''.join(result_parts)

    def get_full_code(self) -> str:
        """获取完整的音节编码"""
        parts = []
        if self.initial: parts.append(self.initial)
        if self.ascender: parts.append(self.ascender)
        if self.peak: parts.append(self.peak)
        if self.descender: parts.append(self.descender)
        return ''.join(parts)

    def get_abbreviation(self) -> str:
        """获取简拼形式(使用 simplify_full_to_abbreviation 对全拼合并连续相同音元)"""
        full = self.get_full_code()
        return SyllableStructure.simplify_full_to_abbreviation(full)

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

    @staticmethod
    def from_string(pinyin: str) -> 'SyllableStructure':
        """
        根据全拼字符串构造 SyllableStructure 实例。
        你可以根据自己的分解规则完善此方法。
        """
        # 这里仅为示例，实际应按你的音元拼音结构分解
        return SyllableStructure(
            initial=pinyin[0] if len(pinyin) > 0 else None,
            ascender=pinyin[1] if len(pinyin) > 1 else None,
            peak=pinyin[2] if len(pinyin) > 2 else None,
            descender=pinyin[3] if len(pinyin) > 3 else None
        )

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
