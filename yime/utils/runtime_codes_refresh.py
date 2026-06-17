from __future__ import annotations

import argparse
import json
import shutil
import sqlite3
import subprocess
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass
from itertools import product
from pathlib import Path

try:
    from yime.utils.backup import create_timestamped_backup
except ImportError:
    from utils.backup import create_timestamped_backup

from yime.canonical_yime_mapping import (
    load_canonical_code_map,
    load_canonical_patch_map,
    sync_canonical_mapping_table,
)
from yime.utils.blcu_word_frequency_import import load_char_frequency_map
from yime.utils.char_frequency_policy import (
    BCC_SOURCE,
    DEFAULT_BCC_CHAR_FREQ_PATH,
    purge_legacy_frequency_metadata,
)
from yime.utils.unihan_readings_frequency import (
    DEFAULT_UNIHAN_READINGS_DB,
    load_tghz2013_char_frequencies,
)


MODULE_DIR = Path(__file__).resolve().parent
PACKAGE_DIR = MODULE_DIR.parent if MODULE_DIR.name == "utils" else MODULE_DIR
REPO_ROOT = PACKAGE_DIR.parent
DB_PATH = PACKAGE_DIR / "pinyin_hanzi.db"
DEFAULT_BACKUP_DIR = PACKAGE_DIR / "backup"
DEFAULT_BACKUP_RETAIN_COUNT = 20
EXPORT_SCRIPT = PACKAGE_DIR / "export_runtime_candidates_json.py"
SCHEMA_PATH = PACKAGE_DIR / "create_prototype_schema_additions.sql"
DEFAULT_TUNING_SCAN_JSON_OUTPUT = PACKAGE_DIR / "reports" / "runtime_tuning_scan.json"
DEFAULT_TUNING_SCAN_MARKDOWN_OUTPUT = PACKAGE_DIR / "reports" / "runtime_tuning_scan.md"
DEFAULT_UNIHAN_READINGS_DB_PATH = DEFAULT_UNIHAN_READINGS_DB
DEFAULT_XHC1983_SOURCE = Path("C:/dev/pinyin-data/kXHC1983.txt")
DEFAULT_BLCU_CHAR_FREQ_SOURCE = DEFAULT_BCC_CHAR_FREQ_PATH

OPTIONAL_EXTERNAL_FREQUENCY_SOURCES = (
    (
        DEFAULT_UNIHAN_READINGS_DB_PATH,
        "《通用规范汉字表》TGHZ2013 + BCC 单字频",
        "缺失时将跳过 TGHZ2013 单字分层增强；需要时可运行 external_data/unihan_readings/build_all.py 重建 unihan_readings.db。",
    ),
    (
        DEFAULT_BLCU_CHAR_FREQ_SOURCE,
        "BCC 合并单字频（merged_char_freq.txt）",
        "缺失时将跳过 BCC 单字序位增强；需要时可运行 tools/merge_char_freq.py 生成后放回 external_data/char_freq/。",
    ),
)

COMMON_HIGH_COUNT = 3500
COMMON_LOW_COUNT = 3000
SPECIAL_HIGH_COUNT = 1605
SPECIAL_LOW_COUNT = 4895

TIER_BASE_WEIGHTS = {
    "common_high": 40_000_000.0,
    "common_low": 30_000_000.0,
    "special_high": 20_000_000.0,
    "special_low": 10_000_000.0,
    "rare": 0.0,
}

MODERN_COMMON_MAX_RANK = 12_000
MODERN_COMMON_RANK_DIVISOR = 20.0
COMMON_READING_WEIGHT = 0.0
UNCOMMON_READING_WEIGHT = 0.0
PHRASE_READING_PRIOR_SCALE = 0.25
PHRASE_READING_PRIOR_MIN_SHARE = 0.995
PHRASE_READING_PRIOR_MIN_PHRASE_COUNT = 2.0
PHRASE_READING_PRIOR_MIN_EVIDENCE_WEIGHT = 0.0

DEFAULT_TUNING_PARAMETERS: dict[str, tuple[float, str]] = {
    "common_reading_weight": (COMMON_READING_WEIGHT, "常用读音排序加成"),
    "uncommon_reading_weight": (UNCOMMON_READING_WEIGHT, "非常用读音排序惩罚"),
    "modern_common_max_rank": (MODERN_COMMON_MAX_RANK, "现代常用单字序位阈值"),
    "modern_common_rank_divisor": (MODERN_COMMON_RANK_DIVISOR, "现代常用单字序位缩放除数"),
    "phrase_reading_prior_scale": (PHRASE_READING_PRIOR_SCALE, "词语读音先验缩放系数"),
    "phrase_reading_prior_min_share": (PHRASE_READING_PRIOR_MIN_SHARE, "词语读音先验启用门槛：reading_share 至少达到该值才启用"),
    "phrase_reading_prior_min_phrase_count": (PHRASE_READING_PRIOR_MIN_PHRASE_COUNT, "词语读音先验启用门槛：至少需要这么多条词语证据"),
    "phrase_reading_prior_min_evidence_weight": (PHRASE_READING_PRIOR_MIN_EVIDENCE_WEIGHT, "词语读音先验启用门槛：累计 evidence_weight 至少达到该值"),
}

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
    parser.add_argument(
        "--backup-retain",
        type=int,
        default=DEFAULT_BACKUP_RETAIN_COUNT,
        help="保留最近多少份数据库备份",
    )
    parser.add_argument(
        "--scan-runtime-tuning",
        action="store_true",
        help="在事务内批量扫描弱先验参数组合，并输出首屏指标对比；不会持久写库。",
    )
    parser.add_argument(
        "--scan-limit",
        type=int,
        default=20,
        help="扫描模式下输出前多少组结果。",
    )
    parser.add_argument(
        "--scan-page-size",
        type=int,
        default=5,
        help="扫描模式下按多少候选计算首屏可见率。",
    )
    parser.add_argument(
        "--scan-reading-weight-magnitudes",
        default="2,5,10",
        help="扫描模式下常用/非常用读音权重幅度列表；会自动展开成 +v / -v。",
    )
    parser.add_argument(
        "--scan-prior-scale-values",
        default="2,5",
        help="扫描模式下词语读音先验 scale 列表。",
    )
    parser.add_argument(
        "--scan-prior-share-values",
        default="0.98,0.995,0.999",
        help="扫描模式下 reading_share 门槛列表。",
    )
    parser.add_argument(
        "--scan-prior-min-phrase-count-values",
        default="1,2,3",
        help="扫描模式下最小 phrase_count 门槛列表。",
    )
    parser.add_argument(
        "--scan-prior-min-evidence-weight-values",
        default="0,2,5",
        help="扫描模式下最小 evidence_weight 门槛列表。",
    )
    parser.add_argument(
        "--scan-high-collision-bucket-limit",
        type=int,
        default=20,
        help="扫描模式下局部评分关注的高碰撞单字顶数量。",
    )
    parser.add_argument(
        "--scan-json-output",
        default=str(DEFAULT_TUNING_SCAN_JSON_OUTPUT),
        help="扫描结果 JSON 输出路径。",
    )
    parser.add_argument(
        "--scan-markdown-output",
        default=str(DEFAULT_TUNING_SCAN_MARKDOWN_OUTPUT),
        help="扫描结果 Markdown 输出路径。",
    )
    parser.add_argument(
        "--scan-global-first-page-tolerance",
        type=float,
        default=0.0,
        help="把组合视为全局首屏可用时，允许相对 modern_common 的最大负向 first-page 偏移。",
    )
    parser.add_argument(
        "--scan-global-top1-tolerance",
        type=float,
        default=0.0,
        help="把组合视为全局首选可用时，允许相对 modern_common 的最大负向 top1 偏移。",
    )
    parser.add_argument(
        "--scan-local-first-page-tolerance",
        type=float,
        default=0.0,
        help="把组合视为局部高碰撞桶可用时，允许相对 modern_common 的最大负向 first-page 偏移。",
    )
    parser.add_argument(
        "--scan-local-top1-tolerance",
        type=float,
        default=0.0,
        help="把组合视为局部高碰撞桶可用时，允许相对 modern_common 的最大负向 top1 偏移。",
    )
    return parser.parse_args()


