from pathlib import Path
import sqlite3
import argparse
import logging
import sys

DB = Path(__file__).parents[1] / "pinyin_hanzi.db"
logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")
logger = logging.getLogger(__name__)

def process_queue(conn: sqlite3.Connection, apply: bool, limit: int = 100, max_attempts: int = 3):
    cur = conn.cursor()
    # 确保返回 sqlite3.Row，便于按列名访问
    try:
        conn.row_factory = sqlite3.Row
        cur = conn.cursor()
    except Exception:
        pass

    # 检查 mapping_queue 表中是否有 attempts 列
    cols = [r["name"] for r in cur.execute("PRAGMA table_info(mapping_queue)").fetchall()]
    has_attempts = "attempts" in cols

    if has_attempts:
        sql = "SELECT id,target_pk,hanzi,phoneme_key,attempts FROM mapping_queue WHERE status='pending' ORDER BY created_at LIMIT ?"
    else:
        sql = "SELECT id,target_pk,hanzi,phoneme_key FROM mapping_queue WHERE status='pending' ORDER BY created_at LIMIT ?"

    rows = cur.execute(sql, (limit,)).fetchall()
    logger.info("Found %d pending queue items", len(rows))
    if not rows:
        return 0

    updated = 0
    for r in rows:
        # 兼容 Row 或 tuple
        if isinstance(r, sqlite3.Row):
            qid = r["id"]
            pk = r["target_pk"]
            hanzi = r["hanzi"]
            phoneme = r["phoneme_key"]
            attempts = r["attempts"] if has_attempts and "attempts" in r.keys() else 0
        else:
            if has_attempts:
                qid, pk, hanzi, phoneme, attempts = r
            else:
                qid, pk, hanzi, phoneme = r
                attempts = 0

        m = cur.execute(
            "SELECT id, codepoint_sequence FROM hanzi_phoneme_mapping WHERE hanzi=? AND phoneme_code=? LIMIT 1",
            (hanzi, phoneme),
        ).fetchone()
        if not m:
            attempts = (attempts or 0) + 1
            if apply:
                if has_attempts:
                    if attempts >= max_attempts:
                        cur.execute("UPDATE mapping_queue SET attempts=?, status='failed' WHERE id=?", (attempts, qid))
                        logger.info("Queue %s marked failed (attempts=%d)", qid, attempts)
                    else:
                        cur.execute("UPDATE mapping_queue SET attempts=? WHERE id=?", (attempts, qid))
                else:
                    # 如果没有 attempts 列，只更新 status 为 failed 当超过阈值（保守：直接不改 attempts）
                    if attempts >= max_attempts:
                        cur.execute("UPDATE mapping_queue SET status='failed' WHERE id=?", (qid,))
                        logger.info("Queue %s marked failed (no attempts column)", qid)
            else:
                logger.info("Would increment attempts for queue %s (dry-run)", qid)
            continue

        mapping_id, codepoints = (m["id"], m["codepoint_sequence"]) if isinstance(m, sqlite3.Row) else (m[0], m[1])
        if apply:
            cur.execute('UPDATE "音元拼音" SET 映射编号=?, codepoint_sequence=? WHERE 编号=?', (mapping_id, codepoints, pk))
            cur.execute("UPDATE mapping_queue SET status='done' WHERE id=?", (qid,))
            updated += 1
            logger.info("Updated pk=%s with mapping_id=%s (queue %s)", pk, mapping_id, qid)
        else:
            logger.info("Dry-run: would update pk=%s with mapping_id=%s (queue %s)", pk, mapping_id, qid)

    if apply:
        conn.commit()
    return updated

def backfill_all(conn: sqlite3.Connection, apply: bool):
    cur = conn.cursor()
    cnt = cur.execute(
        'SELECT COUNT(*) FROM "音元拼音" p WHERE EXISTS (SELECT 1 FROM hanzi_phoneme_mapping m WHERE m.hanzi = p.全拼 AND m.phoneme_code = p.干音)'
    ).fetchone()[0]
    logger.info("Rows eligible for full backfill: %d", cnt)
    if not cnt:
        return 0
    if apply:
        cur.execute(
            'UPDATE "音元拼音" SET 映射编号 = (SELECT id FROM hanzi_phoneme_mapping m WHERE m.hanzi = "音元拼音".全拼 AND m.phoneme_code = "音元拼音".干音 LIMIT 1) WHERE EXISTS (SELECT 1 FROM hanzi_phoneme_mapping m WHERE m.hanzi = "音元拼音".全拼 AND m.phoneme_code = "音元拼音".干音)'
        )
        conn.commit()
        logger.info("Applied full backfill, affected rows approx: %d", cnt)
        return cnt
    else:
        logger.info("Dry-run: would apply full backfill to %d rows", cnt)
        return cnt

def main(argv=None):
    p = Path(DB)
    if not p.exists():
        logger.error("数据库不存在: %s", p)
        return 2

    parser = argparse.ArgumentParser(description="Backfill mappings: queue processing or full backfill.")
    parser.add_argument("--apply", action="store_true", help="Apply changes; default is dry-run")
    parser.add_argument("--mode", choices=["queue","full"], default="queue", help="queue: process mapping_queue; full: batch update all matching rows")
    parser.add_argument("--limit", type=int, default=100, help="Max items to process when mode=queue")
    args = parser.parse_args(argv)

    conn = sqlite3.connect(str(p))
    conn.row_factory = sqlite3.Row

    if args.mode == "queue":
        n = process_queue(conn, args.apply, limit=args.limit)
        logger.info("Processed queue, updates applied: %d (apply=%s)", n, args.apply)
    else:
        n = backfill_all(conn, args.apply)
        logger.info("Full backfill: %d rows (apply=%s)", n, args.apply)

    conn.close()
    return 0

if __name__ == "__main__":
    sys.exit(main())
