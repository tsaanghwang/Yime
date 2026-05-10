from pathlib import Path
import sqlite3

DB = Path(__file__).parents[1] / "pinyin_hanzi.db"

def compose_audio_to_standard(db_path: Path):
    with sqlite3.connect(str(db_path)) as conn:
        cur = conn.cursor()
        # collect 数字标调 -> 音元拼音 (numeric -> audio)
        cur.execute('''
            SELECT 原拼音 AS numeric, 目标拼音 AS audio
            FROM "拼音映射关系"
            WHERE 原拼音类型 = '数字标调' AND 目标拼音类型 = '音元拼音'
        ''')
        numeric_to_audios = {}
        for numeric, audio in cur.fetchall():
            numeric_to_audios.setdefault(numeric, set()).add(audio)

        # collect 数字标调 -> 标准拼音 (numeric -> standard)
        cur.execute('''
            SELECT 原拼音 AS numeric, 目标拼音 AS standard
            FROM "拼音映射关系"
            WHERE 原拼音类型 = '数字标调' AND 目标拼音类型 = '标准拼音'
        ''')
        numeric_to_standards = {}
        for numeric, standard in cur.fetchall():
            numeric_to_standards.setdefault(numeric, set()).add(standard)

        # compose: for each numeric value, map each audio -> each standard
        inserts = []
        for numeric, audios in numeric_to_audios.items():
            standards = numeric_to_standards.get(numeric)
            if not standards:
                continue
            for audio in audios:
                for std in standards:
                    inserts.append((
                        '音元拼音', audio, '标准拼音', std,
                        'composed_audio_to_standard', '', f'composed via numeric {numeric}'
                    ))

        if not inserts:
            print("No composed audio->standard mappings found.")
            return 0

        cur.executemany('''
            INSERT OR IGNORE INTO "拼音映射关系"
            ("原拼音类型","原拼音","目标拼音类型","目标拼音","数据来源","版本号","备注")
            VALUES (?,?,?,?,?,?,?)
        ''', inserts)
        conn.commit()
        print("Inserted composed audio->standard rows:", cur.rowcount)
        return cur.rowcount

if __name__ == "__main__":
    if not DB.exists():
        print("DB not found:", DB)
    else:
        compose_audio_to_standard(DB)
