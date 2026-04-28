from __future__ import annotations

import argparse
import shutil
import sqlite3
import subprocess
import sys
from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Iterable


DEFAULT_DB_PATH = Path(__file__).resolve().parent / "pinyin_hanzi.db"
DEFAULT_WANXIANG_ROOT = Path(r"C:\dev\RIME-LMDG")
DEFAULT_CHAR_DICT = Path("dicts/zi.dict.yaml")
DEFAULT_RUNTIME_EXPORT = Path(__file__).resolve().parent / "export_runtime_candidates_json.py"

ACCENTED_VOWEL_MAP: dict[str, tuple[str, int]] = {
    "ā": ("a", 1),
    "á": ("a", 2),
    "ǎ": ("a", 3),
    "à": ("a", 4),
    "ē": ("e", 1),
    "é": ("e", 2),
    "ě": ("e", 3),
    "è": ("e", 4),
    "ê": ("e", 1),
    "ḗ": ("e", 2),
    "ế": ("e", 2),
    "ě": ("e", 3),
    "ề": ("e", 4),
    "ī": ("i", 1),
    "í": ("i", 2),
    "ǐ": ("i", 3),
    "ì": ("i", 4),
    "ō": ("o", 1),
    "ó": ("o", 2),
    "ǒ": ("o", 3),
    "ò": ("o", 4),
    "ū": ("u", 1),
    "ú": ("u", 2),
    "ǔ": ("u", 3),
    "ù": ("u", 4),
    "ǖ": ("ü", 1),
    "ǘ": ("ü", 2),
    "ǚ": ("ü", 3),
    "ǜ": ("ü", 4),
    "ń": ("n", 2),
    "ň": ("n", 3),
    "ǹ": ("n", 4),
    "ḿ": ("m", 2),
}


@dataclass(frozen=True)
class ImportStats:
    parsed_char_rows: int
    parsed_phrase_rows: int
    matched_char_readings: int
    matched_char_frequency_rows: int
    matched_phrase_rows: int


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="借用 RIME-LMDG 的单字/词语频率数据到本地 Yime 数据库"
    )
    parser.add_argument("--db", default=str(DEFAULT_DB_PATH), help="Yime SQLite 数据库路径")
    parser.add_argument(
        "--wanxiang-root",
        default=str(DEFAULT_WANXIANG_ROOT),
        help="RIME-LMDG 仓库根目录",
    )
    parser.add_argument(
        "--char-dict",
        default=str(DEFAULT_CHAR_DICT),
        help="相对 wanxiang-root 的单字词库路径",
    )
    parser.add_argument(
        "--phrase-dicts",
        nargs="*",
        default=None,
        help="相对 wanxiang-root 的词语词库路径；默认导入 dicts 下除 zi.dict.yaml 外的所有 *.dict.yaml",
    )
    parser.add_argument(
        "--source-tag",
        default="borrowed:RIME-LMDG",
        help="写回数据库时使用的来源标签",
    )
    parser.add_argument(
        "--skip-runtime-export",
        action="store_true",
        help="更新数据库后不刷新 runtime_candidates JSON",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="只统计匹配，不写入数据库",
    )
    parser.add_argument(
        "--no-backup",
        action="store_true",
        help="写库前不创建数据库备份",
    )
    return parser.parse_args()


def resolve_phrase_dicts(root: Path, args: argparse.Namespace) -> list[Path]:
    if args.phrase_dicts:
        return [root / Path(item) for item in args.phrase_dicts]

    dict_dir = root / "dicts"
    return sorted(
        path
        for path in dict_dir.glob("*.dict.yaml")
        if path.name != "zi.dict.yaml"
    )


def iter_rime_rows(path: Path) -> Iterable[tuple[str, str, float]]:
    in_payload = False
    with path.open("r", encoding="utf-8") as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            if not in_payload:
                if line == "...":
                    in_payload = True
                continue

            payload = raw_line.split("#", 1)[0].rstrip("\n")
            if not payload.strip():
                continue

            parts = [part.strip() for part in payload.split("\t") if part.strip()]
            if len(parts) < 3:
                continue

            text, marked_pinyin, weight_text = parts[:3]
            try:
                weight = float(weight_text)
            except ValueError:
                continue
            yield text, marked_pinyin, weight


def marked_syllable_to_numeric(syllable: str) -> str:
    tone = 5
    base_chars: list[str] = []
    for char in syllable:
        mapped = ACCENTED_VOWEL_MAP.get(char)
        if mapped is None:
            base_chars.append(char)
            continue
        base, tone = mapped
        base_chars.append(base)

    base_syllable = "".join(base_chars).lower().replace("u:", "ü")
    if not base_syllable:
        return base_syllable
    return f"{base_syllable}{tone}"


