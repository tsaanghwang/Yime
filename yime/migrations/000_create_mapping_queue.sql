CREATE TABLE IF NOT EXISTS mapping_queue (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  target_table TEXT NOT NULL,
  target_pk INTEGER NOT NULL,
  hanzi TEXT,
  phoneme_key TEXT,
  status TEXT NOT NULL DEFAULT 'pending',
  attempts INTEGER DEFAULT 0,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_queue_status ON mapping_queue(status);
