from __future__ import annotations

import argparse
import json
import shutil
import sqlite3
import subprocess
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

from yime.canonical_yime_mapping import (
    load_canonical_code_map,
    load_canonical_patch_map,
    sync_canonical_mapping_table,
)


SCRIPT_DIR = Path(__file__).resolve().parent
DB_PATH = SCRIPT_DIR / "pinyin_hanzi.db"
DEFAULT_BACKUP_DIR = SCRIPT_DIR / "backup"
EXPORT_SCRIPT = SCRIPT_DIR / "export_runtime_candidates_json.py"
SCHEMA_PATH = SCRIPT_DIR / "create_prototype_schema_additions.sql"

PREFERRED_PHRASE_READINGS: dict[str, tuple[str, str]] = {
    "朝阳": ("zhao1 yang2", "source-first ambiguous reading"),
    "那些": ("na4 xie1", "source-first ambiguous reading"),
}


@dataclass
class RefreshStats:
    total_char_rows: int = 0
    char_rows_with_expected: int = 0
    char_rows_to_update: int = 0
    char_rows_already_current: int = 0
    char_rows_missing_expected: int = 0
    total_phrase_rows: int = 0
    phrase_rows_single_effective_code: int = 0
    phrase_rows_to_update: int = 0
    phrase_rows_already_current: int = 0
    phrase_rows_ambiguous: int = 0
    phrase_rows_missing_pinyin: int = 0
    runtime_matches_before: int = 0
    runtime_mismatches_before: int = 0
    runtime_matches_after: int = 0
    runtime_mismatches_after: int = 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="按当前 yinjie_code 真源刷新数据库中的音元编码列。默认 dry-run。"
    )
    parser.add_argument("--db", default=str(DB_PATH), help="SQLite 数据库路径")
    parser.add_argument("--apply", action="store_true", help="真正写入数据库；默认仅 dry-run")
    parser.add_argument("--no-backup", action="store_true", help="写库前不创建数据库备份")
    parser.add_argument(
        "--skip-runtime-export",
        action="store_true",
        help="写库后不刷新 runtime_candidates JSON 导出",
    )
    parser.add_argument(
        "--show-examples",
        type=int,
        default=10,
        help="每类问题最多展示多少条样例",
    )
    return parser.parse_args()


def backup_database(db_path: Path) -> Path:
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    DEFAULT_BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    backup_path = DEFAULT_BACKUP_DIR / f"{db_path.stem}.yime_code_refresh_{timestamp}.bak"
    shutil.copy2(db_path, backup_path)
    return backup_path


def compute_runtime_alignment(
    conn: sqlite3.Connection,
    canonical_code_map: dict[str, str],
) -> tuple[int, int]:
    rows = conn.execute(
        "SELECT pinyin_tone, yime_code FROM runtime_candidates"
    ).fetchall()
    matches = 0
    mismatches = 0
    for row in rows:
        pinyin_tone = str(row[0] or "").strip()
        stored_code = str(row[1] or "").strip()
        if not pinyin_tone:
            continue
        expected_code = "".join(
            canonical_code_map.get(syllable, "")
            for syllable in pinyin_tone.split()
            if syllable
        )
        if not expected_code:
            continue
        if stored_code == expected_code:
            matches += 1
        else:
            mismatches += 1
    return matches, mismatches


def build_char_updates(
    conn: sqlite3.Connection,
    canonical_code_map: dict[str, str],
    examples_limit: int,
) -> tuple[list[tuple[str, str, str]], Counter, dict[str, list[tuple[object, ...]]]]:
    patch_pinyin_tones = set(load_canonical_patch_map(SCRIPT_DIR.parent))
    rows = conn.execute(
        '''
        SELECT npi.pinyin_tone, pyc.yime_code, pyc.code_source
        FROM numeric_pinyin_inventory AS npi
        LEFT JOIN pinyin_yime_code AS pyc
            ON pyc.pinyin_tone = npi.pinyin_tone
        ORDER BY npi.pinyin_tone
        '''
    ).fetchall()

    updates: list[tuple[str, str, str]] = []
    stats = Counter()
    examples: dict[str, list[tuple[object, ...]]] = defaultdict(list)

    for row in rows:
        pinyin_tone = str(row[0] or "").strip()
        current_code = str(row[1] or "")
        current_source = str(row[2] or "")
        stats["total"] += 1
        if not pinyin_tone:
            stats["missing_expected"] += 1
            if len(examples["missing_expected"]) < examples_limit:
                examples["missing_expected"].append(
                    (pinyin_tone, current_code, "<missing pinyin_tone>")
                )
            continue

        expected_code = canonical_code_map.get(pinyin_tone, "")
        if not expected_code:
            stats["missing_expected"] += 1
            if len(examples["missing_expected"]) < examples_limit:
                examples["missing_expected"].append(
                    (pinyin_tone, current_code, "<missing in code map>")
                )
            continue

        stats["with_expected"] += 1
        if current_code == expected_code:
            stats["already_current"] += 1
            continue

        code_source = "canonical_patch" if pinyin_tone in patch_pinyin_tones else "yinjie_code"
        updates.append((pinyin_tone, expected_code, code_source))
        stats["to_update"] += 1

    return updates, stats, examples