def marked_pinyin_to_numeric(marked_pinyin: str) -> str:
    syllables = [segment for segment in marked_pinyin.strip().split() if segment]
    return " ".join(marked_syllable_to_numeric(segment) for segment in syllables)


def load_char_frequency_map(path: Path) -> tuple[dict[tuple[str, str], float], dict[str, float], int]:
    by_reading: dict[tuple[str, str], float] = {}
    by_char_total: dict[str, float] = defaultdict(float)
    parsed_rows = 0
    for text, marked_pinyin, weight in iter_rime_rows(path):
        if len(text) != 1:
            continue
        numeric_pinyin = marked_pinyin_to_numeric(marked_pinyin)
        key = (text, numeric_pinyin)
        previous = by_reading.get(key)
        if previous is None or weight > previous:
            by_reading[key] = weight
        parsed_rows += 1

    for (hanzi, _numeric_pinyin), weight in by_reading.items():
        by_char_total[hanzi] += weight

    return by_reading, dict(by_char_total), parsed_rows


def load_phrase_frequency_map(paths: Iterable[Path]) -> tuple[dict[tuple[str, str], float], int]:
    by_phrase: dict[tuple[str, str], float] = {}
    parsed_rows = 0
    for path in paths:
        for text, marked_pinyin, weight in iter_rime_rows(path):
            if len(text) < 2:
                continue
            numeric_pinyin = marked_pinyin_to_numeric(marked_pinyin)
            key = (text, numeric_pinyin)
            previous = by_phrase.get(key)
            if previous is None or weight > previous:
                by_phrase[key] = weight
            parsed_rows += 1
    return by_phrase, parsed_rows


def backup_database(db_path: Path) -> Path:
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_path = db_path.with_suffix(f".wanxiang_borrow_{timestamp}.bak")
    shutil.copy2(db_path, backup_path)
    return backup_path


def apply_frequency_updates(
    db_path: Path,
    *,
    char_frequency_by_reading: dict[tuple[str, str], float],
    char_frequency_by_char: dict[str, float],
    phrase_frequency_by_key: dict[tuple[str, str], float],
    source_tag: str,
    dry_run: bool,
) -> ImportStats:
    conn = sqlite3.connect(db_path)
    try:
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()

        char_row_matches = cursor.execute(
            """
                        SELECT ci.hanzi, npi.pinyin_tone
                        FROM char_pinyin_map AS cpm
                        JOIN char_inventory AS ci
                            ON ci.id = cpm.char_id
                        JOIN numeric_pinyin_inventory AS npi
                            ON npi.id = cpm.numeric_pinyin_id
            """
        ).fetchall()
        matched_char_readings = sum(
            1
            for row in char_row_matches
            if (str(row[0]), str(row[1])) in char_frequency_by_reading
        )

        char_table_matches = cursor.execute(
            'SELECT hanzi FROM char_inventory'
        ).fetchall()
        matched_char_frequency_rows = sum(
            1
            for row in char_table_matches
            if str(row[0]) in char_frequency_by_char
        )

        phrase_matches = cursor.execute(
            """
                        SELECT p.phrase_id, pi.phrase, p.pinyin_tone
            FROM phrase_pinyin_map AS p
                        JOIN phrase_inventory AS pi
                            ON pi.id = p.phrase_id
            """
        ).fetchall()
        matched_phrase_rows = sum(
            1
            for row in phrase_matches
            if (str(row[1]), str(row[2])) in phrase_frequency_by_key
        )

        if dry_run:
            return ImportStats(
                parsed_char_rows=len(char_frequency_by_reading),
                parsed_phrase_rows=len(phrase_frequency_by_key),
                matched_char_readings=matched_char_readings,
                matched_char_frequency_rows=matched_char_frequency_rows,
                matched_phrase_rows=matched_phrase_rows,
            )

        cursor.execute("BEGIN")
        cursor.execute('UPDATE char_pinyin_map SET reading_weight = NULL, updated_at = CURRENT_TIMESTAMP')
        cursor.execute(
            'UPDATE char_inventory SET char_frequency_abs = NULL, char_frequency_rel = NULL, frequency_source = NULL, updated_at = CURRENT_TIMESTAMP'
        )
        cursor.execute('UPDATE phrase_inventory SET phrase_frequency = NULL, updated_at = CURRENT_TIMESTAMP')

        cursor.executemany(
            """
            UPDATE char_pinyin_map
            SET reading_weight = ?,
                updated_at = CURRENT_TIMESTAMP
            WHERE char_id = (
                SELECT id FROM char_inventory WHERE hanzi = ?
            )
              AND numeric_pinyin_id = (
                SELECT id FROM numeric_pinyin_inventory WHERE pinyin_tone = ?
            )
            """,
            [
                (weight, hanzi, numeric_pinyin)
                for (hanzi, numeric_pinyin), weight in char_frequency_by_reading.items()
            ],
        )

        cursor.executemany(
            """
            UPDATE char_inventory
            SET char_frequency_abs = ?,
                char_frequency_rel = ?,
                frequency_source = ?,
                updated_at = CURRENT_TIMESTAMP
            WHERE hanzi = ?
            """,
            [
                (int(round(weight)), float(weight), source_tag, hanzi)
                for hanzi, weight in char_frequency_by_char.items()
            ],
        )

        cursor.executemany(
            """
            UPDATE phrase_inventory
            SET phrase_frequency = ?,
                updated_at = CURRENT_TIMESTAMP
            WHERE id = ?
            """,
            [
                (weight, int(row[0]))
                for row in phrase_matches
                for weight in [phrase_frequency_by_key.get((str(row[1]), str(row[2])))]
                if weight is not None
            ],
        )

        conn.commit()
        return ImportStats(
            parsed_char_rows=len(char_frequency_by_reading),
            parsed_phrase_rows=len(phrase_frequency_by_key),
            matched_char_readings=matched_char_readings,
            matched_char_frequency_rows=matched_char_frequency_rows,
            matched_phrase_rows=matched_phrase_rows,
        )
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def refresh_runtime_export(db_path: Path) -> None:
    subprocess.run(
        [
            sys.executable,
            str(DEFAULT_RUNTIME_EXPORT),
            "--db",
            str(db_path),
        ],
        check=True,
    )


