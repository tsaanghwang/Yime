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

-- 单字链路使用全英文隔离表，避免继续依赖旧中文主表与频率表的编号体系。

CREATE TABLE IF NOT EXISTS char_inventory (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    hanzi TEXT NOT NULL UNIQUE,
    stroke_count INTEGER,
    radical TEXT,
    is_common_char INTEGER NOT NULL DEFAULT 1 CHECK (is_common_char IN (0, 1)),
    char_frequency_abs INTEGER,
    char_frequency_rel REAL,
    frequency_source TEXT,
    legacy_char_id INTEGER,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_char_inventory_hanzi
ON char_inventory(hanzi);

CREATE TABLE IF NOT EXISTS numeric_pinyin_inventory (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    pinyin_tone TEXT NOT NULL UNIQUE,
    initial TEXT,
    final TEXT,
    tone_number INTEGER,
    mapping_id INTEGER,
    legacy_numeric_pinyin_id INTEGER,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_numeric_pinyin_inventory_tone
ON numeric_pinyin_inventory(pinyin_tone);

CREATE TABLE IF NOT EXISTS pinyin_yime_code (
    pinyin_tone TEXT PRIMARY KEY,
    yime_code TEXT NOT NULL,
    code_source TEXT NOT NULL,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_pinyin_yime_code_yime_code
ON pinyin_yime_code(yime_code);

CREATE TABLE IF NOT EXISTS char_pinyin_map (
    char_id INTEGER NOT NULL REFERENCES char_inventory(id) ON DELETE CASCADE,
    numeric_pinyin_id INTEGER NOT NULL REFERENCES numeric_pinyin_inventory(id) ON DELETE CASCADE,
    reading_weight REAL,
    is_common_reading INTEGER NOT NULL DEFAULT 0 CHECK (is_common_reading IN (0, 1)),
    source_file TEXT,
    source_note TEXT,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (char_id, numeric_pinyin_id)
);

CREATE INDEX IF NOT EXISTS idx_char_pinyin_map_char_id
ON char_pinyin_map(char_id);

CREATE INDEX IF NOT EXISTS idx_char_pinyin_map_numeric_id
ON char_pinyin_map(numeric_pinyin_id);

-- 兼容映射面：保留 mapping_id -> yime_code，仅供旧结构兼容脚本使用。
CREATE TABLE IF NOT EXISTS mapping_yime_code (
    mapping_id INTEGER PRIMARY KEY,
    yime_code TEXT NOT NULL,
    source_pinyin_tone TEXT,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_mapping_yime_code_yime_code
ON mapping_yime_code(yime_code);

CREATE TABLE IF NOT EXISTS phrase_inventory (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    phrase TEXT NOT NULL UNIQUE,
    yime_code TEXT,
    phrase_frequency REAL,
    phrase_length INTEGER NOT NULL,
    is_common_phrase INTEGER NOT NULL DEFAULT 1 CHECK (is_common_phrase IN (0, 1)),
    legacy_phrase_id INTEGER,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_phrase_inventory_phrase
ON phrase_inventory(phrase);

CREATE TABLE IF NOT EXISTS phrase_reading_preference (
    phrase TEXT PRIMARY KEY,
    preferred_pinyin_tone TEXT NOT NULL,
    selection_reason TEXT,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (phrase) REFERENCES phrase_inventory(phrase) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_phrase_reading_preference_pinyin
ON phrase_reading_preference(preferred_pinyin_tone);

-- 词语读音映射也走英文隔离表，不再引用旧“词汇”编号体系。
CREATE TABLE IF NOT EXISTS phrase_pinyin_map (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    phrase_id INTEGER NOT NULL REFERENCES phrase_inventory(id) ON DELETE CASCADE,
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

-- 单字词库视图：完全走英文隔离表，不再依赖旧 汉字 / 数字标调拼音 / 汉字频率。
-- yime_code 通过 numeric_pinyin_inventory.pinyin_tone -> pinyin_yime_code 推导得到。
CREATE VIEW char_lexicon AS
SELECT
    scr.id AS char_id,
    scr.hanzi AS hanzi,
    scr.codepoint AS unicode_codepoint,
    ci.stroke_count AS stroke_count,
    ci.radical AS radical,
    ci.is_common_char AS is_common_char,
    npi.id AS numeric_pinyin_id,
    scr.numeric_pinyin AS pinyin_tone,
    npi.initial AS initial,
    npi.final AS final,
    npi.tone_number AS tone_number,
    COALESCE(cpm.reading_weight, CASE WHEN scr.is_primary = 1 THEN 1.0 ELSE 0.5 END) AS reading_weight,
    COALESCE(cpm.is_common_reading, scr.is_primary) AS is_common_reading,
    pyc.pinyin_tone AS yime_pinyin_id,
    pyc.yime_code AS yime_code,
    ci.char_frequency_abs AS char_frequency_abs,
    ci.char_frequency_rel AS char_frequency_rel,
    ci.frequency_source AS frequency_source,
    scr.source_name AS source_name,
    scr.marked_pinyin AS marked_pinyin,
    scr.reading_rank AS reading_rank,
    scr.comment AS source_comment,
    scr.raw_line AS source_raw_line,
    COALESCE(cpm.updated_at, ci.updated_at, npi.updated_at, CURRENT_TIMESTAMP) AS updated_at
FROM single_char_readings scr
LEFT JOIN char_inventory ci
    ON ci.hanzi = scr.hanzi
LEFT JOIN numeric_pinyin_inventory npi
    ON npi.pinyin_tone = scr.numeric_pinyin
LEFT JOIN char_pinyin_map cpm
    ON ci.id = cpm.char_id
   AND cpm.numeric_pinyin_id = npi.id
LEFT JOIN pinyin_yime_code pyc
    ON pyc.pinyin_tone = npi.pinyin_tone;

-- 词语词库视图：完全走英文隔离表，不再依赖旧“词汇”。
CREATE VIEW phrase_lexicon_view AS
SELECT
    COALESCE(pi.id, pr.id) AS phrase_id,
    pr.phrase AS phrase,
    pr.numeric_pinyin AS pinyin_tone,
    pr.reading_rank AS reading_rank,
    pi.yime_code AS yime_code,
    pi.phrase_frequency AS phrase_frequency,
    COALESCE(pi.phrase_length, LENGTH(pr.phrase)) AS phrase_length,
    COALESCE(pi.is_common_phrase, CASE WHEN pr.reading_rank = 1 THEN 1 ELSE 0 END) AS is_common_phrase,
    pr.source_name AS source_file,
    COALESCE(pr.comment, pr.raw_line) AS source_note,
    COALESCE(pi.updated_at, CURRENT_TIMESTAMP) AS updated_at
FROM phrase_readings pr
LEFT JOIN phrase_inventory pi
    ON pi.phrase = pr.phrase
LEFT JOIN phrase_reading_preference pref
    ON pref.phrase = pr.phrase
WHERE pref.phrase IS NULL OR pref.preferred_pinyin_tone = pr.numeric_pinyin;

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
    ('prototype_schema', 'v4', '测试原型附加表结构版本', CURRENT_TIMESTAMP),
    ('char_inventory_table', 'char_inventory', '当前原型单字主表（英文隔离表）', CURRENT_TIMESTAMP),
    ('numeric_pinyin_inventory_table', 'numeric_pinyin_inventory', '当前原型数字标调拼音主表（英文隔离表）', CURRENT_TIMESTAMP),
    ('pinyin_yime_code_table', 'pinyin_yime_code', '当前原型 canonical 拼音到 yime_code 映射表；主线不再依赖 mapping_id', CURRENT_TIMESTAMP),
    ('char_numeric_map_table', 'char_pinyin_map', '当前原型单字到数字标调拼音映射表（英文隔离表）', CURRENT_TIMESTAMP),
    ('phrase_inventory_table', 'phrase_inventory', '当前原型词语主表（英文隔离表）', CURRENT_TIMESTAMP),
    ('phrase_reading_preference_table', 'phrase_reading_preference', '歧义词显式默认读音表；runtime 仅暴露默认读音', CURRENT_TIMESTAMP),
    ('char_source_strategy', 'clone_source_single_char_readings', '单字相关先复制 source_pinyin.db.single_char_readings，再派生 char_lexicon', CURRENT_TIMESTAMP),
    ('phrase_source_strategy', 'clone_source_phrase_readings', '词语相关先复制 source_pinyin.db.phrase_readings，再派生 phrase_lexicon_view', CURRENT_TIMESTAMP);
