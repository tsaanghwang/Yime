PRAGMA foreign_keys = ON;

DROP VIEW IF EXISTS runtime_candidates;
DROP VIEW IF EXISTS phrase_lexicon_view;
DROP VIEW IF EXISTS char_lexicon;

-- 原型元数据表：记录这套测试原型的版本、来源和备注。
CREATE TABLE IF NOT EXISTS prototype_metadata (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    note TEXT,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS source_files (
    source_name TEXT PRIMARY KEY,
    source_kind TEXT NOT NULL CHECK (source_kind IN ('single_char', 'phrase')),
    source_path TEXT NOT NULL,
    imported_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS single_char_readings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source_name TEXT NOT NULL REFERENCES source_files(source_name) ON DELETE CASCADE,
    codepoint TEXT NOT NULL,
    hanzi TEXT NOT NULL,
    marked_pinyin TEXT NOT NULL,
    numeric_pinyin TEXT NOT NULL,
    reading_rank INTEGER NOT NULL,
    is_primary INTEGER NOT NULL DEFAULT 0 CHECK (is_primary IN (0, 1)),
    comment TEXT,
    raw_line TEXT NOT NULL,
    UNIQUE (source_name, codepoint, marked_pinyin)
);

CREATE INDEX IF NOT EXISTS idx_single_char_readings_hanzi ON single_char_readings(hanzi);
CREATE INDEX IF NOT EXISTS idx_single_char_readings_numeric ON single_char_readings(numeric_pinyin);
CREATE INDEX IF NOT EXISTS idx_single_char_readings_codepoint ON single_char_readings(codepoint);

CREATE TABLE IF NOT EXISTS phrase_readings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source_name TEXT NOT NULL REFERENCES source_files(source_name) ON DELETE CASCADE,
    phrase TEXT NOT NULL,
    marked_pinyin TEXT NOT NULL,
    numeric_pinyin TEXT NOT NULL,
    reading_rank INTEGER NOT NULL,
    comment TEXT,
    raw_line TEXT NOT NULL,
    UNIQUE (source_name, phrase, marked_pinyin)
);

CREATE INDEX IF NOT EXISTS idx_phrase_readings_phrase ON phrase_readings(phrase);
CREATE INDEX IF NOT EXISTS idx_phrase_readings_numeric ON phrase_readings(numeric_pinyin);

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
CREATE VIEW char_lexicon AS
SELECT
    scr.id AS char_id,
    scr.hanzi AS hanzi,
    scr.codepoint AS unicode_codepoint,
    h."画数" AS stroke_count,
    h."部首" AS radical,
    h."是否常用" AS is_common_char,
    dp."编号" AS numeric_pinyin_id,
    scr.numeric_pinyin AS pinyin_tone,
    dp."声母" AS initial,
    dp."韵母" AS final,
    dp."声调" AS tone_number,
    COALESCE(hnm."频率", CASE WHEN scr.is_primary = 1 THEN 1.0 ELSE 0.5 END) AS reading_weight,
    COALESCE(hnm."常用读音", scr.is_primary) AS is_common_reading,
    yp."编号" AS yime_pinyin_id,
    yp."全拼" AS yime_code,
    hf."绝对频率" AS char_frequency_abs,
    hf."相对频率" AS char_frequency_rel,
    hf."语料来源" AS frequency_source,
    scr.source_name AS source_name,
    scr.marked_pinyin AS marked_pinyin,
    scr.reading_rank AS reading_rank,
    scr.comment AS source_comment,
    scr.raw_line AS source_raw_line,
    h."最近更新" AS updated_at
FROM single_char_readings scr
LEFT JOIN "汉字" h
    ON h."字符" = scr.hanzi
LEFT JOIN "数字标调拼音" dp
    ON dp."全拼" = scr.numeric_pinyin
LEFT JOIN "汉字数字标调拼音映射" hnm
    ON h."编号" = hnm."汉字编号"
   AND hnm."数字标调拼音编号" = dp."编号"
LEFT JOIN "音元拼音" yp
    ON yp."映射编号" = dp."映射编号"
LEFT JOIN "汉字频率" hf
    ON h."编号" = hf."汉字编号";

-- 词语词库视图：先复制 source_pinyin.db.phrase_readings，
-- 再按词语文本左连现有“词汇”表复用频率、长度和音元拼音。
CREATE VIEW phrase_lexicon_view AS
WITH ranked_words AS (
    SELECT
        w."编号",
        w."词语",
        w."音元拼音",
        w."频率",
        w."长度",
        w."常用词语",
        w."最近更新",
        ROW_NUMBER() OVER (
            PARTITION BY w."词语"
            ORDER BY COALESCE(w."频率", 0.0) DESC, w."编号"
        ) AS row_rank
    FROM "词汇" w
),
chosen_words AS (
    SELECT
        "编号",
        "词语",
        "音元拼音",
        "频率",
        "长度",
        "常用词语",
        "最近更新"
    FROM ranked_words
    WHERE row_rank = 1
)
SELECT
    COALESCE(w."编号", pr.id) AS phrase_id,
    pr.phrase AS phrase,
    pr.numeric_pinyin AS pinyin_tone,
    pr.reading_rank AS reading_rank,
    w."音元拼音" AS yime_code,
    w."频率" AS phrase_frequency,
    COALESCE(w."长度", LENGTH(pr.phrase)) AS phrase_length,
    COALESCE(w."常用词语", CASE WHEN pr.reading_rank = 1 THEN 1 ELSE 0 END) AS is_common_phrase,
    pr.source_name AS source_file,
    COALESCE(pr.comment, pr.raw_line) AS source_note,
    COALESCE(w."最近更新", CURRENT_TIMESTAMP) AS updated_at
FROM phrase_readings pr
LEFT JOIN chosen_words w
    ON w."词语" = pr.phrase;

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
    ('prototype_schema', 'v3', '测试原型附加表结构版本', CURRENT_TIMESTAMP),
    ('char_source_strategy', 'clone_source_single_char_readings', '单字相关先复制 source_pinyin.db.single_char_readings，再派生 char_lexicon', CURRENT_TIMESTAMP),
    ('phrase_source_strategy', 'clone_source_phrase_readings', '词语相关先复制 source_pinyin.db.phrase_readings，再派生 phrase_lexicon_view', CURRENT_TIMESTAMP);
