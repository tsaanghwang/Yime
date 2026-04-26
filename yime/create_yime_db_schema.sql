PRAGMA foreign_keys = ON;

-- yime.db observation schema
-- SQLite does not preserve native table/column comments, so Chinese comments
-- are stored in schema_comment for inspection in SQLTools.

DROP VIEW IF EXISTS vw_klc_layout_observation;
DROP VIEW IF EXISTS vw_klc_layout_observation_all;
DROP VIEW IF EXISTS vw_symbol_crosswalk;
DROP VIEW IF EXISTS vw_symbol_inventory;
DROP VIEW IF EXISTS vw_key_symbol_layout;
DROP VIEW IF EXISTS vw_entry_encoding_detail;

DROP TABLE IF EXISTS key_symbol_map;
DROP TABLE IF EXISTS symbol;

CREATE TABLE IF NOT EXISTS db_meta (
    meta_key TEXT PRIMARY KEY,
    meta_value TEXT NOT NULL,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS schema_comment (
    object_type TEXT NOT NULL,
    object_name TEXT NOT NULL,
    column_name TEXT,
    comment_zh TEXT NOT NULL,
    PRIMARY KEY (object_type, object_name, column_name)
);

CREATE TABLE IF NOT EXISTS physical_key (
    key_id INTEGER PRIMARY KEY AUTOINCREMENT,
    key_code TEXT NOT NULL UNIQUE,
    ahk_key_name TEXT NOT NULL UNIQUE,
    key_group TEXT NOT NULL CHECK (key_group IN ('base', 'shift')),
    display_label TEXT NOT NULL,
    display_order INTEGER NOT NULL,
    is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1))
);

CREATE TABLE IF NOT EXISTS symbol (
    symbol_id TEXT PRIMARY KEY,
    source_symbol_key TEXT UNIQUE,
    slot_key TEXT UNIQUE,
    slot_number INTEGER UNIQUE,
    symbol_category TEXT CHECK (symbol_category IN ('initial', 'musical')),
    yinyuan_label TEXT,
    pua_char TEXT NOT NULL UNIQUE,
    codepoint_hex TEXT NOT NULL UNIQUE,
    canonical_char TEXT UNIQUE,
    canonical_codepoint_hex TEXT UNIQUE,
    sort_order INTEGER NOT NULL UNIQUE,
    symbol_name_zh TEXT,
    notes_zh TEXT
);