def parse_float_list(raw_value: str) -> list[float]:
    values: list[float] = []
    for chunk in raw_value.split(","):
        item = chunk.strip()
        if not item:
            continue
        values.append(float(item))
    if not values:
        raise ValueError("至少需要一个数值")
    return values


def parse_int_list(raw_value: str) -> list[int]:
    values: list[int] = []
    for chunk in raw_value.split(","):
        item = chunk.strip()
        if not item:
            continue
        values.append(int(item))
    if not values:
        raise ValueError("至少需要一个整数")
    return values


def report_missing_optional_external_frequency_sources() -> None:
    missing_entries = [
        (path, label, note)
        for path, label, note in OPTIONAL_EXTERNAL_FREQUENCY_SOURCES
        if not path.exists()
    ]
    if not missing_entries:
        return

    print("提示：以下外部频率资源缺失，将跳过对应增强步骤：")
    for path, label, note in missing_entries:
        print(f"- {label}: {path}")
        print(f"  {note}")


def backup_database(db_path: Path, *, retain_count: int) -> tuple[Path, list[Path]]:
    return create_timestamped_backup(
        db_path,
        backup_dir=DEFAULT_BACKUP_DIR,
        backup_tag="yime_code_refresh",
        retain_count=retain_count,
    )


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
    patch_pinyin_tones = set(load_canonical_patch_map(REPO_ROOT))
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


def summarize_char_frequency_state(conn: sqlite3.Connection) -> dict[str, int | str]:
    row = conn.execute(
        """
        SELECT
            COUNT(*),
            SUM(CASE WHEN char_frequency_abs IS NOT NULL THEN 1 ELSE 0 END),
            SUM(CASE WHEN frequency_source = ? THEN 1 ELSE 0 END),
            SUM(
                CASE
                    WHEN frequency_source IS NOT NULL
                     AND frequency_source <> ? THEN 1
                    ELSE 0
                END
            )
        FROM char_inventory
        """,
        (BCC_SOURCE, BCC_SOURCE),
    ).fetchone()
    total_chars = int(row[0] or 0) if row is not None else 0
    populated = int(row[1] or 0) if row is not None else 0
    bcc_rows = int(row[2] or 0) if row is not None else 0
    synthetic_rows = int(row[3] or 0) if row is not None else 0

    source_counter = Counter(
        str(item[0] or "").strip()
        for item in conn.execute(
            """
            SELECT frequency_source
            FROM char_inventory
            WHERE frequency_source IS NOT NULL AND TRIM(frequency_source) <> ''
            """
        )
        if str(item[0] or "").strip()
    )
    dominant_source = source_counter.most_common(1)[0][0] if source_counter else ""

    purge_legacy_frequency_metadata(conn)
    conn.executemany(
        '''
        INSERT OR REPLACE INTO prototype_metadata (key, value, note, updated_at)
        VALUES (?, ?, ?, CURRENT_TIMESTAMP)
        ''',
        [
            (
                "prototype_char_frequency_state_total_chars",
                str(total_chars),
                "char_inventory 总字数",
            ),
            (
                "prototype_char_frequency_state_populated",
                str(populated),
                "char_inventory 已写入 char_frequency_abs 的字数",
            ),
            (
                "prototype_char_frequency_state_bcc_rows",
                str(bcc_rows),
                "frequency_source 为 BCC 的字数",
            ),
            (
                "prototype_char_frequency_state_synthetic_rows",
                str(synthetic_rows),
                "frequency_source 为 Unihan 合成兜底的字数",
            ),
            (
                "prototype_char_frequency_state_dominant_source",
                dominant_source,
                "char_inventory 中出现最多的 frequency_source",
            ),
        ],
    )

    return {
        "total_chars": total_chars,
        "populated": populated,
        "bcc_rows": bcc_rows,
        "synthetic_rows": synthetic_rows,
        "dominant_source": dominant_source,
    }


def load_dictionary_chars(path: Path) -> set[str]:
    if not path.exists():
        return set()

    chars: set[str] = set()
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or ":" not in line or "#" not in line:
            continue
        payload = line.split("#", 1)[1].strip()
        if payload:
            chars.add(payload[0])
    return chars


def load_char_inventory_frequencies(conn: sqlite3.Connection) -> dict[str, int]:
    return {
        str(row[0]): int(row[1] or 0)
        for row in conn.execute(
            "SELECT hanzi, COALESCE(char_frequency_abs, 0) FROM char_inventory"
        )
    }


def load_single_char_word_frequencies(path: Path) -> dict[str, int]:
    if not path.exists():
        return {}
    by_char, _parsed_rows = load_char_frequency_map(path)
    return by_char


def load_single_char_word_ranks(path: Path) -> dict[str, int]:
    frequency_by_char = load_single_char_word_frequencies(path)
    sorted_chars = sorted(
        frequency_by_char.items(),
        key=lambda item: (-item[1], item[0]),
    )
    return {
        hanzi: index
        for index, (hanzi, _frequency) in enumerate(sorted_chars, start=1)
    }


def upsert_runtime_tuning_parameters(conn: sqlite3.Connection, parameters: dict[str, float]) -> None:
    conn.executemany(
        '''
        INSERT INTO runtime_tuning_parameters (key, value, note, updated_at)
        VALUES (?, ?, ?, CURRENT_TIMESTAMP)
        ON CONFLICT(key) DO UPDATE SET
            value = excluded.value,
            note = excluded.note,
            updated_at = CURRENT_TIMESTAMP
        ''',
        [
            (
                key,
                float(parameters[key]),
                DEFAULT_TUNING_PARAMETERS.get(key, (0.0, "runtime tuning parameter"))[1],
            )
            for key in sorted(parameters)
        ],
    )


def load_runtime_tuning_parameters(conn: sqlite3.Connection) -> dict[str, float]:
    upsert_runtime_tuning_parameters(
        conn,
        {key: default_value for key, (default_value, _note) in DEFAULT_TUNING_PARAMETERS.items()},
    )

    rows = conn.execute(
        '''
        SELECT key, value
        FROM runtime_tuning_parameters
        '''
    ).fetchall()
    return {
        str(row[0]): float(row[1])
        for row in rows
        if row[0] is not None and row[1] is not None
    }


def build_effective_tuning_parameters(overrides: dict[str, float] | None = None) -> dict[str, float]:
    parameters = {
        key: float(default_value)
        for key, (default_value, _note) in DEFAULT_TUNING_PARAMETERS.items()
    }
    if overrides:
        parameters.update({key: float(value) for key, value in overrides.items()})
    return parameters


def load_runtime_db_char_rows_from_connection(conn: sqlite3.Connection) -> list[dict[str, object]]:
    rows = conn.execute(
        '''
        SELECT
            yime_code,
            hanzi AS text,
            pinyin_tone,
            COALESCE(tier_sort_weight, 0.0)
                + CASE WHEN is_common_reading = 1 THEN COALESCE(modern_common_boost, 0.0) ELSE 0.0 END
                + COALESCE(reading_phrase_prior_boost, 0.0)
                + COALESCE(char_frequency_abs, 0)
                + COALESCE(reading_weight, CASE WHEN is_common_reading = 1 THEN 1.0 ELSE 0.5 END) AS sort_weight,
            is_common_reading AS is_common,
            COALESCE(tier_sort_weight, 0.0) AS usage_tier_sort_boost,
            COALESCE(modern_common_boost, 0.0) AS modern_common_boost,
            COALESCE(reading_phrase_prior_boost, 0.0) AS reading_phrase_prior_boost,
            char_frequency_abs,
            char_frequency_rel,
            COALESCE(reading_weight, 1.0) AS reading_weight
        FROM char_lexicon
        WHERE yime_code IS NOT NULL AND TRIM(yime_code) <> ''
        '''
    ).fetchall()
    return [dict(row) for row in rows]


