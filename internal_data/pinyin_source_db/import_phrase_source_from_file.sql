.bail on

.parameter init
.parameter set @phrase_source_name phrase:pinyin.txt

-- Usage:
--   1. Edit the .import path below if your phrase file lives elsewhere.
--   2. Run:
--        sqlite3 c:/dev/Yime/internal_data/pinyin_source_db/source_pinyin.db ".read c:/dev/Yime/internal_data/pinyin_source_db/import_phrase_source_from_file.sql"
--   3. Optional check:
--        SELECT COUNT(*) FROM phrase_readings;

PRAGMA foreign_keys = ON;

BEGIN;

CREATE TABLE IF NOT EXISTS source_files (
    source_name TEXT PRIMARY KEY,
    source_kind TEXT NOT NULL CHECK (source_kind IN ('single_char', 'phrase')),
    source_path TEXT NOT NULL,
    imported_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

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

CREATE INDEX IF NOT EXISTS idx_phrase_text ON phrase_readings(phrase);
CREATE INDEX IF NOT EXISTS idx_phrase_numeric ON phrase_readings(numeric_pinyin);

DROP TABLE IF EXISTS temp_phrase_source_lines;
CREATE TEMP TABLE temp_phrase_source_lines (
    raw_line TEXT
);

COMMIT;

.mode tabs
.import c:/dev/pinyin-data/tools/phrase-pinyin-data/pinyin.txt temp_phrase_source_lines

BEGIN;

DELETE FROM phrase_readings
WHERE source_name = @phrase_source_name;

DELETE FROM source_files
WHERE source_name = @phrase_source_name
  AND source_kind = 'phrase';

INSERT INTO source_files (source_name, source_kind, source_path)
VALUES (@phrase_source_name, 'phrase', 'c:/dev/pinyin-data/tools/phrase-pinyin-data/pinyin.txt');

WITH RECURSIVE
raw_lines AS (
    SELECT
        rowid AS input_order,
        TRIM(raw_line) AS raw_line
    FROM temp_phrase_source_lines
    WHERE TRIM(raw_line) <> ''
      AND SUBSTR(LTRIM(raw_line), 1, 1) <> '#'
),
split_comment AS (
    SELECT
        input_order,
        raw_line,
        CASE
            WHEN INSTR(raw_line, '#') > 0 THEN RTRIM(SUBSTR(raw_line, 1, INSTR(raw_line, '#') - 1))
            ELSE raw_line
        END AS content,
        NULLIF(TRIM(CASE
            WHEN INSTR(raw_line, '#') > 0 THEN SUBSTR(raw_line, INSTR(raw_line, '#') + 1)
            ELSE ''
        END), '') AS comment
    FROM raw_lines
),
parsed AS (
    SELECT
        input_order,
        raw_line,
        comment,
        TRIM(SUBSTR(content, 1, INSTR(content, ':') - 1)) AS phrase,
        TRIM(SUBSTR(content, INSTR(content, ':') + 1)) AS marked_pinyin
    FROM split_comment
    WHERE INSTR(content, ':') > 0
),
ranked AS (
    SELECT
        input_order,
        raw_line,
        comment,
        phrase,
        marked_pinyin,
        ROW_NUMBER() OVER (
            PARTITION BY phrase
            ORDER BY input_order
        ) AS reading_rank
    FROM parsed
    WHERE phrase <> ''
      AND marked_pinyin <> ''
),
syllable_split AS (
    SELECT
        input_order,
        phrase,
        marked_pinyin,
        reading_rank,
        comment,
        raw_line,
        1 AS syllable_index,
        CASE
            WHEN INSTR(marked_pinyin, ' ') > 0 THEN SUBSTR(marked_pinyin, 1, INSTR(marked_pinyin, ' ') - 1)
            ELSE marked_pinyin
        END AS syllable,
        CASE
            WHEN INSTR(marked_pinyin, ' ') > 0 THEN LTRIM(SUBSTR(marked_pinyin, INSTR(marked_pinyin, ' ') + 1))
            ELSE ''
        END AS remaining
    FROM ranked

    UNION ALL

    SELECT
        input_order,
        phrase,
        marked_pinyin,
        reading_rank,
        comment,
        raw_line,
        syllable_index + 1,
        CASE
            WHEN INSTR(remaining, ' ') > 0 THEN SUBSTR(remaining, 1, INSTR(remaining, ' ') - 1)
            ELSE remaining
        END AS syllable,
        CASE
            WHEN INSTR(remaining, ' ') > 0 THEN LTRIM(SUBSTR(remaining, INSTR(remaining, ' ') + 1))
            ELSE ''
        END AS remaining
    FROM syllable_split
    WHERE remaining <> ''
),
numeric_syllables AS (
    SELECT
        input_order,
        phrase,
        marked_pinyin,
        reading_rank,
        comment,
        raw_line,
        syllable_index,
        CASE
            WHEN syllable = 'ê̄' THEN 'ê1'
            WHEN syllable = 'ế' THEN 'ê2'
            WHEN syllable = 'ê̌' THEN 'ê3'
            WHEN syllable = 'ề' THEN 'ê4'
            WHEN syllable = 'm̄' THEN 'm1'
            WHEN syllable = 'ḿ' THEN 'm2'
            WHEN syllable = 'm̌' THEN 'm3'
            WHEN syllable = 'm̀' THEN 'm4'
            WHEN syllable = 'n̄' THEN 'n1'
            WHEN syllable = 'ń' THEN 'n2'
            WHEN syllable = 'ň' THEN 'n3'
            WHEN syllable = 'ǹ' THEN 'n4'
            WHEN syllable = 'n̄g' THEN 'ng1'
            WHEN syllable = 'ňg' THEN 'ng3'
            WHEN syllable = 'ǹg' THEN 'ng4'
            WHEN syllable = 'hm̄' THEN 'hm1'
            WHEN syllable = 'hm̌' THEN 'hm3'
            WHEN syllable = 'hm̀' THEN 'hm4'
            WHEN syllable = 'hn̄' THEN 'hn1'
            WHEN syllable = 'hň' THEN 'hn3'
            WHEN syllable = 'hǹ' THEN 'hn4'
            WHEN syllable = 'hn̄g' THEN 'hng1'
            WHEN syllable = 'hňg' THEN 'hng3'
            WHEN syllable = 'hǹg' THEN 'hng4'
            ELSE
                REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(syllable,
                    'ā', 'a'), 'á', 'a'), 'ǎ', 'a'), 'à', 'a'),
                    'ē', 'e'), 'é', 'e'), 'ě', 'e'), 'è', 'e'),
                    'ī', 'i'), 'í', 'i'), 'ǐ', 'i'), 'ì', 'i'),
                    'ō', 'o'), 'ó', 'o'), 'ǒ', 'o'), 'ò', 'o'),
                    'ū', 'u'), 'ú', 'u'), 'ǔ', 'u'), 'ù', 'u'),
                    'ǖ', 'ü'), 'ǘ', 'ü'), 'ǚ', 'ü'), 'ǜ', 'ü'),
                    'ḿ', 'm'), 'ń', 'n'), 'ň', 'n'), 'ǹ', 'n'),
                    'ế', 'ê') ||
                CASE
                    WHEN syllable GLOB '*ā*' OR syllable GLOB '*ē*' OR syllable GLOB '*ī*' OR syllable GLOB '*ō*' OR syllable GLOB '*ū*' OR syllable GLOB '*ǖ*' THEN '1'
                    WHEN syllable GLOB '*á*' OR syllable GLOB '*é*' OR syllable GLOB '*í*' OR syllable GLOB '*ó*' OR syllable GLOB '*ú*' OR syllable GLOB '*ǘ*' OR syllable GLOB '*ḿ*' OR syllable GLOB '*ń*' OR syllable GLOB '*ế*' THEN '2'
                    WHEN syllable GLOB '*ǎ*' OR syllable GLOB '*ě*' OR syllable GLOB '*ǐ*' OR syllable GLOB '*ǒ*' OR syllable GLOB '*ǔ*' OR syllable GLOB '*ǚ*' OR syllable GLOB '*ň*' THEN '3'
                    WHEN syllable GLOB '*à*' OR syllable GLOB '*è*' OR syllable GLOB '*ì*' OR syllable GLOB '*ò*' OR syllable GLOB '*ù*' OR syllable GLOB '*ǜ*' OR syllable GLOB '*ǹ*' OR syllable GLOB '*ề*' THEN '4'
                    ELSE '5'
                END
        END AS numeric_syllable
    FROM syllable_split
),
aggregated AS (
    SELECT
        input_order,
        phrase,
        marked_pinyin,
        reading_rank,
        comment,
        raw_line,
        GROUP_CONCAT(numeric_syllable, ' ') AS numeric_pinyin,
        COUNT(*) AS syllable_count
    FROM (
        SELECT *
        FROM numeric_syllables
        ORDER BY input_order, syllable_index
    )
    GROUP BY input_order, phrase, marked_pinyin, reading_rank, comment, raw_line
)
INSERT OR REPLACE INTO phrase_readings (
    source_name,
    phrase,
    marked_pinyin,
    numeric_pinyin,
    reading_rank,
    comment,
    raw_line
)
SELECT
    @phrase_source_name,
    phrase,
    marked_pinyin,
    numeric_pinyin,
    reading_rank,
    comment,
    raw_line
FROM aggregated
WHERE phrase <> ''
  AND marked_pinyin <> '';

DROP TABLE IF EXISTS temp_phrase_source_lines;

COMMIT;

SELECT 'phrase_readings rows for phrase:pinyin.txt' AS label, COUNT(*) AS row_count
FROM phrase_readings
WHERE source_name = @phrase_source_name;
