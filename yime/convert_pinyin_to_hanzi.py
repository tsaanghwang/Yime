# convert_pinyin_to_hanzi.py
import sqlite3
from functools import lru_cache
from pathlib import Path
from typing import Optional, Tuple, List

class YinYuanInputConverter:
    def __init__(self, db_path=None):
        """初始化转换器，完全基于数据库"""
        base_dir = Path(__file__).parent
        self.db_path = Path(db_path) if db_path else base_dir / "pinyin_hanzi.db"

        if not self.db_path.exists():
            raise FileNotFoundError(f"数据库文件不存在: {self.db_path}")

        self.db_conn = None
        self._initialize_database_tables()

    def _get_db_connection(self) -> sqlite3.Connection:
        """获取数据库连接(单例模式)"""
        if self.db_conn is None:
            self.db_conn = sqlite3.connect(self.db_path)
            self.db_conn.row_factory = sqlite3.Row
        return self.db_conn

    def _initialize_database_tables(self):
        """确保所有必要的数据库表存在"""
        conn = self._get_db_connection()
        c = conn.cursor()

        # 创建音元映射表
        c.execute("""
        CREATE TABLE IF NOT EXISTS yinyuan_map (
            yinjie TEXT PRIMARY KEY,
            number_tones TEXT,
            tone_marks TEXT,
            zhuyin TEXT
        )
        """)

        # 创建拼音-汉字映射表
        c.execute("""
        CREATE TABLE IF NOT EXISTS pinyin_hanzi (
            pinyin TEXT PRIMARY KEY,
            hanzi TEXT
        )
        """)

        # 创建音元符号映射表
        c.execute("""
        CREATE TABLE IF NOT EXISTS yinjie_mapping (
            symbol TEXT PRIMARY KEY,
            num_tone TEXT,
            mark_tone TEXT,
            zhuyin TEXT
        )
        """)

        # 创建通用映射表
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
    def _load_pinyin_hanzi(self, pinyin: str) -> List[str]:
        """从数据库加载拼音对应的汉字"""
        conn = self._get_db_connection()
        c = conn.cursor()
        c.execute("SELECT hanzi FROM pinyin_hanzi WHERE pinyin=?", (pinyin,))
        row = c.fetchone()
        return list(row['hanzi']) if row else []

    def _load_yinyuan_mapping(self, yinjie: str) -> Optional[dict]:
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

    def _load_universal_mapping(self, pinyin: str) -> Optional[dict]:
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
                '其他形式': row['variants'].split(',') if row['variants'] else []
            }

        return None

    def _validate_input(self, text: str) -> bool:
        """验证输入是否包含有效字符"""
        if not text or not isinstance(text, str):
            return False
        return True

    def _pua_to_pinyin(self, pua_text):
        """改进的PUA字符转换方法"""
        if not pua_text or not isinstance(pua_text, str):
            return None

        try:
            conn = self._get_db_connection()
            c = conn.cursor()

            # 1. 先尝试完整匹配
            c.execute("SELECT mark_tone FROM yinjie_mapping WHERE symbol=?", (pua_text,))
            row = c.fetchone()
            if row:
                return row[0]

            # 2. 处理不完整输入(非4的倍数)
            pinyin_parts = []
            valid_chars = []

            # 收集所有有效PUA字符(过滤掉代理对)
            for char in pua_text:
                if 0xE000 <= ord(char) <= 0xF8FF:  # PUA范围
                    valid_chars.append(char)
                else:
                    print(f"忽略非PUA字符: {char!r}")

            # 按4字符一组处理
            for i in range(0, len(valid_chars), 4):
                quad = ''.join(valid_chars[i:i+4])
                if len(quad) < 4:
                    continue  # 忽略不完整组

                c.execute("SELECT mark_tone FROM yinjie_mapping WHERE symbol=?", (quad,))
                quad_row = c.fetchone()
                if quad_row:
                    pinyin_parts.append(quad_row[0])

            return ''.join(pinyin_parts) if pinyin_parts else None

        except Exception as e:
            print(f"PUA转换错误: {str(e)}")
            return None

    def convert(self, input_text):
        print(f"转换输入: {input_text!r}")  # 调试日志
        try:
            pinyin = self._pua_to_pinyin(input_text)
            print(f"转换后拼音: {pinyin!r}")  # 调试日志

            if not pinyin:
                return None, []

            # 查询对应汉字 - 先尝试带调号查询
            conn = self._get_db_connection()
            c = conn.cursor()

            # 尝试带调号查询
            c.execute("""
                SELECT hanzi
                FROM pinyin_hanzi
                WHERE pinyin=?""", (pinyin,))
            row = c.fetchone()

            if not row:
                # 如果带调号查询无结果，尝试去掉调号查询
                base_pinyin = ''.join([c for c in pinyin if c.isalpha()])
                if base_pinyin != pinyin:  # 只有确实有调号时才进行二次查询
                    c.execute("""
                        SELECT hanzi
                        FROM pinyin_hanzi
                        WHERE pinyin=?""", (base_pinyin,))
                    row = c.fetchone()
                    if row:
                        # 返回带调号的拼音和候选汉字
                        return pinyin, list(row[0])

            if row:
                return pinyin, list(row[0])  # 将汉字字符串转为字符列表

            return pinyin, []

        except Exception as e:
            print(f"转换错误: {str(e)}")
            return None, []        # 注意：这里移除了conn.close()，因为连接由类统一管理

    def __del__(self):
        """析构时关闭数据库连接"""
        if self.db_conn:
            self.db_conn.close()