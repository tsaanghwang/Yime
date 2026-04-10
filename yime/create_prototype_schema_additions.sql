PRAGMA foreign_keys = ON;

-- 原型元数据表：记录这套测试原型的版本、来源和备注。
CREATE TABLE IF NOT EXISTS prototype_metadata (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    note TEXT,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- 说明：以下中文表直接复用当前库中“已有但无数据、结构可用”的表。
-- 1. "汉字"：单字主表
-- 2. "汉字数字标调拼音映射"：汉字到数字标调拼音的映射
-- 3. "汉字音元拼音映射"：汉字到音元拼音/编码的映射
-- 4. "汉字频率"：汉字频率
-- 5. "词汇"：词语主表，复用其 词语/音元拼音/频率/长度 结构

-- 现有“词汇”表缺少数字标调拼音与读音序位，因此补一张英文映射表。
CREATE TABLE IF NOT EXISTS phrase_pinyin_map (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    phrase_id INTEGER NOT NULL REFERENCES "词汇"("编号") ON DELETE CASCADE,
    pinyin_tone TEXT NOT NULL,
    reading_rank INTEGER NOT NULL DEFAULT 1,
    source_file TEXT,
    source_note TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(phrase_id, pinyin_tone)
);

CREATE INDEX IF NOT EXISTS idx_phrase_pinyin_map_phrase_id
ON phrase_pinyin_map(phrase_id);

CREATE INDEX IF NOT EXISTS idx_phrase_pinyin_map_pinyin
ON phrase_pinyin_map(pinyin_tone);

-- 单字词库视图：把现有中文表整理成输入系统更容易理解的英文列名。
-- yime_code 优先通过 数字标调拼音.映射编号 -> 音元拼音 推导得到。
CREATE VIEW IF NOT EXISTS char_lexicon AS
SELECT
    h."编号" AS char_id,
    h."字符" AS hanzi,
    h."Unicode码点" AS unicode_codepoint,
    h."画数" AS stroke_count,
    h."部首" AS radical,
    h."是否常用" AS is_common_char,
    dp."编号" AS numeric_pinyin_id,
    dp."全拼" AS pinyin_tone,
    dp."声母" AS initial,
    dp."韵母" AS final,
    dp."声调" AS tone_number,
    hnm."频率" AS reading_weight,
    hnm."常用读音" AS is_common_reading,
    yp."编号" AS yime_pinyin_id,
    yp."全拼" AS yime_code,
    hf."绝对频率" AS char_frequency_abs,
    hf."相对频率" AS char_frequency_rel,
    hf."语料来源" AS frequency_source,
    h."最近更新" AS updated_at
FROM "汉字" h
LEFT JOIN "汉字数字标调拼音映射" hnm
    ON h."编号" = hnm."汉字编号"
LEFT JOIN "数字标调拼音" dp
    ON hnm."数字标调拼音编号" = dp."编号"
LEFT JOIN "音元拼音" yp
    ON yp."映射编号" = dp."映射编号"
LEFT JOIN "汉字频率" hf
    ON h."编号" = hf."汉字编号";

-- 词语词库视图：复用现有“词汇”表，并通过 phrase_pinyin_map 补足数字标调拼音。
CREATE VIEW IF NOT EXISTS phrase_lexicon_view AS
SELECT
    w."编号" AS phrase_id,
    w."词语" AS phrase,
    ppm.pinyin_tone AS pinyin_tone,
    ppm.reading_rank AS reading_rank,
    w."音元拼音" AS yime_code,
    w."频率" AS phrase_frequency,
    w."长度" AS phrase_length,
    w."常用词语" AS is_common_phrase,
    ppm.source_file AS source_file,
    ppm.source_note AS source_note,
    w."最近更新" AS updated_at
FROM "词汇" w
LEFT JOIN phrase_pinyin_map ppm
    ON w."编号" = ppm.phrase_id;

-- 统一候选视图：把单字和词语候选整理成统一结构，便于输入系统后续直接查询或导出 JSON。
CREATE VIEW IF NOT EXISTS runtime_candidates AS
SELECT
    'char' AS entry_type,
    CAST(char_id AS TEXT) AS entry_id,
    hanzi AS text,
    pinyin_tone,
    yime_code,
    COALESCE(char_frequency_rel, char_frequency_abs, reading_weight, 1.0) AS sort_weight,
    is_common_reading AS is_common,
    1 AS text_length,
    updated_at
FROM char_lexicon
UNION ALL
SELECT
    'phrase' AS entry_type,
    CAST(phrase_id AS TEXT) AS entry_id,
    phrase AS text,
    pinyin_tone,
    yime_code,
    COALESCE(phrase_frequency, 1.0) AS sort_weight,
    is_common_phrase AS is_common,
    phrase_length AS text_length,
    updated_at
FROM phrase_lexicon_view;

-- 写入原型元数据标记。
INSERT OR REPLACE INTO prototype_metadata (key, value, note, updated_at)
VALUES
    ('prototype_schema', 'v1', '测试原型附加表结构版本', CURRENT_TIMESTAMP),
    ('char_source_strategy', 'reuse_existing_chinese_tables', '单字相关直接复用现有中文表', CURRENT_TIMESTAMP),
    ('phrase_source_strategy', 'reuse_词汇_plus_phrase_pinyin_map', '词语主表复用现有词汇表，数字标调拼音放在 phrase_pinyin_map', CURRENT_TIMESTAMP);
