PRAGMA foreign_keys = ON;

DROP VIEW IF EXISTS vw_formal_key_plan;
DROP TABLE IF EXISTS formal_key_plan;

CREATE TABLE formal_key_plan (
    plan_slot INTEGER PRIMARY KEY,
    sim_id INTEGER NOT NULL UNIQUE,
    symbol_order INTEGER NOT NULL UNIQUE,
    symbol_hex TEXT NOT NULL UNIQUE,
    symbol_char TEXT NOT NULL UNIQUE,
    physical_key_char TEXT NOT NULL,
    output_layer TEXT NOT NULL CHECK (output_layer IN ('base', 'shift')),
    physical_group TEXT NOT NULL CHECK (physical_group IN ('letter', 'symbol')),
    json_key TEXT NOT NULL UNIQUE,
    relocated_ascii_char TEXT,
    relocated_ascii_layer TEXT CHECK (relocated_ascii_layer IN ('shift')),
    notes_zh TEXT,
    FOREIGN KEY (sim_id) REFERENCES symbol_key_simulation(sim_id) ON DELETE CASCADE
);

WITH selected_keys(plan_slot, physical_key_char, output_layer, physical_group, json_key, relocated_ascii_char, relocated_ascii_layer, notes_zh) AS (
    VALUES
        (1,  '`', 'base', 'symbol', '`', '`', 'shift', '下档符号键改作码元键，原反引号挪到上档'),
        (2,  '1', 'base', 'symbol', '1', '1', 'shift', '数字键下档改作码元键，原字符挪到上档'),
        (3,  '2', 'base', 'symbol', '2', '2', 'shift', '数字键下档改作码元键，原字符挪到上档'),
        (4,  '3', 'base', 'symbol', '3', '3', 'shift', '数字键下档改作码元键，原字符挪到上档'),
        (5,  '4', 'base', 'symbol', '4', '4', 'shift', '数字键下档改作码元键，原字符挪到上档'),
        (6,  '5', 'base', 'symbol', '5', '5', 'shift', '数字键下档改作码元键，原字符挪到上档'),
        (7,  '6', 'base', 'symbol', '6', '6', 'shift', '数字键下档改作码元键，原字符挪到上档'),
        (8,  '7', 'base', 'symbol', '7', '7', 'shift', '数字键下档改作码元键，原字符挪到上档'),
        (9,  '8', 'base', 'symbol', '8', '8', 'shift', '数字键下档改作码元键，原字符挪到上档'),
        (10, '9', 'base', 'symbol', '9', '9', 'shift', '数字键下档改作码元键，原字符挪到上档'),
        (11, '0', 'base', 'symbol', '0', '0', 'shift', '数字键下档改作码元键，原字符挪到上档'),
        (12, '-', 'base', 'symbol', '-', '-', 'shift', '下档减号键改作码元键，原字符挪到上档'),
        (13, '=', 'base', 'symbol', '=', '=', 'shift', '下档等号键改作码元键，原字符挪到上档'),
        (14, 'q', 'base', 'letter', 'q', NULL, NULL, '字母键下档作为正式码元键'),
        (15, 'w', 'base', 'letter', 'w', NULL, NULL, '字母键下档作为正式码元键'),
        (16, 'e', 'base', 'letter', 'e', NULL, NULL, '字母键下档作为正式码元键'),
        (17, 'r', 'base', 'letter', 'r', NULL, NULL, '字母键下档作为正式码元键'),
        (18, 't', 'base', 'letter', 't', NULL, NULL, '字母键下档作为正式码元键'),
        (19, 'y', 'base', 'letter', 'y', NULL, NULL, '字母键下档作为正式码元键'),
        (20, 'u', 'base', 'letter', 'u', NULL, NULL, '字母键下档作为正式码元键'),
        (21, 'i', 'base', 'letter', 'i', NULL, NULL, '字母键下档作为正式码元键'),
        (22, 'o', 'base', 'letter', 'o', NULL, NULL, '字母键下档作为正式码元键'),
        (23, 'p', 'base', 'letter', 'p', NULL, NULL, '字母键下档作为正式码元键'),
        (24, '[', 'base', 'symbol', '[', '[', 'shift', '下档左方括号键改作码元键，原字符挪到上档'),
        (25, ']', 'base', 'symbol', ']', ']', 'shift', '下档右方括号键改作码元键，原字符挪到上档'),
        (26, '\\', 'base', 'symbol', '\\', '\\', 'shift', '下档反斜杠键改作码元键，原字符挪到上档'),
        (27, 'a', 'base', 'letter', 'a', NULL, NULL, '字母键下档作为正式码元键'),
        (28, 's', 'base', 'letter', 's', NULL, NULL, '字母键下档作为正式码元键'),
        (29, 'd', 'base', 'letter', 'd', NULL, NULL, '字母键下档作为正式码元键'),
        (30, 'f', 'base', 'letter', 'f', NULL, NULL, '字母键下档作为正式码元键'),
        (31, 'g', 'base', 'letter', 'g', NULL, NULL, '字母键下档作为正式码元键'),
        (32, 'h', 'base', 'letter', 'h', NULL, NULL, '字母键下档作为正式码元键'),
        (33, 'j', 'base', 'letter', 'j', NULL, NULL, '字母键下档作为正式码元键'),
        (34, 'k', 'base', 'letter', 'k', NULL, NULL, '字母键下档作为正式码元键'),
        (35, 'l', 'base', 'letter', 'l', NULL, NULL, '字母键下档作为正式码元键'),
        (36, ';', 'base', 'symbol', ';', ';', 'shift', '下档分号键改作码元键，原字符挪到上档'),
        (37, '''', 'base', 'symbol', '''', '''', 'shift', '下档单引号键改作码元键，原字符挪到上档'),
        (38, 'z', 'base', 'letter', 'z', NULL, NULL, '字母键下档作为正式码元键'),
        (39, 'x', 'base', 'letter', 'x', NULL, NULL, '字母键下档作为正式码元键'),
        (40, 'c', 'base', 'letter', 'c', NULL, NULL, '字母键下档作为正式码元键'),
        (41, 'v', 'base', 'letter', 'v', NULL, NULL, '字母键下档作为正式码元键'),
        (42, 'b', 'base', 'letter', 'b', NULL, NULL, '字母键下档作为正式码元键'),
        (43, 'n', 'base', 'letter', 'n', NULL, NULL, '字母键下档作为正式码元键'),
        (44, 'm', 'base', 'letter', 'm', NULL, NULL, '字母键下档作为正式码元键'),
        (45, ',', 'base', 'symbol', ',', ',', 'shift', '下档逗号键改作码元键，原字符挪到上档'),
        (46, '.', 'base', 'symbol', '.', '.', 'shift', '下档句点键改作码元键，原字符挪到上档'),
        (47, '/', 'base', 'symbol', '/', '/', 'shift', '下档斜杠键改作码元键，原字符挪到上档'),
        (48, 'g', 'shift', 'letter', 'Shift+g', NULL, NULL, '扩展上档码元键位之一；按你的列表保留'),
        (49, 'h', 'shift', 'letter', 'Shift+h', NULL, NULL, '扩展上档码元键位之一；按你的列表保留'),
        (50, 'j', 'shift', 'letter', 'Shift+j', NULL, NULL, '扩展上档码元键位之一；按你的列表保留'),
        (51, 'k', 'shift', 'letter', 'Shift+k', NULL, NULL, '扩展上档码元键位之一；按你的列表保留'),
        (52, 'l', 'shift', 'letter', 'Shift+l', NULL, NULL, '扩展上档码元键位之一；按你的列表保留'),
        (53, 'n', 'shift', 'letter', 'Shift+n', NULL, NULL, '扩展上档码元键位之一；你消息里列了6个键，这里按列出的6个键全部保留')
)
INSERT INTO formal_key_plan (
    plan_slot,
    sim_id,
    symbol_order,
    symbol_hex,
    symbol_char,
    physical_key_char,
    output_layer,
    physical_group,
    json_key,
    relocated_ascii_char,
    relocated_ascii_layer,
    notes_zh
)
SELECT
    sk.plan_slot,
    sk.plan_slot,
    sk.plan_slot,
    printf('U+%04X', 57344 + sk.plan_slot),
    CHAR(57344 + sk.plan_slot),
    sk.physical_key_char,
    sk.output_layer,
    sk.physical_group,
    sk.json_key,
    sk.relocated_ascii_char,
    sk.relocated_ascii_layer,
    sk.notes_zh
FROM selected_keys AS sk;

CREATE VIEW vw_formal_key_plan AS
SELECT
    plan_slot,
    sim_id,
    symbol_order,
    symbol_hex,
    symbol_char,
    physical_key_char,
    output_layer,
    physical_group,
    json_key,
    relocated_ascii_char,
    relocated_ascii_layer,
    notes_zh
FROM formal_key_plan
ORDER BY plan_slot;
