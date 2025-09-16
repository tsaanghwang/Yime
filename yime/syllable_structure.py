# 音节分成首音和干音两段
# 干音分成呼音和韵音两段
# 韵音分成主音和末音两段
# 首音由噪音充当
# 呼音、主音和末音由乐音充当
#  噪音和乐音统称音元

class SyllableStructure:
    """
    音节类，表示汉语音节的层次结构：
    - 首音(噪音)
    - 干音
      - 呼音(乐音)
      - 韵音
        - 主音(乐音)
        - 末音(乐音)
    """

    def __init__(self, initial=None, ascender=None, peak=None, descender=None):
        """
        初始化音节对象

        参数:
            initial: 首音(噪音)
            ascender: 呼音(乐音)
            peak: 主音(乐音)
            descender: 末音(乐音)
        """
        self.initial = initial  # 首音(音节的首段)
        self.ascender = ascender    # 呼音(韵音、干音和音节的呼段——峰前段)
        self.peak = peak  # 主音(韵音、干音和音节的主段——峰值段)
        self.descender = descender        # 末音(韵音、干音和音节的末段——峰后段)

    @property
    def ganyin(self):
        """干音部分，由呼音和韵音组成"""
        return {
            'ascender': self.ascender,
            'rime': self.rime  # 引用新定义的rime属性
        }

    @property
    def rime(self):
        """韵音部分，由主音和末音组成"""
        return {
            'peak': self.peak,
            'descender': self.descender
        }

    def classify_codes(self):
        """
        分类音元为噪音和乐音
        返回: (noise_codes, musical_codes)
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
    def split_encoded_syllable(encoded_syllable):
        """
        将编码音节分割为完整的音元结构

        参数:
            encoded_syllable: 编码后的音节字符串(如"abcd")

        返回:
            SyllableStructure: 包含所有音元部分的对象
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

    def __str__(self):
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

    def simplify_codes(self):
        """
        合并连续相同的音元，返回新的Syllable实例
        规则：连续2个或3个相同音元合并为1个
        """
        # 获取当前所有音元
        codes = [
            self.initial,  # 首音
            self.ascender,  # 呼音
            self.peak,  # 主音
            self.descender  # 末音
        ]

        # 合并连续相同的音元
        simple_codes = []
        prev_codes = None
        for codes in codes:
            if codes is None:
                continue
            if codes == prev_codes:
                continue  # 跳过连续相同的音元
            simple_codes.append(codes)
            prev_codes = codes

        # 根据合并后的音元创建新实例
        # 注意：这里假设合并后的音元顺序与原始结构一致
        # 可能需要根据实际业务逻辑调整
        new_initial = simple_codes[0] if len(simple_codes) > 0 else None
        new_ascender = simple_codes[1] if len(simple_codes) > 1 else None
        new_peak = simple_codes[2] if len(simple_codes) > 2 else None
        new_descender = simple_codes[3] if len(simple_codes) > 3 else None

        return SyllableStructure(
            initial=new_initial,
            ascender=new_ascender,
            peak=new_peak,
            descender=new_descender
        )

    def to_db_dict(self):
        """
        将音节结构转换为数据库字典格式，匹配音元拼音表结构
        返回:
            dict: 包含音元拼音表所需字段的字典
        """
        return {
            '全拼': self.get_full_code(),
            '简拼': self.get_abbreviation(),
            '首音': self.initial,
            '干音': self.get_ganyin_code(),
            '呼音': self.ascender,
            '主音': self.peak,
            '末音': self.descender,
            '间音': None,  # 可根据需要补充
            '韵音': self.get_yunyin_code()
        }

    def get_full_code(self):
        """获取完整的音节编码"""
        parts = []
        if self.initial: parts.append(self.initial)
        if self.ascender: parts.append(self.ascender)
        if self.peak: parts.append(self.peak)
        if self.descender: parts.append(self.descender)
        return ''.join(parts)

    def get_abbreviation(self):
        """获取简拼形式"""
        abbrev = []
        if self.initial: abbrev.append(self.initial)
        if self.ascender or self.peak or self.descender:
            abbrev.append(self.get_ganyin_code()[0] if self.get_ganyin_code() else '')
        return ''.join(abbrev)

    def get_ganyin_code(self):
        """获取干音部分编码"""
        return (self.ascender or '') + (self.peak or '') + (self.descender or '')

    def get_yunyin_code(self):
        """获取韵音部分编码"""
        return (self.peak or '') + (self.descender or '')

    @classmethod
    def from_db_dict(cls, db_dict):
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

    def save_to_db(self, db_connection):
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
    def load_from_db(cls, db_connection, full_code):
        """
        从数据库加载音节结构
        参数:
            db_connection: SQLite数据库连接
            full_code: 全拼编码
        返回:
            SyllableStructure: 音节结构对象
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

