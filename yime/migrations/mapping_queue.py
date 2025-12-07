import sqlite3
from pathlib import Path

DB = Path(__file__).parents[1] / "pinyin_hanzi.db"
with sqlite3.connect(str(DB)) as conn:
    cur = conn.cursor()
    cur.execute("SELECT id,target_pk,hanzi,phoneme_key FROM mapping_queue WHERE status='pending' LIMIT 100")
    rows = cur.fetchall()
    for qid, pk, hanzi, phoneme in rows:
        # 尝试用最新映射表查 codepoint / 映射 id
        cur.execute("SELECT id, codepoint_sequence FROM hanzi_phoneme_mapping WHERE hanzi=? AND phoneme_code=?", (hanzi, phoneme))
        m = cur.fetchone()
        if m:
            mapping_id, codepoints = m[0], m[1]
            cur.execute("UPDATE '音元拼音' SET 映射编号=?, codepoint_sequence=? WHERE 编号=?", (mapping_id, codepoints, pk))
            cur.execute("UPDATE mapping_queue SET status='done' WHERE id=?", (qid,))
    conn.commit()    
