-- Active: 1758559459358@@127.0.0.1@3306@yime
CREATE TABLE IF NOT EXISTS hanzi_phoneme_mapping (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  hanzi TEXT NOT NULL,
  phoneme_code TEXT NOT NULL,
  codepoint_sequence TEXT,
  source TEXT,
  version INTEGER DEFAULT 1,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(hanzi, phoneme_code)
);
CREATE INDEX IF NOT EXISTS idx_hanzi_phoneme ON hanzi_phoneme_mapping(hanzi);