def main() -> int:
    args = parse_args()
    db_path = Path(args.db).resolve()
    wanxiang_root = Path(args.wanxiang_root).resolve()
    char_dict_path = wanxiang_root / Path(args.char_dict)
    phrase_dict_paths = resolve_phrase_dicts(wanxiang_root, args)

    if not db_path.exists():
        print(f"未找到数据库: {db_path}", file=sys.stderr)
        return 1
    if not wanxiang_root.exists():
        print(f"未找到 RIME-LMDG 仓库: {wanxiang_root}", file=sys.stderr)
        return 1
    if not char_dict_path.exists():
        print(f"未找到单字词库: {char_dict_path}", file=sys.stderr)
        return 1
    missing_phrase_paths = [path for path in phrase_dict_paths if not path.exists()]
    if missing_phrase_paths:
        print("以下词语词库不存在:", file=sys.stderr)
        for path in missing_phrase_paths:
            print(f"  - {path}", file=sys.stderr)
        return 1

    char_frequency_by_reading, char_frequency_by_char, parsed_char_rows = (
        load_char_frequency_map(char_dict_path)
    )
    phrase_frequency_by_key, parsed_phrase_rows = load_phrase_frequency_map(
        phrase_dict_paths
    )

    if not args.dry_run and not args.no_backup:
        backup_path = backup_database(db_path)
        print(f"已创建数据库备份: {backup_path}")

    stats = apply_frequency_updates(
        db_path,
        char_frequency_by_reading=char_frequency_by_reading,
        char_frequency_by_char=char_frequency_by_char,
        phrase_frequency_by_key=phrase_frequency_by_key,
        source_tag=args.source_tag,
        dry_run=args.dry_run,
    )

    print(f"解析到单字读音频率: {parsed_char_rows}")
    print(f"解析到词语读音频率: {parsed_phrase_rows}")
    print(f"命中的单字读音映射: {stats.matched_char_readings}")
    print(f"命中的单字频率行: {stats.matched_char_frequency_rows}")
    print(f"命中的词语频率行: {stats.matched_phrase_rows}")
    print("说明: 已先清空原有字频/词频，仅保留本次万象导入命中的频率数据。")
    print("说明: 单字总频写入汉字频率时，按同字各读音权重去重后求和；当前候选视图会优先读取这个总频。")

    if args.dry_run:
        print("dry-run 模式：未写入数据库")
        return 0

    if not args.skip_runtime_export:
        refresh_runtime_export(db_path)
        print("已刷新 runtime_candidates 导出 JSON")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