def build_scenario_summaries_from_rows(
    rows: list[dict[str, object]],
    *,
    page_size: int,
    include_codes: set[str] | None = None,
) -> dict[str, dict[str, float | int]]:
    by_code: dict[str, list[dict[str, object]]] = defaultdict(list)
    for row in rows:
        code = str(row.get("yime_code", "") or "").strip()
        if not code:
            continue
        if include_codes is not None and code not in include_codes:
            continue
        by_code[code].append(row)

    scenario_summaries: dict[str, dict[str, float | int]] = {}
    scenario_scorers = {
        "tier_only": lambda entry: float(entry.get("usage_tier_sort_boost", 0.0) or 0.0),
        "tier_plus_frequency": lambda entry: float(entry.get("usage_tier_sort_boost", 0.0) or 0.0)
        + float(entry.get("char_frequency_abs", 0) or 0),
        "tier_plus_frequency_plus_modern_common": lambda entry: float(entry.get("usage_tier_sort_boost", 0.0) or 0.0)
        + float(entry.get("char_frequency_abs", 0) or 0)
        + (float(entry.get("modern_common_boost", 0.0) or 0.0) if bool(entry.get("is_common")) else 0.0),
        "current_runtime": lambda entry: float(entry.get("usage_tier_sort_boost", 0.0) or 0.0)
        + float(entry.get("char_frequency_abs", 0) or 0)
        + (float(entry.get("modern_common_boost", 0.0) or 0.0) if bool(entry.get("is_common")) else 0.0)
        + float(entry.get("reading_phrase_prior_boost", 0.0) or 0.0)
        + float(entry.get("reading_weight", 1.0) or 1.0),
    }
    for scenario_name, scorer in scenario_scorers.items():
        weighted_candidate_sum = 0.0
        weighted_top1_sum = 0.0
        weighted_first_page_sum = 0.0
        bucket_count = 0
        for entries in by_code.values():
            ranked = sorted(entries, key=lambda entry: (-scorer(entry), str(entry.get("text", ""))))
            demand_weights = [float(entry.get("char_frequency_abs", 0.0) or 0.0) for entry in ranked]
            total_weight = sum(demand_weights)
            if total_weight <= 0:
                continue
            bucket_count += 1
            weighted_candidate_sum += total_weight
            weighted_top1_sum += demand_weights[0]
            weighted_first_page_sum += sum(demand_weights[:page_size])
        scenario_summaries[scenario_name] = {
            "bucket_count": bucket_count,
            "weighted_candidate_sum": weighted_candidate_sum,
            "weighted_top1_share": (weighted_top1_sum / weighted_candidate_sum) if weighted_candidate_sum else 0.0,
            "weighted_first_page_share": (weighted_first_page_sum / weighted_candidate_sum) if weighted_candidate_sum else 0.0,
        }
    return scenario_summaries


def build_high_collision_bucket_reference(
    rows: list[dict[str, object]],
    *,
    bucket_limit: int,
) -> list[dict[str, object]]:
    by_code: dict[str, list[dict[str, object]]] = defaultdict(list)
    for row in rows:
        code = str(row.get("yime_code", "") or "").strip()
        if not code:
            continue
        by_code[code].append(row)

    selected_codes = sorted(
        by_code.items(),
        key=lambda item: (
            -sum(float(entry.get("char_frequency_abs", 0.0) or 0.0) for entry in item[1]) * len(item[1]),
            -sum(float(entry.get("char_frequency_abs", 0.0) or 0.0) for entry in item[1]),
            -len(item[1]),
            item[0],
        ),
    )[:bucket_limit]
    payload: list[dict[str, object]] = []
    for code, entries in selected_codes:
        demand_weight_sum = sum(float(entry.get("char_frequency_abs", 0.0) or 0.0) for entry in entries)
        collision_demand_score = demand_weight_sum * len(entries)
        ranked = sorted(
            entries,
            key=lambda entry: (
                -(
                    float(entry.get("usage_tier_sort_boost", 0.0) or 0.0)
                    + float(entry.get("char_frequency_abs", 0) or 0)
                    + (float(entry.get("modern_common_boost", 0.0) or 0.0) if bool(entry.get("is_common")) else 0.0)
                    + float(entry.get("reading_phrase_prior_boost", 0.0) or 0.0)
                    + float(entry.get("reading_weight", 1.0) or 1.0)
                ),
                str(entry.get("text", "")),
            ),
        )
        payload.append(
            {
                "yime_code": code,
                "pinyin_tone": str(entries[0].get("pinyin_tone", "") or ""),
                "candidate_count": len(entries),
                "demand_weight_sum": demand_weight_sum,
                "collision_demand_score": collision_demand_score,
                "top_current_runtime_texts": [str(entry.get("text", "")) for entry in ranked[:8]],
            }
        )
    return payload


def pareto_frontier(
    rows: list[dict[str, float | int]],
    *,
    metric_keys: tuple[str, ...],
) -> list[dict[str, float | int]]:
    frontier: list[dict[str, float | int]] = []
    for candidate in rows:
        dominated = False
        for other in rows:
            if other is candidate:
                continue
            if all(float(other[key]) >= float(candidate[key]) for key in metric_keys) and any(
                float(other[key]) > float(candidate[key]) for key in metric_keys
            ):
                dominated = True
                break
        if not dominated:
            frontier.append(candidate)
    frontier.sort(
        key=lambda item: (
            -float(item["weighted_first_page_share"]),
            -float(item["high_collision_weighted_first_page_share"]),
            -float(item["weighted_top1_share"]),
            -float(item["high_collision_weighted_top1_share"]),
        )
    )
    return frontier


