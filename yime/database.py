# 在YinYuanInputConverter类中添加新方法
def convert_direct(self, input_text):
    """直接从音元符号查询汉字"""
    if not self._validate_input(input_text):
        return None, []

    try:
        conn = self._get_db_connection()
        cursor = conn.cursor()

        # 查询universal_map表获取直接映射
        cursor.execute("""
            SELECT hanzi, pinyin
            FROM universal_map
            WHERE yinjie=?""", (input_text,))
        row = cursor.fetchone()

        if row:
            return row['pinyin'], list(row['hanzi'])

        # 兼容旧版查询方式
        return self.convert(input_text)
    except Exception as e:
        print(f"直接转换错误: {str(e)}")
        return None, []

    def on_input_change(self, event: Optional[tk.Event] = None):
        """使用直接查询优化输入处理"""
    input_text = self.input_entry.get()
    self.last_input_text = input_text  # 同步轮询状态

    if not input_text:
        self.clear_display()
        return

    try:
        # 使用新的直接查询方法
        pinyin, candidates = self.converter.convert_direct(input_text)

        # 更新UI
        self.pinyin_display['text'] = pinyin if pinyin else ""
        self._update_hanzi_buttons(candidates if candidates else [])

    except Exception as e:
        self._show_error_message(f"转换错误: {str(e)}")
        self.clear_display()

"""
    CREATE TABLE frequency_adjustment (
    pinyin TEXT NOT NULL,
    hanzi TEXT NOT NULL,
    base_freq INTEGER DEFAULT 100,
    user_freq INTEGER DEFAULT 0,
    last_used TIMESTAMP,
    context_freq INTEGER DEFAULT 0,
    PRIMARY KEY (pinyin, hanzi),
    FOREIGN KEY (pinyin) REFERENCES pinyin_hanzi(pinyin)
)

CREATE TRIGGER update_frequency
AFTER INSERT ON user_input_log
FOR EACH ROW
BEGIN
    UPDATE frequency_adjustment
    SET user_freq = user_freq + 1,
        last_used = CURRENT_TIMESTAMP
    WHERE pinyin = NEW.pinyin AND hanzi = NEW.hanzi;
END;


-- 保持现有基础映射表不变
CREATE TABLE pinyin_hanzi (
    pinyin TEXT NOT NULL,
    hanzi TEXT NOT NULL,
    PRIMARY KEY (pinyin, hanzi)
);

-- 新建频率专用表（建议命名为 hanzi_frequency）
CREATE TABLE hanzi_frequency (
    pinyin TEXT NOT NULL,
    hanzi TEXT NOT NULL,
    base_freq INTEGER DEFAULT 100,  -- 基础频率
    user_freq INTEGER DEFAULT 0,    -- 用户个性化频率
    context_freq INTEGER DEFAULT 0, -- 上下文频率
    last_used TIMESTAMP,            -- 最后使用时间
    boost_factor REAL DEFAULT 1.0,  -- 临时提升系数
    PRIMARY KEY (pinyin, hanzi),
    FOREIGN KEY (pinyin, hanzi) REFERENCES pinyin_hanzi(pinyin, hanzi)
);


{
    "zhao": [
        {"hanzi": "照", "freq": 100},
        {"hanzi": "找", "freq": 80}
    ],
    "zhong": [
        {"hanzi": "中", "freq": 200},
        {"hanzi": "种", "freq": 150}
    ]
}
CREATE TABLE "拼音" (
    "编号" INTEGER PRIMARY KEY,
    "全拼" TEXT NOT NULL
);

CREATE TABLE "汉字" (
    "编号" INTEGER PRIMARY KEY,
    "字形" TEXT NOT NULL,
    "拼音编号" INTEGER,
    "拼音文本" TEXT GENERATED ALWAYS AS (
        SELECT "全拼" FROM "拼音" WHERE "编号" = "汉字"."拼音编号"
    ) STORED,  -- 或 VIRTUAL（根据数据库支持）
    FOREIGN KEY ("拼音编号") REFERENCES "拼音"("编号") ON DELETE CASCADE
);

            '拼音映射': '''
                CREATE TABLE IF NOT EXISTS "拼音映射" (
                    "编号" INTEGER PRIMARY KEY AUTOINCREMENT,
                    "数字标调拼音" TEXT NOT NULL UNIQUE,
                    "音元拼音" TEXT,
                    "标准拼音" TEXT,
                    "注音符号" TEXT,
                    "最近更新" TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            '''
            在"汉字"表中没有指向"数字标调拼音"表的"编号"字段也没有"全拼"列；
            在"数字标调拼音"表中没有指向"汉字"表的"编号"字段也没有"汉字"列；
            在"汉字数字标调拼音映射"表中有关联"拼音"表的"编号"和"数字标调拼音"表的"编号"。            我的"汉字"表中的字形字段是主键，确保每个汉字都是唯一的。            我的"拼音"表中的全拼字段是主键，确保每个拼音都是唯一的。           一个字段"拼音编号"，它是一个外键，指向"拼音"表的编号字段。这样，当"拼音"表中的记录被删除时，"汉字"表中对应的记录也会被自动删除，以保持数据的一致性。n = '''
            （引用或外键）；由汉字能不能找到拼音或由拼音能不能找到汉字？
            关键的是这个表怎么知道那个汉字编号对应哪个拼音编号？ 也就是说，怎么初始化？
"""

