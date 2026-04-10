PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS metadata (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS single_char_lexicon (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    hanzi TEXT NOT NULL,
    pinyin_tone TEXT NOT NULL,
    reading_rank INTEGER NOT NULL DEFAULT 1,
    char_frequency REAL,
    yime_code TEXT,
    source_file TEXT NOT NULL,
    source_note TEXT,
    enabled INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(hanzi, pinyin_tone)
);

CREATE TABLE IF NOT EXISTS phrase_lexicon (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    phrase TEXT NOT NULL,
    pinyin_tone TEXT NOT NULL,
    reading_rank INTEGER NOT NULL DEFAULT 1,
    phrase_frequency REAL,
    yime_code TEXT,
    source_file TEXT NOT NULL,
    source_note TEXT,
    enabled INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(phrase, pinyin_tone)
);

CREATE INDEX IF NOT EXISTS idx_single_char_hanzi ON single_char_lexicon(hanzi);
CREATE INDEX IF NOT EXISTS idx_single_char_pinyin ON single_char_lexicon(pinyin_tone);
CREATE INDEX IF NOT EXISTS idx_single_char_code ON single_char_lexicon(yime_code);

CREATE INDEX IF NOT EXISTS idx_phrase_text ON phrase_lexicon(phrase);
CREATE INDEX IF NOT EXISTS idx_phrase_pinyin ON phrase_lexicon(pinyin_tone);
CREATE INDEX IF NOT EXISTS idx_phrase_code ON phrase_lexicon(yime_code);

CREATE VIEW IF NOT EXISTS merged_lexicon AS
SELECT
    'single' AS entry_type,
    id,
    hanzi AS text,
    pinyin_tone,
    reading_rank,
    char_frequency AS frequency,
    yime_code,
    source_file,
    enabled,
    created_at
FROM single_char_lexicon
UNION ALL
SELECT
    'phrase' AS entry_type,
    id,
    phrase AS text,
    pinyin_tone,
    reading_rank,
    phrase_frequency AS frequency,
    yime_code,
    source_file,
    enabled,
    created_at
FROM phrase_lexicon;