def build_scan_recommendations(
    results: list[dict[str, float | int]],
    *,
    global_first_page_tolerance: float,
    global_top1_tolerance: float,
    local_first_page_tolerance: float,
    local_top1_tolerance: float,
) -> dict[str, object]:
    global_non_regression = [
        row for row in results if float(row["delta_vs_modern_first_page"]) >= 0.0
    ]
    local_non_regression = [
        row
        for row in global_non_regression
        if float(row["high_collision_delta_vs_modern_first_page"]) >= 0.0
    ]
    local_improvement = [
        row
        for row in global_non_regression
        if float(row["high_collision_delta_vs_modern_first_page"]) > 0.0
        or float(row["high_collision_delta_vs_modern_top1"]) > 0.0
    ]
    strict_usable = [
        row
        for row in global_non_regression
        if float(row["delta_vs_modern_top1"]) >= 0.0
        and float(row["high_collision_delta_vs_modern_first_page"]) >= 0.0
        and float(row["high_collision_delta_vs_modern_top1"]) >= 0.0
    ]
    tolerant_usable = [
        row
        for row in results
        if float(row["delta_vs_modern_first_page"]) >= -global_first_page_tolerance
        and float(row["delta_vs_modern_top1"]) >= -global_top1_tolerance
        and float(row["high_collision_delta_vs_modern_first_page"]) >= -local_first_page_tolerance
        and float(row["high_collision_delta_vs_modern_top1"]) >= -local_top1_tolerance
    ]
    strict_usable.sort(
        key=lambda row: (
            -float(row["weighted_first_page_share"]),
            -float(row["high_collision_weighted_first_page_share"]),
            -float(row["weighted_top1_share"]),
            -float(row["high_collision_weighted_top1_share"]),
        )
    )
    tolerant_usable.sort(
        key=lambda row: (
            -float(row["weighted_first_page_share"]),
            -float(row["high_collision_weighted_first_page_share"]),
            -float(row["weighted_top1_share"]),
            -float(row["high_collision_weighted_top1_share"]),
        )
    )
    pareto_source = local_improvement or local_non_regression or global_non_regression or results
    frontier = pareto_frontier(
        pareto_source,
        metric_keys=(
            "weighted_first_page_share",
            "high_collision_weighted_first_page_share",
            "weighted_top1_share",
            "high_collision_weighted_top1_share",
        ),
    )
    return {
        "global_non_regression_count": len(global_non_regression),
        "local_non_regression_count": len(local_non_regression),
        "local_improvement_count": len(local_improvement),
        "strict_usable_count": len(strict_usable),
        "tolerant_usable_count": len(tolerant_usable),
        "tolerances": {
            "global_first_page": global_first_page_tolerance,
            "global_top1": global_top1_tolerance,
            "local_first_page": local_first_page_tolerance,
            "local_top1": local_top1_tolerance,
        },
        "pareto_source": (
            "local_improvement"
            if local_improvement
            else "local_non_regression"
            if local_non_regression
            else "global_non_regression"
            if global_non_regression
            else "all_results"
        ),
        "strict_usable": strict_usable,
        "tolerant_usable": tolerant_usable,
        "pareto_frontier": frontier,
        "best_global_first_page": max(
            results,
            key=lambda row: (
                float(row["weighted_first_page_share"]),
                float(row["weighted_top1_share"]),
            ),
        )
        if results
        else None,
        "best_local_first_page": max(
            results,
            key=lambda row: (
                float(row["high_collision_weighted_first_page_share"]),
                float(row["high_collision_weighted_top1_share"]),
            ),
        )
        if results
        else None,
    }


def build_char_ordering_comparison_from_connection(
    conn: sqlite3.Connection,
    *,
    page_size: int,
    high_collision_bucket_limit: int = 20,
) -> dict[str, object]:
    rows = load_runtime_db_char_rows_from_connection(conn)
    scenario_summaries = build_scenario_summaries_from_rows(rows, page_size=page_size)

    high_collision_buckets = build_high_collision_bucket_reference(
        rows,
        bucket_limit=high_collision_bucket_limit,
    )
    high_collision_codes = {str(bucket["yime_code"]) for bucket in high_collision_buckets}
    local_summaries = build_scenario_summaries_from_rows(
        rows,
        page_size=page_size,
        include_codes=high_collision_codes,
    )

    tier_plus_frequency_plus_modern_common = scenario_summaries["tier_plus_frequency_plus_modern_common"]
    current_runtime = scenario_summaries["current_runtime"]
    local_modern = local_summaries["tier_plus_frequency_plus_modern_common"]
    local_current = local_summaries["current_runtime"]
    return {
        "tier_plus_frequency_plus_modern_common": tier_plus_frequency_plus_modern_common,
        "current_runtime": current_runtime,
        "delta_current_runtime_vs_modern_common": {
            "weighted_top1_share": float(current_runtime["weighted_top1_share"]) - float(tier_plus_frequency_plus_modern_common["weighted_top1_share"]),
            "weighted_first_page_share": float(current_runtime["weighted_first_page_share"]) - float(tier_plus_frequency_plus_modern_common["weighted_first_page_share"]),
        },
        "high_collision_focus": {
            "bucket_limit": high_collision_bucket_limit,
            "buckets": high_collision_buckets,
            "tier_plus_frequency_plus_modern_common": local_modern,
            "current_runtime": local_current,
            "delta_current_runtime_vs_modern_common": {
                "weighted_top1_share": float(local_current["weighted_top1_share"]) - float(local_modern["weighted_top1_share"]),
                "weighted_first_page_share": float(local_current["weighted_first_page_share"]) - float(local_modern["weighted_first_page_share"]),
            },
        },
    }


def format_pct(value: float) -> str:
    return f"{value * 100:.2f}%"


