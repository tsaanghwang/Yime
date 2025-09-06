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
"""