CREATE TABLE IF NOT EXISTS key_symbol_map (
    mapping_id INTEGER PRIMARY KEY AUTOINCREMENT,
    key_id INTEGER NOT NULL,
    symbol_id TEXT NOT NULL,
    map_layer TEXT NOT NULL DEFAULT 'default',
    UNIQUE (key_id, map_layer),
    FOREIGN KEY (key_id) REFERENCES physical_key(key_id) ON DELETE CASCADE,
    FOREIGN KEY (symbol_id) REFERENCES symbol(symbol_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS klc_layout_source (
    layout_id INTEGER PRIMARY KEY AUTOINCREMENT,
    scan_code TEXT NOT NULL,
    vk_name TEXT NOT NULL,
    cap_state TEXT,
    state_0_token TEXT,
    state_1_token TEXT,
    state_2_token TEXT,
    state_6_token TEXT,
    state_0_char TEXT,
    state_1_char TEXT,
    state_2_char TEXT,
    state_6_char TEXT,
    comment_text TEXT,
    source_file TEXT NOT NULL,
    UNIQUE (scan_code, vk_name, source_file)
);

CREATE TABLE IF NOT EXISTS lexicon_entry (
    entry_id INTEGER PRIMARY KEY AUTOINCREMENT,
    surface_text TEXT NOT NULL,
    entry_type TEXT NOT NULL CHECK (entry_type IN ('character', 'word', 'phrase')),
    char_count INTEGER NOT NULL DEFAULT 1,
    source_tag TEXT,
    is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS entry_pronunciation (
    pronunciation_id INTEGER PRIMARY KEY AUTOINCREMENT,
    entry_id INTEGER NOT NULL,
    original_pinyin TEXT NOT NULL,
    normalized_pinyin TEXT,
    syllable_count INTEGER,
    source_tag TEXT,
    FOREIGN KEY (entry_id) REFERENCES lexicon_entry(entry_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS entry_encoding (
    encoding_id INTEGER PRIMARY KEY AUTOINCREMENT,
    pronunciation_id INTEGER NOT NULL,
    symbol_sequence TEXT NOT NULL,
    pua_sequence TEXT,
    encoding_version TEXT NOT NULL DEFAULT 'v1',
    is_primary INTEGER NOT NULL DEFAULT 1 CHECK (is_primary IN (0, 1)),
    sort_priority INTEGER NOT NULL DEFAULT 0,
    notes_zh TEXT,
    UNIQUE (pronunciation_id, symbol_sequence),
    FOREIGN KEY (pronunciation_id) REFERENCES entry_pronunciation(pronunciation_id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_physical_key_group_order
    ON physical_key(key_group, display_order);

CREATE INDEX IF NOT EXISTS idx_key_symbol_map_symbol
    ON key_symbol_map(symbol_id);

CREATE INDEX IF NOT EXISTS idx_lexicon_entry_surface
    ON lexicon_entry(surface_text);

CREATE INDEX IF NOT EXISTS idx_entry_pronunciation_entry
    ON entry_pronunciation(entry_id);

CREATE INDEX IF NOT EXISTS idx_entry_pronunciation_pinyin
    ON entry_pronunciation(normalized_pinyin);

CREATE INDEX IF NOT EXISTS idx_entry_encoding_symbol_sequence
    ON entry_encoding(symbol_sequence);

DROP VIEW IF EXISTS vw_entry_encoding_detail;

CREATE VIEW vw_entry_encoding_detail AS
SELECT
    le.entry_id,
    le.surface_text,
    le.entry_type,
    ep.pronunciation_id,
    ep.original_pinyin,
    ep.normalized_pinyin,
    ee.encoding_id,
    ee.symbol_sequence,
    ee.pua_sequence,
    ee.encoding_version,
    ee.is_primary,
    ee.sort_priority
FROM lexicon_entry AS le
JOIN entry_pronunciation AS ep
    ON ep.entry_id = le.entry_id
JOIN entry_encoding AS ee
    ON ee.pronunciation_id = ep.pronunciation_id;

DROP VIEW IF EXISTS vw_key_symbol_layout;

CREATE VIEW vw_key_symbol_layout AS
SELECT
    pk.key_id,
    pk.key_code,
    pk.ahk_key_name,
    pk.key_group,
    pk.display_label,
    pk.display_order,
    ksm.map_layer,
    s.symbol_id,
    s.source_symbol_key,
    s.slot_key,
    s.slot_number,
    s.symbol_category,
    s.yinyuan_label,
    s.pua_char,
    s.codepoint_hex,
    s.canonical_char,
    s.canonical_codepoint_hex,
    s.sort_order,
    s.symbol_name_zh
FROM physical_key AS pk
LEFT JOIN key_symbol_map AS ksm
    ON ksm.key_id = pk.key_id
LEFT JOIN symbol AS s
    ON s.symbol_id = ksm.symbol_id
ORDER BY pk.display_order;

DROP VIEW IF EXISTS vw_symbol_inventory;

CREATE VIEW vw_symbol_inventory AS
SELECT
    s.symbol_id,
    s.source_symbol_key,
    s.slot_key,
    s.slot_number,
    s.symbol_category,
    s.yinyuan_label,
    s.pua_char,
    s.codepoint_hex,
    s.canonical_char,
    s.canonical_codepoint_hex,
    s.sort_order,
    s.symbol_name_zh,
    s.notes_zh,
    COUNT(ksm.mapping_id) AS mapped_key_count,
    GROUP_CONCAT(pk.display_label || ':' || ksm.map_layer, ', ') AS mapped_keys
FROM symbol AS s
LEFT JOIN key_symbol_map AS ksm
    ON ksm.symbol_id = s.symbol_id
LEFT JOIN physical_key AS pk
    ON pk.key_id = ksm.key_id
GROUP BY
    s.symbol_id,
    s.source_symbol_key,
    s.slot_key,
    s.slot_number,
    s.symbol_category,
    s.yinyuan_label,
    s.pua_char,
    s.codepoint_hex,
    s.canonical_char,
    s.canonical_codepoint_hex,
    s.sort_order,
    s.symbol_name_zh,
    s.notes_zh
ORDER BY s.sort_order, s.symbol_id;

CREATE VIEW vw_symbol_crosswalk AS
SELECT
    s.symbol_id,
    s.slot_key,
    s.slot_number,
    s.symbol_category,
    s.yinyuan_label,
    s.pua_char AS bmp_pua_char,
    s.codepoint_hex AS bmp_pua_codepoint_hex,
    s.canonical_char AS spua_b_char,
    s.canonical_codepoint_hex AS spua_b_codepoint_hex,
    s.symbol_name_zh,
    s.notes_zh,
    COUNT(ksm.mapping_id) AS mapped_key_count,
    GROUP_CONCAT(pk.display_label || ':' || ksm.map_layer, ', ') AS mapped_keys
FROM symbol AS s
LEFT JOIN key_symbol_map AS ksm
    ON ksm.symbol_id = s.symbol_id
LEFT JOIN physical_key AS pk
    ON pk.key_id = ksm.key_id
GROUP BY
    s.symbol_id,
    s.slot_key,
    s.slot_number,
    s.symbol_category,
    s.yinyuan_label,
    s.pua_char,
    s.codepoint_hex,
    s.canonical_char,
    s.canonical_codepoint_hex,
    s.symbol_name_zh,
    s.notes_zh
ORDER BY s.sort_order, s.symbol_id;

DROP VIEW IF EXISTS vw_klc_layout_observation;
DROP VIEW IF EXISTS vw_klc_layout_observation_all;

CREATE VIEW vw_klc_layout_observation_all AS
SELECT
    kls.layout_id,
    kls.scan_code,
    kls.vk_name,
    pk.key_code,
    pk.display_label,
    kls.state_0_char,
    base_map.symbol_id AS base_symbol_id,
    base_symbol.codepoint_hex AS base_codepoint_hex,
    kls.state_1_char,
    shift_map.symbol_id AS shift_symbol_id,
    kls.state_6_char,
    alt_map.symbol_id AS ctrl_alt_symbol_id,
    kls.comment_text
FROM klc_layout_source AS kls
LEFT JOIN physical_key AS pk
    ON pk.key_code = CASE kls.vk_name
        WHEN '1' THEN '1'
        WHEN '2' THEN '2'
        WHEN '3' THEN '3'
        WHEN '4' THEN '4'
        WHEN '5' THEN '5'
        WHEN '6' THEN '6'
        WHEN '7' THEN '7'
        WHEN '8' THEN '8'
        WHEN '9' THEN '9'
        WHEN '0' THEN '0'
        WHEN 'OEM_MINUS' THEN '-'
        WHEN 'OEM_PLUS' THEN '='
        WHEN 'OEM_4' THEN '['
        WHEN 'OEM_6' THEN ']'
        WHEN 'OEM_5' THEN '\'
        WHEN 'OEM_1' THEN ';'
        WHEN 'OEM_7' THEN ''''
        WHEN 'OEM_3' THEN '`'
        WHEN 'OEM_COMMA' THEN ','
        WHEN 'OEM_PERIOD' THEN '.'
        WHEN 'OEM_2' THEN '/'
        WHEN 'SPACE' THEN 'space'
        ELSE lower(kls.vk_name)
    END
LEFT JOIN symbol AS base_symbol
    ON base_symbol.pua_char = kls.state_0_char
LEFT JOIN key_symbol_map AS base_map
    ON base_map.key_id = pk.key_id AND base_map.map_layer = 'klc_base'
LEFT JOIN key_symbol_map AS shift_map
    ON shift_map.key_id = pk.key_id AND shift_map.map_layer = 'klc_shift'
LEFT JOIN key_symbol_map AS alt_map
    ON alt_map.key_id = pk.key_id AND alt_map.map_layer = 'klc_ctrl_alt';

CREATE VIEW vw_klc_layout_observation AS
SELECT
    layout_id,
    scan_code,
    vk_name,
    key_code,
    display_label,
    state_0_char,
    base_symbol_id,
    base_codepoint_hex,
    state_1_char,
    shift_symbol_id,
    state_6_char,
    ctrl_alt_symbol_id,
    comment_text
FROM vw_klc_layout_observation_all
WHERE vk_name <> 'DECIMAL'
  AND key_code IS NOT NULL;

INSERT INTO db_meta (meta_key, meta_value)
VALUES
    ('schema_name', 'yime_observation_schema'),
    ('schema_version', '1.5'),
    ('database_purpose', 'Observe Yime input data structure without importing data')
ON CONFLICT(meta_key) DO UPDATE SET
    meta_value = excluded.meta_value,
    updated_at = CURRENT_TIMESTAMP;

WITH RECURSIVE ascii(cp) AS (
    SELECT 32
    UNION ALL
    SELECT cp + 1 FROM ascii WHERE cp < 126
)
INSERT OR REPLACE INTO physical_key (key_id, key_code, ahk_key_name, key_group, display_label, display_order, is_active)
SELECT
    cp - 31 AS key_id,
    CASE WHEN cp = 32 THEN 'space' ELSE CHAR(cp) END AS key_code,
    CASE WHEN cp = 32 THEN 'Space' ELSE CHAR(cp) END AS ahk_key_name,
    CASE
        WHEN cp = 32
            OR cp BETWEEN 48 AND 57
            OR cp BETWEEN 97 AND 122
            OR cp IN (39, 44, 45, 46, 47, 59, 61, 91, 92, 93, 96)
        THEN 'base'
        ELSE 'shift'
    END AS key_group,
    CASE WHEN cp = 32 THEN 'Space' ELSE CHAR(cp) END AS display_label,
    cp - 31 AS display_order,
    1 AS is_active
FROM ascii;

WITH RECURSIVE symbols(source_symbol_key, ordinal) AS (
    SELECT 'a', 0
    UNION ALL
    SELECT
        CASE
            WHEN source_symbol_key = 'z' THEN 'A'
            WHEN source_symbol_key = 'Z' THEN NULL
            WHEN source_symbol_key BETWEEN 'a' AND 'y' THEN CHAR(UNICODE(source_symbol_key) + 1)
            WHEN source_symbol_key BETWEEN 'A' AND 'Y' THEN CHAR(UNICODE(source_symbol_key) + 1)
        END,
        ordinal + 1
    FROM symbols
    WHERE source_symbol_key IS NOT NULL AND source_symbol_key <> 'Z'
)
INSERT OR REPLACE INTO symbol (
    symbol_id,
    source_symbol_key,
    slot_key,
    slot_number,
    symbol_category,
    yinyuan_label,
    pua_char,
    codepoint_hex,
    canonical_char,
    canonical_codepoint_hex,
    sort_order,
    symbol_name_zh,
    notes_zh
)
SELECT
    printf('sym_%03d', ordinal + 1),
    source_symbol_key,
    NULL,
    ordinal + 1,
    NULL,
    source_symbol_key,
    CHAR(57344 + ordinal),
    printf('U+%04X', 57344 + ordinal),
    NULL,
    NULL,
    ordinal + 1,
    '音元' || source_symbol_key,
    '观察库占位音元字符，可后续替换为正式私用区字符'
FROM symbols
WHERE source_symbol_key IS NOT NULL;

INSERT OR REPLACE INTO key_symbol_map (mapping_id, key_id, symbol_id, map_layer)
SELECT
    pk.key_id,
    pk.key_id,
    s.symbol_id,
    'default'
FROM physical_key AS pk
JOIN symbol AS s
    ON s.source_symbol_key = pk.key_code
WHERE LENGTH(pk.key_code) = 1
  AND ((pk.key_code BETWEEN 'a' AND 'z') OR (pk.key_code BETWEEN 'A' AND 'Z'));

INSERT INTO schema_comment (object_type, object_name, column_name, comment_zh)
VALUES
    ('table', 'db_meta', NULL, '数据库元信息表，记录 schema 名称、版本、用途等基础信息'),
    ('column', 'db_meta', 'meta_key', '元信息键名'),
    ('column', 'db_meta', 'meta_value', '元信息值'),
    ('column', 'db_meta', 'updated_at', '最后更新时间'),

    ('table', 'schema_comment', NULL, '结构注释表，用中文记录各数据表和字段含义'),
    ('column', 'schema_comment', 'object_type', '对象类型，可取 table 或 column'),
    ('column', 'schema_comment', 'object_name', '表名或视图名'),
    ('column', 'schema_comment', 'column_name', '字段名；表级注释时为空'),
    ('column', 'schema_comment', 'comment_zh', '中文注释内容'),

    ('table', 'physical_key', NULL, '物理键位表，记录可参与映射的键位定义'),
    ('column', 'physical_key', 'key_id', '键位主键'),
    ('column', 'physical_key', 'key_code', '系统内部键位代号'),
    ('column', 'physical_key', 'ahk_key_name', 'AutoHotkey 使用的键名'),
    ('column', 'physical_key', 'key_group', '键位分组，base 表示无需 Shift，shift 表示需按 Shift'),
    ('column', 'physical_key', 'display_label', '显示给人看的键帽标签'),
    ('column', 'physical_key', 'display_order', '键位显示顺序'),
    ('column', 'physical_key', 'is_active', '是否启用该键位'),

    ('table', 'symbol', NULL, '音元符号表，直接定义 PUA 符号实体及其稳定 ID'),
    ('column', 'symbol', 'symbol_id', '稳定符号 ID，例如 sym_001'),
    ('column', 'symbol', 'source_symbol_key', '历史来源键名；如旧方案中的字母键，可为空'),
    ('column', 'symbol', 'slot_key', '正式槽位键，例如 N01 或 M33'),
    ('column', 'symbol', 'slot_number', '槽位序号，用于和投射表对照'),
    ('column', 'symbol', 'symbol_category', '槽位类别，initial 或 musical'),
    ('column', 'symbol', 'yinyuan_label', '音元标签，例如 b、zh、ɪ́'),
    ('column', 'symbol', 'pua_char', '对应的私用区字符本体'),
    ('column', 'symbol', 'codepoint_hex', '私用区码位十六进制表示'),
    ('column', 'symbol', 'canonical_char', '对应 canonical SPUA-B 字符'),
    ('column', 'symbol', 'canonical_codepoint_hex', 'canonical SPUA-B 码位十六进制表示'),
    ('column', 'symbol', 'sort_order', '符号排序值，便于中间插入和调序'),
    ('column', 'symbol', 'symbol_name_zh', '音元中文名称'),
    ('column', 'symbol', 'notes_zh', '补充说明'),

    ('table', 'key_symbol_map', NULL, '键位到音元符号的映射表'),
    ('column', 'key_symbol_map', 'mapping_id', '映射主键'),
    ('column', 'key_symbol_map', 'key_id', '关联 physical_key 的键位 ID'),
    ('column', 'key_symbol_map', 'symbol_id', '关联 symbol 的稳定符号 ID'),
    ('column', 'key_symbol_map', 'map_layer', '映射层名称，默认 default'),

    ('table', 'klc_layout_source', NULL, 'KLC 原始布局导入表，保存 yinyuan.klc 各键位各修饰状态的输出'),
    ('column', 'klc_layout_source', 'layout_id', 'KLC 布局记录主键'),
    ('column', 'klc_layout_source', 'scan_code', '扫描码'),
    ('column', 'klc_layout_source', 'vk_name', 'KLC 中的虚拟键名'),
    ('column', 'klc_layout_source', 'cap_state', 'KLC 的 Cap 字段'),
    ('column', 'klc_layout_source', 'state_0_token', '未修饰状态的原始 token'),
    ('column', 'klc_layout_source', 'state_1_token', 'Shift 状态的原始 token'),
    ('column', 'klc_layout_source', 'state_2_token', 'Ctrl 状态的原始 token'),
    ('column', 'klc_layout_source', 'state_6_token', 'Ctrl+Alt 状态的原始 token'),
    ('column', 'klc_layout_source', 'state_0_char', '未修饰状态解析后的字符'),
    ('column', 'klc_layout_source', 'state_1_char', 'Shift 状态解析后的字符'),
    ('column', 'klc_layout_source', 'state_2_char', 'Ctrl 状态解析后的字符'),
    ('column', 'klc_layout_source', 'state_6_char', 'Ctrl+Alt 状态解析后的字符'),
    ('column', 'klc_layout_source', 'comment_text', 'KLC 行尾注释'),
    ('column', 'klc_layout_source', 'source_file', '导入来源文件名'),

    ('table', 'lexicon_entry', NULL, '词条表，记录汉字、词语或短语本体'),
    ('column', 'lexicon_entry', 'entry_id', '词条主键'),
    ('column', 'lexicon_entry', 'surface_text', '词条文本内容'),
    ('column', 'lexicon_entry', 'entry_type', '词条类型，可为单字、词语或短语'),
    ('column', 'lexicon_entry', 'char_count', '词条字数'),
    ('column', 'lexicon_entry', 'source_tag', '数据来源标签'),
    ('column', 'lexicon_entry', 'is_active', '是否启用该词条'),
    ('column', 'lexicon_entry', 'created_at', '创建时间'),
    ('column', 'lexicon_entry', 'updated_at', '更新时间'),

    ('table', 'entry_pronunciation', NULL, '词条读音表，记录原始拼音及规范化拼音'),
    ('column', 'entry_pronunciation', 'pronunciation_id', '读音主键'),
    ('column', 'entry_pronunciation', 'entry_id', '关联 lexicon_entry 的词条 ID'),
    ('column', 'entry_pronunciation', 'original_pinyin', '原始拼音表示'),
    ('column', 'entry_pronunciation', 'normalized_pinyin', '规范化后的拼音表示'),
    ('column', 'entry_pronunciation', 'syllable_count', '音节数'),
    ('column', 'entry_pronunciation', 'source_tag', '读音来源标签'),

    ('table', 'entry_encoding', NULL, '词条编码表，记录音元序列和私用区字符序列'),
    ('column', 'entry_encoding', 'encoding_id', '编码主键'),
    ('column', 'entry_encoding', 'pronunciation_id', '关联 entry_pronunciation 的读音 ID'),
    ('column', 'entry_encoding', 'symbol_sequence', '逻辑码元序列，例如 AbcZ'),
    ('column', 'entry_encoding', 'pua_sequence', '对应的私用区字符序列'),
    ('column', 'entry_encoding', 'encoding_version', '编码方案版本'),
    ('column', 'entry_encoding', 'is_primary', '是否为主编码'),
    ('column', 'entry_encoding', 'sort_priority', '候选排序优先级'),
    ('column', 'entry_encoding', 'notes_zh', '编码说明'),

    ('view', 'vw_entry_encoding_detail', NULL, '观察用视图，展开词条、拼音和编码的主要字段'),
    ('view', 'vw_key_symbol_layout', NULL, '观察用视图，展示 52 键位到 52 码元及私用区字符的映射关系'),
    ('view', 'vw_symbol_inventory', NULL, '观察用视图，汇总每个音元符号被哪些键位映射'),
    ('view', 'vw_symbol_crosswalk', NULL, '对照视图，展示槽位、BMP PUA、SPUA-B 与物理键位聚合结果'),
    ('view', 'vw_klc_layout_observation_all', NULL, '观察用全量视图，保留 KLC 原始布局中的所有行，包括 DECIMAL 等非标准键位'),
    ('view', 'vw_klc_layout_observation', NULL, '默认观察视图，只显示标准 48 键并自动排除 DECIMAL')
ON CONFLICT(object_type, object_name, column_name) DO UPDATE SET
    comment_zh = excluded.comment_zh;