def build_runtime_tuning_scan_markdown(payload: dict[str, object], *, limit: int) -> str:
    baseline = payload["baseline"]
    local_baseline = baseline["high_collision_focus"]
    recommendations = payload["recommendations"]
    tolerances = recommendations["tolerances"]
    default_tuning = payload.get("default_tuning") or {}
    lines = [
        "# Runtime Tuning Scan",
        "",
        f"- generated_at: `{payload['generated_at']}`",
        f"- combinations: `{payload['combination_count']}`",
        f"- page_size: `{payload['page_size']}`",
        f"- high_collision_bucket_limit: `{payload['high_collision_bucket_limit']}`",
        f"- global baseline modern_common: top1 `{format_pct(float(baseline['tier_plus_frequency_plus_modern_common']['weighted_top1_share']))}`, first-page `{format_pct(float(baseline['tier_plus_frequency_plus_modern_common']['weighted_first_page_share']))}`",
        f"- local baseline modern_common: top1 `{format_pct(float(local_baseline['tier_plus_frequency_plus_modern_common']['weighted_top1_share']))}`, first-page `{format_pct(float(local_baseline['tier_plus_frequency_plus_modern_common']['weighted_first_page_share']))}`",
        (
            f"- current_default_tuning: `cw={float(default_tuning['common_reading_weight']):.2f}, uw={float(default_tuning['uncommon_reading_weight']):.2f}, scale={float(default_tuning['phrase_reading_prior_scale']):.2f}, share>={float(default_tuning['phrase_reading_prior_min_share']):.3f}, count>={int(round(float(default_tuning['phrase_reading_prior_min_phrase_count'])))}, evidence>={float(default_tuning['phrase_reading_prior_min_evidence_weight']):.2f}`"
            if default_tuning
            else "- current_default_tuning: `<unavailable>`"
        ),
        "",
        "## Recommendation Summary",
        "",
        f"- pareto_source: `{recommendations['pareto_source']}`",
        f"- global_non_regression_count: `{recommendations['global_non_regression_count']}`",
        f"- local_non_regression_count: `{recommendations['local_non_regression_count']}`",
        f"- local_improvement_count: `{recommendations['local_improvement_count']}`",
        f"- strict_usable_count: `{recommendations['strict_usable_count']}`",
        f"- tolerant_usable_count: `{recommendations['tolerant_usable_count']}`",
        f"- tolerance_band: `global_first_page>={-float(tolerances['global_first_page']):.6f}, global_top1>={-float(tolerances['global_top1']):.6f}, local_first_page>={-float(tolerances['local_first_page']):.6f}, local_top1>={-float(tolerances['local_top1']):.6f}`",
    ]
    if recommendations["best_global_first_page"]:
        best_global = recommendations["best_global_first_page"]
        lines.append(
            f"- best_global_first_page: `cw={best_global['common_reading_weight']:.2f}, scale={best_global['phrase_reading_prior_scale']:.2f}, share>={best_global['phrase_reading_prior_min_share']:.3f}, count>={best_global['phrase_reading_prior_min_phrase_count']}, evidence>={best_global['phrase_reading_prior_min_evidence_weight']:.2f}, first-page={format_pct(float(best_global['weighted_first_page_share']))}`"
        )
    if recommendations["best_local_first_page"]:
        best_local = recommendations["best_local_first_page"]
        lines.append(
            f"- best_local_first_page: `cw={best_local['common_reading_weight']:.2f}, scale={best_local['phrase_reading_prior_scale']:.2f}, share>={best_local['phrase_reading_prior_min_share']:.3f}, count>={best_local['phrase_reading_prior_min_phrase_count']}, evidence>={best_local['phrase_reading_prior_min_evidence_weight']:.2f}, local_first-page={format_pct(float(best_local['high_collision_weighted_first_page_share']))}`"
        )
    lines.extend(
        [
            "",
            "## Tolerance-Usable Combinations",
            "",
        ]
    )
    if recommendations["tolerant_usable"]:
        lines.extend(
            [
                "| rank | cw | uw | scale | share | count | evidence | Δglobal top1 | Δglobal first-page | Δlocal top1 | Δlocal first-page |",
                "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
            ]
        )
        for index, row in enumerate(recommendations["tolerant_usable"][:limit], start=1):
            lines.append(
                "| "
                f"{index} | {row['common_reading_weight']:.2f} | {row['uncommon_reading_weight']:.2f} | {row['phrase_reading_prior_scale']:.2f} | "
                f"{row['phrase_reading_prior_min_share']:.3f} | {row['phrase_reading_prior_min_phrase_count']} | {row['phrase_reading_prior_min_evidence_weight']:.2f} | "
                f"{format_pct(float(row['delta_vs_modern_top1']))} | {format_pct(float(row['delta_vs_modern_first_page']))} | "
                f"{format_pct(float(row['high_collision_delta_vs_modern_top1']))} | {format_pct(float(row['high_collision_delta_vs_modern_first_page']))} |"
            )
    else:
        lines.append("No tolerance-usable combinations found under the current tolerance band.")
    lines.extend(
        [
            "",
            "## Strictly Usable Combinations",
            "",
        ]
    )
    if recommendations["strict_usable"]:
        lines.extend(
            [
                "| rank | cw | uw | scale | share | count | evidence | global top1 | global first-page | local top1 | local first-page |",
                "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
            ]
        )
        for index, row in enumerate(recommendations["strict_usable"][:limit], start=1):
            lines.append(
                "| "
                f"{index} | {row['common_reading_weight']:.2f} | {row['uncommon_reading_weight']:.2f} | {row['phrase_reading_prior_scale']:.2f} | "
                f"{row['phrase_reading_prior_min_share']:.3f} | {row['phrase_reading_prior_min_phrase_count']} | {row['phrase_reading_prior_min_evidence_weight']:.2f} | "
                f"{format_pct(float(row['weighted_top1_share']))} | {format_pct(float(row['weighted_first_page_share']))} | "
                f"{format_pct(float(row['high_collision_weighted_top1_share']))} | {format_pct(float(row['high_collision_weighted_first_page_share']))} |"
            )
    else:
        lines.append("No strictly usable combinations found under the current grid.")
    lines.extend(
        [
            "",
            "## Pareto Frontier",
            "",
            "| rank | cw | uw | scale | share | count | evidence | global first-page | Δglobal first-page | local first-page | Δlocal first-page |",
            "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
        ]
    )
    for index, row in enumerate(recommendations["pareto_frontier"][:limit], start=1):
        lines.append(
            "| "
            f"{index} | {row['common_reading_weight']:.2f} | {row['uncommon_reading_weight']:.2f} | {row['phrase_reading_prior_scale']:.2f} | "
            f"{row['phrase_reading_prior_min_share']:.3f} | {row['phrase_reading_prior_min_phrase_count']} | {row['phrase_reading_prior_min_evidence_weight']:.2f} | "
            f"{format_pct(float(row['weighted_first_page_share']))} | {format_pct(float(row['delta_vs_modern_first_page']))} | "
            f"{format_pct(float(row['high_collision_weighted_first_page_share']))} | {format_pct(float(row['high_collision_delta_vs_modern_first_page']))} |"
        )
    lines.extend(
        [
            "",
        "## Top Results",
        "",
        "| rank | cw | uw | scale | share | count | evidence | enabled | global top1 | global first-page | Δglobal first-page | local top1 | local first-page | Δlocal first-page |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
        ]
    )
    for index, row in enumerate(payload["results"][:limit], start=1):
        lines.append(
            "| "
            f"{index} | {row['common_reading_weight']:.2f} | {row['uncommon_reading_weight']:.2f} | {row['phrase_reading_prior_scale']:.2f} | "
            f"{row['phrase_reading_prior_min_share']:.3f} | {row['phrase_reading_prior_min_phrase_count']} | {row['phrase_reading_prior_min_evidence_weight']:.2f} | "
            f"{row['enabled_rows']} | {format_pct(float(row['weighted_top1_share']))} | {format_pct(float(row['weighted_first_page_share']))} | "
            f"{format_pct(float(row['delta_vs_modern_first_page']))} | {format_pct(float(row['high_collision_weighted_top1_share']))} | "
            f"{format_pct(float(row['high_collision_weighted_first_page_share']))} | {format_pct(float(row['high_collision_delta_vs_modern_first_page']))} |"
        )
    lines.extend(
        [
            "",
            "## High Collision Buckets",
            "",
            "| pinyin_tone | yime_code | candidates | demand_weight_sum | collision_demand_score | current_runtime_top_texts |",
            "| --- | --- | ---: | ---: | ---: | --- |",
        ]
    )
    for bucket in payload["baseline"]["high_collision_focus"]["buckets"]:
        lines.append(
            f"| {bucket['pinyin_tone']} | {bucket['yime_code']} | {bucket['candidate_count']} | {bucket['demand_weight_sum']:.0f} | {bucket['collision_demand_score']:.0f} | {'、'.join(bucket['top_current_runtime_texts'])} |"
        )
    lines.append("")
    return "\n".join(lines)


def write_runtime_tuning_scan_outputs(
    payload: dict[str, object],
    *,
    json_output: Path,
    markdown_output: Path,
    limit: int,
) -> None:
    json_output.parent.mkdir(parents=True, exist_ok=True)
    markdown_output.parent.mkdir(parents=True, exist_ok=True)
    json_output.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    markdown_output.write_text(
        build_runtime_tuning_scan_markdown(payload, limit=limit),
        encoding="utf-8",
    )


