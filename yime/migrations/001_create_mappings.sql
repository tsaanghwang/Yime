-- Active: 1758559459358@@127.0.0.1@3306@yime
-- 汉字到标准拼音（一个汉字可能有多条同音映射）
CREATE TABLE IF NOT EXISTS hanzi_standard_pinyin (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  hanzi TEXT NOT NULL,
  standard_pinyin TEXT NOT NULL,
  source TEXT,            -- 来源说明（json 文件名、版本）
  version INTEGER DEFAULT 1,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(hanzi, standard_pinyin)
);

CREATE INDEX IF NOT EXISTS idx_hanzi_standard ON hanzi_standard_pinyin(hanzi);

-- 汉字到音元码元(音元拼音) 的映射（可为空，后续回填）
CREATE TABLE IF NOT EXISTS hanzi_phoneme_mapping (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  hanzi TEXT NOT NULL,
  phoneme_code TEXT NOT NULL,   -- 你的音元编码（例如 PUA 串）或音节 key
  codepoint_sequence TEXT,      -- 可选：实际的 PUA/codepoint 串
  source TEXT,
  version INTEGER DEFAULT 1,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(hanzi, phoneme_code)
);

CREATE INDEX IF NOT EXISTS idx_hanzi_phoneme ON hanzi_phoneme_mapping(hanzi);

-- 变更/回填队列（触发器只写入此队列）
CREATE TABLE IF NOT EXISTS mapping_queue (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  target_table TEXT NOT NULL,
  target_pk INTEGER NOT NULL,
  hanzi TEXT,
  phoneme_key TEXT,
  status TEXT NOT NULL DEFAULT 'pending', -- pending|processing|done|failed
  attempts INTEGER DEFAULT 0,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_queue_status ON mapping_queue(status);
