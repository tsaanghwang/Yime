PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS metadata (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
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

CREATE INDEX IF NOT EXISTS idx_single_char_hanzi ON single_char_readings(hanzi);
CREATE INDEX IF NOT EXISTS idx_single_char_numeric ON single_char_readings(numeric_pinyin);
CREATE INDEX IF NOT EXISTS idx_single_char_codepoint ON single_char_readings(codepoint);

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