def scan_runtime_tuning_parameters(
    conn: sqlite3.Connection,
    *,
    page_size: int,
    limit: int,
    reading_weight_magnitudes: list[float],
    prior_scale_values: list[float],
    prior_share_values: list[float],
    prior_min_phrase_count_values: list[int],
    prior_min_evidence_weight_values: list[float],
    high_collision_bucket_limit: int,
    global_first_page_tolerance: float,
    global_top1_tolerance: float,
    local_first_page_tolerance: float,
    local_top1_tolerance: float,
) -> dict[str, object]:
    base_tuning = load_runtime_tuning_parameters(conn)
    baseline_comparison = build_char_ordering_comparison_from_connection(
        conn,
        page_size=page_size,
        high_collision_bucket_limit=high_collision_bucket_limit,
    )
    baseline_modern = baseline_comparison["tier_plus_frequency_plus_modern_common"]
    baseline_local_modern = baseline_comparison["high_collision_focus"]["tier_plus_frequency_plus_modern_common"]
    combinations = list(
        product(
            reading_weight_magnitudes,
            prior_scale_values,
            prior_share_values,
            prior_min_phrase_count_values,
            prior_min_evidence_weight_values,
        )
    )

    results: list[dict[str, float | int]] = []
    for magnitude, prior_scale, min_share, min_phrase_count, min_evidence_weight in combinations:
        overrides = build_effective_tuning_parameters(
            {
                **base_tuning,
                "common_reading_weight": float(magnitude),
                "uncommon_reading_weight": -float(magnitude),
                "phrase_reading_prior_scale": float(prior_scale),
                "phrase_reading_prior_min_share": float(min_share),
                "phrase_reading_prior_min_phrase_count": float(min_phrase_count),
                "phrase_reading_prior_min_evidence_weight": float(min_evidence_weight),
            }
        )
        conn.execute("SAVEPOINT runtime_tuning_scan")
        try:
            upsert_runtime_tuning_parameters(conn, overrides)
            rebuild_char_pinyin_reading_weights(conn, overrides)
            reading_prior_stats = rebuild_char_reading_prior(conn, overrides)
            comparison = build_char_ordering_comparison_from_connection(
                conn,
                page_size=page_size,
                high_collision_bucket_limit=high_collision_bucket_limit,
            )
            current_runtime = comparison["current_runtime"]
            modern_delta = comparison["delta_current_runtime_vs_modern_common"]
            local_current = comparison["high_collision_focus"]["current_runtime"]
            local_delta = comparison["high_collision_focus"]["delta_current_runtime_vs_modern_common"]
            results.append(
                {
                    "common_reading_weight": float(magnitude),
                    "uncommon_reading_weight": -float(magnitude),
                    "phrase_reading_prior_scale": float(prior_scale),
                    "phrase_reading_prior_min_share": float(min_share),
                    "phrase_reading_prior_min_phrase_count": int(min_phrase_count),
                    "phrase_reading_prior_min_evidence_weight": float(min_evidence_weight),
                    "enabled_rows": int(reading_prior_stats["enabled_rows"]),
                    "weighted_top1_share": float(current_runtime["weighted_top1_share"]),
                    "weighted_first_page_share": float(current_runtime["weighted_first_page_share"]),
                    "delta_vs_modern_top1": float(modern_delta["weighted_top1_share"]),
                    "delta_vs_modern_first_page": float(modern_delta["weighted_first_page_share"]),
                    "high_collision_weighted_top1_share": float(local_current["weighted_top1_share"]),
                    "high_collision_weighted_first_page_share": float(local_current["weighted_first_page_share"]),
                    "high_collision_delta_vs_modern_top1": float(local_delta["weighted_top1_share"]),
                    "high_collision_delta_vs_modern_first_page": float(local_delta["weighted_first_page_share"]),
                }
            )
        finally:
            conn.execute("ROLLBACK TO runtime_tuning_scan")
            conn.execute("RELEASE runtime_tuning_scan")

    results.sort(
        key=lambda item: (
            abs(float(item["delta_vs_modern_first_page"])),
            abs(float(item["high_collision_delta_vs_modern_first_page"])),
            abs(float(item["delta_vs_modern_top1"])),
            abs(float(item["high_collision_delta_vs_modern_top1"])),
            -float(item["weighted_first_page_share"]),
            -float(item["high_collision_weighted_first_page_share"]),
            -float(item["weighted_top1_share"]),
        )
    )

    print(
        "扫描基线: "
        f"modern_common top1 {format_pct(float(baseline_modern['weighted_top1_share']))}，"
        f"first-page {format_pct(float(baseline_modern['weighted_first_page_share']))}；"
        f"高碰撞桶 top1 {format_pct(float(baseline_local_modern['weighted_top1_share']))}，"
        f"first-page {format_pct(float(baseline_local_modern['weighted_first_page_share']))}；"
        f"组合数 {len(combinations)}"
    )
    print("排名先按全局首屏偏离排序，再看高碰撞桶局部偏离；越靠前越接近全局稳定且局部不跑偏的弱先验区间。")
    for index, row in enumerate(results[:limit], start=1):
        print(
            f"[{index}] cw={row['common_reading_weight']:.2f} "
            f"uw={row['uncommon_reading_weight']:.2f} "
            f"scale={row['phrase_reading_prior_scale']:.2f} "
            f"share>={row['phrase_reading_prior_min_share']:.3f} "
            f"count>={row['phrase_reading_prior_min_phrase_count']} "
            f"evidence>={row['phrase_reading_prior_min_evidence_weight']:.2f} "
            f"enabled={row['enabled_rows']} "
            f"top1={format_pct(float(row['weighted_top1_share']))} "
            f"first-page={format_pct(float(row['weighted_first_page_share']))} "
            f"Δmodern_top1={format_pct(float(row['delta_vs_modern_top1']))} "
            f"Δmodern_first-page={format_pct(float(row['delta_vs_modern_first_page']))} "
            f"local_top1={format_pct(float(row['high_collision_weighted_top1_share']))} "
            f"local_first-page={format_pct(float(row['high_collision_weighted_first_page_share']))} "
            f"Δlocal_first-page={format_pct(float(row['high_collision_delta_vs_modern_first_page']))}"
        )

    recommendations = build_scan_recommendations(
        results,
        global_first_page_tolerance=global_first_page_tolerance,
        global_top1_tolerance=global_top1_tolerance,
        local_first_page_tolerance=local_first_page_tolerance,
        local_top1_tolerance=local_top1_tolerance,
    )
    return {
        "generated_at": datetime.now().isoformat() + "Z",
        "page_size": page_size,
        "high_collision_bucket_limit": high_collision_bucket_limit,
        "combination_count": len(combinations),
        "default_tuning": {
            key: float(base_tuning[key])
            for key in (
                "common_reading_weight",
                "uncommon_reading_weight",
                "phrase_reading_prior_scale",
                "phrase_reading_prior_min_share",
                "phrase_reading_prior_min_phrase_count",
                "phrase_reading_prior_min_evidence_weight",
            )
            if key in base_tuning
        },
        "baseline": baseline_comparison,
        "recommendations": recommendations,
        "results": results,
    }


def rebuild_char_modern_common_profile(conn: sqlite3.Connection, tuning_parameters: dict[str, float]) -> Counter:
    existing_chars = {
        str(row[0] or "")
        for row in conn.execute("SELECT hanzi FROM char_inventory")
        if str(row[0] or "")
    }
    modern_rank_by_char = load_single_char_word_ranks(DEFAULT_BLCU_CHAR_FREQ_SOURCE)
    max_rank = int(tuning_parameters.get("modern_common_max_rank", MODERN_COMMON_MAX_RANK))
    rank_divisor = float(tuning_parameters.get("modern_common_rank_divisor", MODERN_COMMON_RANK_DIVISOR)) or 1.0

    rows = []
    for hanzi, rank in sorted(modern_rank_by_char.items(), key=lambda item: (item[1], item[0])):
        if hanzi not in existing_chars:
            continue
        if rank > max_rank:
            continue
        boost = max(max_rank - rank, 0) / rank_divisor
        rows.append((hanzi, rank, float(boost), "blcu_bcc_single_char_rank"))

    conn.execute("DELETE FROM char_modern_common_profile")
    if rows:
        conn.executemany(
            '''
            INSERT INTO char_modern_common_profile (
                hanzi,
                modern_common_rank,
                modern_common_boost,
                source_note,
                updated_at
            ) VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)
            ''',
            rows,
        )

    stats = Counter()
    stats["total"] = len(rows)
    stats["threshold"] = max_rank
    return stats


def rebuild_char_pinyin_reading_weights(conn: sqlite3.Connection, tuning_parameters: dict[str, float]) -> Counter:
    rows = conn.execute(
        '''
        SELECT rowid, is_common_reading
        FROM char_pinyin_map
        '''
    ).fetchall()

    updates: list[tuple[float, int]] = []
    stats = Counter()
    common_weight = float(tuning_parameters.get("common_reading_weight", COMMON_READING_WEIGHT))
    uncommon_weight = float(tuning_parameters.get("uncommon_reading_weight", UNCOMMON_READING_WEIGHT))
    for rowid, is_common_reading in rows:
        common_flag = int(is_common_reading or 0)
        reading_weight = common_weight if common_flag == 1 else uncommon_weight
        updates.append((reading_weight, int(rowid)))
        stats["common"] += 1 if common_flag == 1 else 0
        stats["uncommon"] += 1 if common_flag == 0 else 0

    if updates:
        conn.executemany(
            '''
            UPDATE char_pinyin_map
            SET reading_weight = ?,
                updated_at = CURRENT_TIMESTAMP
            WHERE rowid = ?
            ''',
            updates,
        )

    stats["total"] = len(updates)
    return stats