def build_phrase_updates(
    conn: sqlite3.Connection,
    canonical_code_map: dict[str, str],
    examples_limit: int,
) -> tuple[list[tuple[str, int]], Counter, dict[str, list[tuple[object, ...]]]]:
    rows = conn.execute(
        '''
        SELECT pi.id, pi.phrase, pi.yime_code, ppm.pinyin_tone, pref.preferred_pinyin_tone
        FROM phrase_inventory AS pi
        LEFT JOIN phrase_pinyin_map AS ppm
            ON ppm.phrase_id = pi.id
        LEFT JOIN phrase_reading_preference AS pref
            ON pref.phrase = pi.phrase
        ORDER BY pi.id, ppm.reading_rank, ppm.pinyin_tone
        '''
    ).fetchall()

    grouped: dict[int, dict[str, object]] = {}
    for row in rows:
        phrase_id = int(row[0])
        record = grouped.setdefault(
            phrase_id,
            {
                "phrase": str(row[1] or ""),
                "stored": str(row[2] or ""),
                "tones": [],
                "preferred_tone": str(row[4] or "").strip(),
            },
        )
        pinyin_tone = str(row[3] or "").strip()
        if pinyin_tone:
            record["tones"].append(pinyin_tone)

    updates: list[tuple[str, int]] = []
    stats = Counter()
    examples: dict[str, list[tuple[object, ...]]] = defaultdict(list)

    for phrase_id, record in grouped.items():
        stats["total"] += 1
        phrase = str(record["phrase"])
        stored_code = str(record["stored"])
        tones = list(dict.fromkeys(record["tones"]))
        preferred_tone = str(record.get("preferred_tone") or "").strip()
        if not tones:
            stats["missing_pinyin"] += 1
            if len(examples["missing_pinyin"]) < examples_limit:
                examples["missing_pinyin"].append((phrase_id, phrase, stored_code))
            continue

        expected_codes = {
            "".join(canonical_code_map.get(syllable, "") for syllable in tone.split() if syllable)
            for tone in tones
        }
        expected_codes.discard("")
        if not expected_codes:
            stats["missing_pinyin"] += 1
            if len(examples["missing_expected"]) < examples_limit:
                examples["missing_expected"].append((phrase_id, phrase, stored_code, tones[:5]))
            continue

        if len(expected_codes) > 1:
            if preferred_tone:
                preferred_code = "".join(
                    canonical_code_map.get(syllable, "")
                    for syllable in preferred_tone.split()
                    if syllable
                )
                if preferred_code:
                    stats["single_effective_code"] += 1
                    if stored_code == preferred_code:
                        stats["already_current"] += 1
                        continue

                    updates.append((preferred_code, phrase_id))
                    stats["to_update"] += 1
                    continue

            stats["ambiguous"] += 1
            if len(examples["ambiguous"]) < examples_limit:
                examples["ambiguous"].append((
                    phrase_id,
                    phrase,
                    stored_code,
                    tones[:5],
                    sorted(expected_codes)[:5],
                    preferred_tone,
                ))
            continue

        stats["single_effective_code"] += 1
        expected_code = next(iter(expected_codes))
        if stored_code == expected_code:
            stats["already_current"] += 1
            continue

        updates.append((expected_code, phrase_id))
        stats["to_update"] += 1

    return updates, stats, examples


def refresh_runtime_export(db_path: Path) -> None:
    subprocess.run(
        [
            sys.executable,
            str(EXPORT_SCRIPT),
            "--db",
            str(db_path),
        ],
        check=True,
    )


def sync_phrase_reading_preferences(conn: sqlite3.Connection) -> int:
    phrase_rows = conn.execute("SELECT phrase FROM phrase_inventory").fetchall()
    known_phrases = {str(row[0] or "") for row in phrase_rows}
    preferred_rows = [
        (phrase, preferred_pinyin_tone, reason)
        for phrase, (preferred_pinyin_tone, reason) in PREFERRED_PHRASE_READINGS.items()
        if phrase in known_phrases
    ]
    if not preferred_rows:
        return 0

    conn.executemany(
        '''
        INSERT INTO phrase_reading_preference (
            phrase,
            preferred_pinyin_tone,
            selection_reason,
            updated_at
        ) VALUES (?, ?, ?, CURRENT_TIMESTAMP)
        ON CONFLICT(phrase) DO UPDATE SET
            preferred_pinyin_tone = excluded.preferred_pinyin_tone,
            selection_reason = excluded.selection_reason,
            updated_at = CURRENT_TIMESTAMP
        ''',
        preferred_rows,
    )
    return len(preferred_rows)


