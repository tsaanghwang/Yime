PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS metadata (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS source_files (
    source_kind TEXT PRIMARY KEY CHECK (source_kind IN ('char', 'phrase')),
    source_path TEXT NOT NULL,
    imported_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS char_readings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    codepoint TEXT NOT NULL,
    hanzi TEXT NOT NULL,
    marked_pinyin TEXT NOT NULL,
    numeric_pinyin TEXT NOT NULL,
    reading_rank INTEGER NOT NULL,
    is_primary INTEGER NOT NULL DEFAULT 0 CHECK (is_primary IN (0, 1)),
    UNIQUE (codepoint, marked_pinyin)
);

CREATE INDEX IF NOT EXISTS idx_char_hanzi ON char_readings(hanzi);
CREATE INDEX IF NOT EXISTS idx_char_numeric ON char_readings(numeric_pinyin);
CREATE INDEX IF NOT EXISTS idx_char_codepoint ON char_readings(codepoint);

CREATE TABLE IF NOT EXISTS phrase_readings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    phrase TEXT NOT NULL,
    phrase_len INTEGER NOT NULL,
    marked_pinyin TEXT NOT NULL,
    numeric_pinyin TEXT NOT NULL,
    reading_rank INTEGER NOT NULL,
    UNIQUE (phrase, marked_pinyin)
);

CREATE INDEX IF NOT EXISTS idx_phrase_text ON phrase_readings(phrase);
CREATE INDEX IF NOT EXISTS idx_phrase_numeric ON phrase_readings(numeric_pinyin);
