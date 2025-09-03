# convert_pinyin_to_hanzi.py
import sqlite3
import json
from pathlib import Path
from functools import lru_cache

class YinYuanInputConverter:
    def __init__(self, db_path=None):
        """初始化转换器，完全基于数据库"""
        base_dir = Path(__file__).parent
        self.db_path = Path(db_path) if db_path else base_dir / "pinyin_hanzi.db"

        if not self.db_path.exists():
            raise FileNotFoundError(f"数据库文件不存在: {self.db_path}")

        self.db_conn = None
        self._initialize_database_tables()

    def _get_db_connection(self):
        """获取数据库连接(单例模式)"""
        if self.db_conn is None:
            self.db_conn = sqlite3.connect(self.db_path)
            self.db_conn.row_factory = sqlite3.Row
        return self.db_conn

    def _initialize_database_tables(self):
        """确保数据库表存在"""
        conn = self._get_db_connection()
        c = conn.cursor()

        # 检查表是否存在，如果不存在则创建
        c.execute("""
        CREATE TABLE IF NOT EXISTS yinyuan_map (
            yinjie TEXT PRIMARY KEY,
            number_tones TEXT,
            tone_marks TEXT,
            zhuyin TEXT
        )
        """)

        c.execute("""
        CREATE TABLE IF NOT EXISTS universal_map (
            pinyin TEXT PRIMARY KEY,
            hanzi TEXT,
            yinjie TEXT,
            variants TEXT
        )
        """)

        conn.commit()

    @lru_cache(maxsize=5000)
    def _load_pinyin_hanzi(self, pinyin):
        """从数据库加载拼音对应的汉字"""
        conn = self._get_db_connection()
        c = conn.cursor()
        c.execute("SELECT hanzi FROM pinyin_hanzi WHERE pinyin=?", (pinyin,))
        row = c.fetchone()
        return list(row['hanzi']) if row else []

    def _load_yinyuan_mapping(self, yinjie):
        """从数据库加载音元映射"""
        conn = self._get_db_connection()
        c = conn.cursor()
        c.execute("""
        SELECT number_tones, tone_marks, zhuyin
        FROM yinyuan_map
        WHERE yinjie=?""", (yinjie,))
        row = c.fetchone()
        if row:
            return {
                '数字标调': row['number_tones'],
                '调号标调': row['tone_marks'],
                '注音符号': row['zhuyin']
            }
        return None

    # 修改 convert_pinyin_to_hanzi.py 中的 _load_universal_mapping 方法
    def _load_universal_mapping(self, pinyin):
        """优先查询pinyin_hanzi表，兼容旧版数据库"""
        conn = self._get_db_connection()
        c = conn.cursor()

        # 先尝试查询pinyin_hanzi表
        c.execute("SELECT hanzi FROM pinyin_hanzi WHERE pinyin=?", (pinyin,))
        row = c.fetchone()
        if row:
            return {
                '汉字': list(row['hanzi']),
                '音元符号': None,
                '其他形式': []
            }

        # 再尝试查询universal_map表
        c.execute("SELECT hanzi, yinjie, variants FROM universal_map WHERE pinyin=?", (pinyin,))
        row = c.fetchone()
        if row:
            return {
                '汉字': list(row['hanzi']),
                '音元符号': row['yinjie'],
                '其他形式': json.loads(row['variants']) if row['variants'] else []
            }

        return None

    # 字符验证
    def _validate_input(self, text):
        """验证输入是否包含有效字符"""
        import re
        # 基本验证规则 - 可根据需要扩展
        if re.search(r'[\uE000-\uF8FF\uF0000-\uFFFFD]', text):  # 私用区范围
            return False
        return True

    # 在convert方法开头添加验证
    def convert(self, input_text):
        """核心转换方法，完全基于数据库查询"""
        if not self._validate_input(input_text):
            return None, ["无效字符(含私用区)"]

        # 预处理：去除首尾空白，转换为小写
        input_text = input_text.strip().lower()

        # 1. 在通用映射表中查找
        universal_mapping = self._load_universal_mapping(input_text)
        if universal_mapping:
            return input_text, universal_mapping['汉字']


        # 2. 检查是否是音元符号
        conn = self._get_db_connection()
        c = conn.cursor()

        # 先检查是否是音元符号(yinjie)
        c.execute("""
        SELECT yinjie, number_tones
        FROM yinyuan_map
        WHERE yinjie=? OR number_tones=? OR tone_marks=? OR zhuyin=?""",
        (input_text, input_text, input_text, input_text))

        row = c.fetchone()
        if row:
            pinyin = row['number_tones']
            candidates = self._load_pinyin_hanzi(pinyin)
            if candidates:
                return pinyin, candidates

        # 3. 如果都没找到，返回空结果
        return None, []

    def __del__(self):
        """析构时关闭数据库连接"""
        if self.db_conn:
            self.db_conn.close()