def print_examples(title: str, examples: list[tuple[object, ...]]) -> None:
    if not examples:
        return
    print(title)
    for item in examples:
        print(f"  {item}")


def main() -> int:
    args = parse_args()
    db_path = Path(args.db).resolve()
    repo_root = SCRIPT_DIR.parent

    if not db_path.exists():
        print(f"未找到数据库: {db_path}", file=sys.stderr)
        return 1

    canonical_code_map = load_canonical_code_map(repo_root)
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    try:
        conn.executescript(SCHEMA_PATH.read_text(encoding="utf-8"))
        if args.apply:
            preferred_phrase_count = sync_phrase_reading_preferences(conn)
            conn.commit()
        else:
            preferred_phrase_count = 0
        conn.commit()

        runtime_matches_before, runtime_mismatches_before = compute_runtime_alignment(
            conn,
            canonical_code_map,
        )
        char_updates, char_stats, char_examples = build_char_updates(
            conn,
            canonical_code_map,
            args.show_examples,
        )
        phrase_updates, phrase_stats, phrase_examples = build_phrase_updates(
            conn,
            canonical_code_map,
            args.show_examples,
        )

        print(f"运行时候选当前匹配: {runtime_matches_before}")
        print(f"运行时候选当前不匹配: {runtime_mismatches_before}")
        print(f"单字拼音行总数: {char_stats['total']}")
        print(f"单字可推导 canonical 行: {char_stats['with_expected']}")
        print(f"单字待更新行: {char_stats['to_update']}")
        print(f"单字已是当前 canonical 行: {char_stats['already_current']}")
        print(f"单字缺少推导依据行: {char_stats['missing_expected']}")
        print(f"词语行总数: {phrase_stats['total']}")
        print(f"词语单一有效编码行: {phrase_stats['single_effective_code']}")
        print(f"词语待更新行: {phrase_stats['to_update']}")
        print(f"词语已是当前编码行: {phrase_stats['already_current']}")
        print(f"词语多读音多编码歧义行: {phrase_stats['ambiguous']}")
        print(f"词语缺少拼音行: {phrase_stats['missing_pinyin']}")

        print_examples("单字缺少推导依据样例:", char_examples.get("missing_expected", []))
        print_examples("词语多编码歧义样例:", phrase_examples.get("ambiguous", []))
        print_examples("词语缺少拼音样例:", phrase_examples.get("missing_pinyin", []))

        if not args.apply:
            print("dry-run 模式：未写入数据库")
            return 0

        if not args.no_backup:
            backup_path = backup_database(db_path)
            print(f"已创建数据库备份: {backup_path}")

        canonical_mapping_count = sync_canonical_mapping_table(conn, repo_root)
        print(f"已同步 canonical pinyin_yime_code 行: {canonical_mapping_count}")
        print(f"已同步 phrase_reading_preference 行: {preferred_phrase_count}")
        conn.commit()

        applied_char_rows = 0
        applied_phrase_rows = 0
        apply_pass = 0
        while char_updates or phrase_updates:
            apply_pass += 1
            conn.execute("BEGIN")
            if char_updates:
                conn.executemany(
                    '''
                    INSERT INTO pinyin_yime_code (pinyin_tone, yime_code, code_source, updated_at)
                    VALUES (?, ?, ?, CURRENT_TIMESTAMP)
                    ON CONFLICT(pinyin_tone) DO UPDATE SET
                        yime_code = excluded.yime_code,
                        code_source = excluded.code_source,
                        updated_at = CURRENT_TIMESTAMP
                    ''',
                    char_updates,
                )
            if phrase_updates:
                conn.executemany(
                    'UPDATE phrase_inventory SET yime_code = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?',
                    phrase_updates,
                )
            conn.commit()

            applied_char_rows += len(char_updates)
            applied_phrase_rows += len(phrase_updates)
            print(
                f"第 {apply_pass} 轮写入: 单字 {len(char_updates)} 行, 词语 {len(phrase_updates)} 行"
            )

            char_updates, char_stats, char_examples = build_char_updates(
                conn,
                canonical_code_map,
                args.show_examples,
            )
            phrase_updates, phrase_stats, phrase_examples = build_phrase_updates(
                conn,
                canonical_code_map,
                args.show_examples,
            )

        print(f"累计写入单字行: {applied_char_rows}")
        print(f"累计写入词语行: {applied_phrase_rows}")

        runtime_matches_after, runtime_mismatches_after = compute_runtime_alignment(
            conn,
            canonical_code_map,
        )
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()

    print(f"写库后运行时候选匹配: {runtime_matches_after}")
    print(f"写库后运行时候选不匹配: {runtime_mismatches_after}")

    if not args.skip_runtime_export:
        refresh_runtime_export(db_path)
        print("已刷新 runtime_candidates 导出 JSON")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