def reading_prior_is_enabled(
    *,
    reading_share: float,
    phrase_count: int,
    evidence_weight: float,
    min_share: float,
    min_phrase_count: int,
    min_evidence_weight: float,
) -> bool:
    return (
        reading_share >= min_share
        and phrase_count >= min_phrase_count
        and evidence_weight >= min_evidence_weight
    )


def rebuild_char_reading_prior(conn: sqlite3.Connection, tuning_parameters: dict[str, float]) -> Counter:
    existing_chars = {
        str(row[0] or "")
        for row in conn.execute("SELECT hanzi FROM char_inventory")
        if str(row[0] or "")
    }
    phrase_rows = conn.execute(
        '''
        SELECT pi.phrase, ppm.pinyin_tone, COALESCE(pi.phrase_frequency, 0)
        FROM phrase_inventory AS pi
        JOIN phrase_pinyin_map AS ppm
            ON ppm.phrase_id = pi.id
        LEFT JOIN phrase_reading_preference AS pref
            ON pref.phrase = pi.phrase
        WHERE (
            pref.phrase IS NOT NULL
            AND ppm.pinyin_tone = pref.preferred_pinyin_tone
        ) OR (
            pref.phrase IS NULL
            AND ppm.reading_rank = 1
        )
        '''
    ).fetchall()

    evidence_by_pair: dict[tuple[str, str], float] = defaultdict(float)
    phrase_count_by_pair: Counter[tuple[str, str]] = Counter()
    total_by_char: dict[str, float] = defaultdict(float)
    stats = Counter()

    for phrase, pinyin_tone, phrase_frequency in phrase_rows:
        text = str(phrase or "")
        syllables = [segment for segment in str(pinyin_tone or "").split() if segment]
        if not text or not syllables or len(text) != len(syllables):
            stats["skipped_mismatched_phrase_rows"] += 1
            continue
        frequency = int(phrase_frequency or 0)
        stats["phrase_rows"] += 1
        for hanzi, syllable in zip(text, syllables, strict=False):
            if hanzi not in existing_chars:
                continue
            evidence_by_pair[(hanzi, syllable)] += frequency
            phrase_count_by_pair[(hanzi, syllable)] += 1
            total_by_char[hanzi] += frequency

    prior_scale = float(tuning_parameters.get("phrase_reading_prior_scale", PHRASE_READING_PRIOR_SCALE))
    min_share = float(tuning_parameters.get("phrase_reading_prior_min_share", PHRASE_READING_PRIOR_MIN_SHARE))
    min_phrase_count = int(
        round(
            float(
                tuning_parameters.get(
                    "phrase_reading_prior_min_phrase_count",
                    PHRASE_READING_PRIOR_MIN_PHRASE_COUNT,
                )
            )
        )
    )
    min_evidence_weight = float(
        tuning_parameters.get(
            "phrase_reading_prior_min_evidence_weight",
            PHRASE_READING_PRIOR_MIN_EVIDENCE_WEIGHT,
        )
    )
    rows = []
    for (hanzi, syllable), evidence_weight in sorted(evidence_by_pair.items(), key=lambda item: (item[0][0], item[0][1])):
        char_total = total_by_char.get(hanzi, 0.0)
        if char_total <= 0:
            continue
        reading_share = evidence_weight / char_total
        phrase_count = int(phrase_count_by_pair[(hanzi, syllable)])
        prior_boost = (
            reading_share * prior_scale
            if reading_prior_is_enabled(
                reading_share=reading_share,
                phrase_count=phrase_count,
                evidence_weight=float(evidence_weight),
                min_share=min_share,
                min_phrase_count=min_phrase_count,
                min_evidence_weight=min_evidence_weight,
            )
            else 0.0
        )
        rows.append((
            hanzi,
            syllable,
            phrase_count,
            float(evidence_weight),
            float(reading_share),
            float(prior_boost),
            "phrase_inventory_selected_readings",
        ))

    conn.execute("DELETE FROM char_reading_prior")
    if rows:
        conn.executemany(
            '''
            INSERT INTO char_reading_prior (
                hanzi,
                pinyin_tone,
                phrase_count,
                evidence_weight,
                reading_share,
                prior_boost,
                source_note,
                updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
            ''',
            rows,
        )

    stats["pair_rows"] = len(rows)
    stats["covered_chars"] = len({hanzi for hanzi, _syllable in evidence_by_pair})
    stats["enabled_rows"] = sum(1 for _hanzi, _syllable, _phrase_count, _evidence_weight, _reading_share, prior_boost, _source_note in rows if float(prior_boost) > 0.0)
    stats["min_share"] = min_share
    stats["min_phrase_count"] = min_phrase_count
    stats["min_evidence_weight"] = min_evidence_weight
    return stats


def build_phrase_support_by_char(conn: sqlite3.Connection) -> dict[str, float]:
    support_by_char: dict[str, float] = defaultdict(float)
    rows = conn.execute(
        '''
        SELECT phrase, COALESCE(phrase_frequency, 0)
        FROM phrase_inventory
        WHERE phrase IS NOT NULL AND phrase <> ''
        '''
    ).fetchall()
    for row in rows:
        phrase = str(row[0] or "")
        if not phrase:
            continue
        frequency = float(row[1] or 1.0)
        for hanzi in phrase:
            support_by_char[hanzi] += frequency
    return dict(support_by_char)


def build_char_usage_profile_rows(conn: sqlite3.Connection) -> list[tuple[str, str, int, float, str]]:
    existing_chars = {
        str(row[0] or "")
        for row in conn.execute("SELECT hanzi FROM char_inventory")
        if str(row[0] or "")
    }
    if not existing_chars:
        return []

    tghz_freq = load_tghz2013_char_frequencies(DEFAULT_UNIHAN_READINGS_DB_PATH)
    sorted_tghz_chars = [
        hanzi
        for hanzi, _frequency in sorted(
            (
                (hanzi, frequency)
                for hanzi, frequency in tghz_freq.items()
                if hanzi in existing_chars
            ),
            key=lambda item: (-item[1], item[0]),
        )[: COMMON_HIGH_COUNT + COMMON_LOW_COUNT + SPECIAL_HIGH_COUNT]
    ]

    dictionary_chars = load_dictionary_chars(DEFAULT_XHC1983_SOURCE) & existing_chars
    single_char_word_freq = load_char_inventory_frequencies(conn)
    phrase_support = build_phrase_support_by_char(conn)

    high_common_chars = sorted_tghz_chars[:COMMON_HIGH_COUNT]
    low_common_chars = sorted_tghz_chars[COMMON_HIGH_COUNT:COMMON_HIGH_COUNT + COMMON_LOW_COUNT]
    high_special_chars = sorted_tghz_chars[
        COMMON_HIGH_COUNT + COMMON_LOW_COUNT:
        COMMON_HIGH_COUNT + COMMON_LOW_COUNT + SPECIAL_HIGH_COUNT
    ]

    assigned_chars = set(high_common_chars) | set(low_common_chars) | set(high_special_chars)
    remaining_chars = sorted(
        existing_chars - assigned_chars,
        key=lambda hanzi: (
            0 if hanzi in dictionary_chars else 1,
            0 if hanzi in single_char_word_freq else 1,
            -single_char_word_freq.get(hanzi, 0),
            -phrase_support.get(hanzi, 0.0),
            hanzi,
        ),
    )
    low_special_chars = remaining_chars[:SPECIAL_LOW_COUNT]
    rare_chars = remaining_chars[SPECIAL_LOW_COUNT:]

    rows: list[tuple[str, str, int, float, str]] = []

    def append_rows(chars: list[str], tier_name: str, source_note: str) -> None:
        base_weight = TIER_BASE_WEIGHTS[tier_name]
        tier_size = len(chars)
        for index, hanzi in enumerate(chars, start=1):
            residual_rank_weight = max(tier_size - index, 0) / 10_000.0
            rows.append((
                hanzi,
                tier_name,
                index,
                base_weight + residual_rank_weight,
                source_note,
            ))

    append_rows(high_common_chars, "common_high", "tghz2013_bcc_frequency_top_3500")
    append_rows(low_common_chars, "common_low", "tghz2013_bcc_frequency_3501_6500")
    append_rows(high_special_chars, "special_high", "tghz2013_bcc_frequency_6501_8105")
    append_rows(low_special_chars, "special_low", "dictionary_and_lexicon_support_to_13000")
    append_rows(rare_chars, "rare", "out_of_primary_13000")
    return rows


