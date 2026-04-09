PRAGMA foreign_keys = ON;

DROP VIEW IF EXISTS vw_formal_candidate_key;
DROP VIEW IF EXISTS vw_symbol_key_simulation;
DROP TABLE IF EXISTS formal_candidate_key;
DROP TABLE IF EXISTS symbol_key_simulation;

CREATE TABLE symbol_key_simulation (
    sim_id INTEGER PRIMARY KEY,
    symbol_order INTEGER NOT NULL UNIQUE,
    symbol_hex TEXT NOT NULL UNIQUE,
    symbol_char TEXT NOT NULL UNIQUE,
    key_order INTEGER NOT NULL UNIQUE,
    key_char TEXT NOT NULL UNIQUE,
    key_ascii_code INTEGER NOT NULL UNIQUE,
    key_layer TEXT NOT NULL CHECK (key_layer IN ('base', 'shift')),
    layer_sort_order INTEGER NOT NULL CHECK (layer_sort_order IN (1, 2)),
    key_label TEXT NOT NULL,
    notes_zh TEXT
);

CREATE TABLE formal_candidate_key (
    candidate_id INTEGER PRIMARY KEY,
    sim_id INTEGER NOT NULL UNIQUE,
    is_selected INTEGER NOT NULL DEFAULT 0 CHECK (is_selected IN (0, 1)),
    candidate_order INTEGER,
    usage_tier TEXT NOT NULL DEFAULT 'candidate'
        CHECK (usage_tier IN ('candidate', 'core', 'extended', 'deferred')),
    selection_note_zh TEXT,
    FOREIGN KEY (sim_id) REFERENCES symbol_key_simulation(sim_id) ON DELETE CASCADE
);

WITH RECURSIVE printable_chars(n) AS (
    SELECT 33
    UNION ALL
    SELECT n + 1
    FROM printable_chars
    WHERE n < 126
)
INSERT INTO symbol_key_simulation (
    sim_id,
    symbol_order,
    symbol_hex,
    symbol_char,
    key_order,
    key_char,
    key_ascii_code,
    key_layer,
    layer_sort_order,
    key_label,
    notes_zh
)
SELECT
    n - 32 AS sim_id,
    n - 32 AS symbol_order,
    printf('U+%04X', 57344 + (n - 32)) AS symbol_hex,
    CHAR(57344 + (n - 32)) AS symbol_char,
    n - 32 AS key_order,
    CHAR(n) AS key_char,
    n AS key_ascii_code,
    CASE
        WHEN n BETWEEN 97 AND 122 THEN 'base'
        WHEN n IN (96, 49, 50, 51, 52, 53, 54, 55, 56, 57, 48, 45, 61, 91, 93, 92, 59, 39, 44, 46, 47) THEN 'base'
        ELSE 'shift'
    END AS key_layer,
    CASE
        WHEN n BETWEEN 97 AND 122 THEN 1
        WHEN n IN (96, 49, 50, 51, 52, 53, 54, 55, 56, 57, 48, 45, 61, 91, 93, 92, 59, 39, 44, 46, 47) THEN 1
        ELSE 2
    END AS layer_sort_order,
    CASE CHAR(n)
        WHEN '"' THEN 'double_quote'
        WHEN '''' THEN 'single_quote'
        WHEN '\' THEN 'backslash'
        WHEN '`' THEN 'backquote'
        ELSE CHAR(n)
    END AS key_label,
    '模拟表：94个可打印字符对应从U+E001开始的连续码元' AS notes_zh
FROM printable_chars;

INSERT INTO formal_candidate_key (
    candidate_id,
    sim_id,
    is_selected,
    candidate_order,
    usage_tier,
    selection_note_zh
)
SELECT
    sim_id,
    sim_id,
    0,
    NULL,
    'candidate',
    '待根据码元频次和手感选择是否进入正式键位表'
FROM symbol_key_simulation;

CREATE VIEW vw_symbol_key_simulation AS
SELECT
    sim_id,
    symbol_order,
    symbol_hex,
    symbol_char,
    key_order,
    key_char,
    key_ascii_code,
    key_layer,
    layer_sort_order,
    key_label,
    notes_zh
FROM symbol_key_simulation
ORDER BY symbol_order;

CREATE VIEW vw_formal_candidate_key AS
SELECT
    fck.candidate_id,
    fck.is_selected,
    fck.candidate_order,
    fck.usage_tier,
    sks.symbol_order,
    sks.symbol_hex,
    sks.symbol_char,
    sks.key_order,
    sks.key_char,
    sks.key_ascii_code,
    sks.key_layer,
    sks.layer_sort_order,
    sks.key_label,
    fck.selection_note_zh
FROM formal_candidate_key AS fck
JOIN symbol_key_simulation AS sks
    ON sks.sim_id = fck.sim_id
ORDER BY
    fck.is_selected DESC,
    COALESCE(fck.candidate_order, 999),
    sks.layer_sort_order,
    sks.key_order;