def rebuild_char_usage_profile(conn: sqlite3.Connection) -> Counter:
    rows = build_char_usage_profile_rows(conn)
    conn.execute("DELETE FROM char_usage_profile")
    if rows:
        conn.executemany(
            '''
            INSERT INTO char_usage_profile (
                hanzi,
                usage_tier,
                tier_rank,
                tier_sort_weight,
                source_note,
                updated_at
            ) VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
            ''',
            rows,
        )

    stats = Counter()
    for _hanzi, usage_tier, _tier_rank, _tier_sort_weight, _source_note in rows:
        stats[usage_tier] += 1
    stats["total"] = len(rows)
    return stats


def rebuild_materialized_runtime_candidates(conn: sqlite3.Connection) -> int:
    conn.execute("DELETE FROM runtime_candidates_materialized")
    conn.execute(
        '''
        INSERT INTO runtime_candidates_materialized (
            entry_type,
            entry_id,
            text,
            pinyin_tone,
            yime_code,
            sort_weight,
            is_common,
            text_length,
            updated_at
        )
        SELECT
            entry_type,
            entry_id,
            text,
            pinyin_tone,
            yime_code,
            sort_weight,
            is_common,
            text_length,
            updated_at
        FROM runtime_candidates
        WHERE yime_code IS NOT NULL
          AND TRIM(yime_code) <> ''
        '''
    )
    row = conn.execute(
        "SELECT COUNT(*) FROM runtime_candidates_materialized"
    ).fetchone()
    return int(row[0]) if row is not None else 0


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
    report_missing_optional_external_frequency_sources()
    db_path = Path(args.db).resolve()
    repo_root = REPO_ROOT

    if not db_path.exists():
        print(f"未找到数据库: {db_path}", file=sys.stderr)
        return 1

    canonical_code_map = load_canonical_code_map(repo_root)
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    try:
        conn.executescript(SCHEMA_PATH.read_text(encoding="utf-8"))
        if args.scan_runtime_tuning:
            scan_payload = scan_runtime_tuning_parameters(
                conn,
                page_size=args.scan_page_size,
                limit=args.scan_limit,
                reading_weight_magnitudes=parse_float_list(args.scan_reading_weight_magnitudes),
                prior_scale_values=parse_float_list(args.scan_prior_scale_values),
                prior_share_values=parse_float_list(args.scan_prior_share_values),
                prior_min_phrase_count_values=parse_int_list(args.scan_prior_min_phrase_count_values),
                prior_min_evidence_weight_values=parse_float_list(args.scan_prior_min_evidence_weight_values),
                high_collision_bucket_limit=args.scan_high_collision_bucket_limit,
                global_first_page_tolerance=float(args.scan_global_first_page_tolerance),
                global_top1_tolerance=float(args.scan_global_top1_tolerance),
                local_first_page_tolerance=float(args.scan_local_first_page_tolerance),
                local_top1_tolerance=float(args.scan_local_top1_tolerance),
            )
            json_output = Path(args.scan_json_output).resolve()
            markdown_output = Path(args.scan_markdown_output).resolve()
            write_runtime_tuning_scan_outputs(
                scan_payload,
                json_output=json_output,
                markdown_output=markdown_output,
                limit=args.scan_limit,
            )
            print(f"已导出扫描 JSON: {json_output}")
            print(f"已导出扫描 Markdown: {markdown_output}")
            print(f"扫描完成，共评估 {scan_payload['combination_count']} 组参数组合")
            return 0
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
            backup_path, removed_backups = backup_database(
                db_path,
                retain_count=args.backup_retain,
            )
            print(f"已创建数据库备份: {backup_path}")
            if removed_backups:
                print(
                    f"已清理旧备份 {len(removed_backups)} 份，当前保留最近 {args.backup_retain} 份。"
                )

        canonical_mapping_count = sync_canonical_mapping_table(conn, repo_root)
        print(f"已同步 canonical pinyin_yime_code 行: {canonical_mapping_count}")
        print(f"已同步 phrase_reading_preference 行: {preferred_phrase_count}")
        tuning_parameters = load_runtime_tuning_parameters(conn)
        bridge_stats = summarize_char_frequency_state(conn)
        reading_weight_stats = rebuild_char_pinyin_reading_weights(conn, tuning_parameters)
        print(
            "已记录单字频率状态: "
            f"总计 {bridge_stats['total_chars']}，"
            f"已填充 {bridge_stats['populated']}（"
            f"BCC {bridge_stats['bcc_rows']}，"
            f"合成 {bridge_stats['synthetic_rows']}）"
        )
        print(
            "已加载运行时调参: "
            f"常用读音 {tuning_parameters.get('common_reading_weight', COMMON_READING_WEIGHT)}，"
            f"非常用读音 {tuning_parameters.get('uncommon_reading_weight', UNCOMMON_READING_WEIGHT)}，"
            f"词语先验系数 {tuning_parameters.get('phrase_reading_prior_scale', PHRASE_READING_PRIOR_SCALE)}，"
            f"词语先验门槛 share>={tuning_parameters.get('phrase_reading_prior_min_share', PHRASE_READING_PRIOR_MIN_SHARE)}，"
            f"count>={int(round(tuning_parameters.get('phrase_reading_prior_min_phrase_count', PHRASE_READING_PRIOR_MIN_PHRASE_COUNT)))}，"
            f"evidence>={tuning_parameters.get('phrase_reading_prior_min_evidence_weight', PHRASE_READING_PRIOR_MIN_EVIDENCE_WEIGHT)}"
        )
        print(
            "已重建单字读音权重: "
            f"常用读音 {reading_weight_stats['common']}，"
            f"非常用读音 {reading_weight_stats['uncommon']}，"
            f"总计 {reading_weight_stats['total']}"
        )
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

        usage_profile_stats = rebuild_char_usage_profile(conn)
        modern_common_stats = rebuild_char_modern_common_profile(conn, tuning_parameters)
        reading_prior_stats = rebuild_char_reading_prior(conn, tuning_parameters)
        conn.commit()
        print(
            "已重建单字分层: "
            f"高频通用 {usage_profile_stats['common_high']}，"
            f"低频通用 {usage_profile_stats['common_low']}，"
            f"高频专用 {usage_profile_stats['special_high']}，"
            f"低频专用 {usage_profile_stats['special_low']}，"
            f"罕用 {usage_profile_stats['rare']}"
        )
        print(
            "已重建现代常用单字序位: "
            f"命中 {modern_common_stats['total']} 字，"
            f"序位阈值 <= {modern_common_stats['threshold']}"
        )
        print(
            "已重建词语读音先验: "
            f"覆盖 {reading_prior_stats['covered_chars']} 字，"
            f"生成 {reading_prior_stats['pair_rows']} 组字音先验，"
            f"启用 {reading_prior_stats['enabled_rows']} 组，"
            f"门槛 share>={reading_prior_stats['min_share']} / count>={reading_prior_stats['min_phrase_count']} / evidence>={reading_prior_stats['min_evidence_weight']}，"
            f"跳过 {reading_prior_stats['skipped_mismatched_phrase_rows']} 条长度不匹配词语"
        )

        materialized_rows = rebuild_materialized_runtime_candidates(conn)
        conn.commit()
        print(f"已重建物化运行时候选行: {materialized_rows}")

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
