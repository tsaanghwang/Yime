from __future__ import annotations

import argparse
import sqlite3
from collections import Counter
from pathlib import Path

from yime.input_method.core.decoders import SQLiteRuntimeCandidateDecoder
from yime.input_method.core.runtime_lookup import build_runtime_lookup_plan
from yime.input_method.core.runtime_ranking import (
    RuntimeCandidateRecord,
    apply_stage_b_rare_representative_guardrail,
)


ROOT = Path(__file__).resolve().parent.parent
APP_DIR = ROOT / "yime"
DB_PATH = ROOT / "yime" / "pinyin_hanzi.db"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="诊断高碰撞整码桶里的 rare 单字可达性基线。")
    parser.add_argument("--db", default=str(DB_PATH), help="运行时数据库路径。")
    parser.add_argument("--limit", type=int, default=10, help="最多显示多少个 worst-case 桶。")
    parser.add_argument(
        "--min-code-size",
        type=int,
        default=10,
        help="只分析候选数不少于该值的整码桶。",
    )
    parser.add_argument(
        "--detail-limit",
        type=int,
        default=15,
        help="桶详情最多显示多少条候选。",
    )
    parser.add_argument(
        "--page-size",
        type=int,
        default=5,
        help="按 UI/decoder 首屏口径统计的页大小。",
    )
    parser.add_argument(
        "--lookup-code",
        help="可选：直接查看某个整码桶；未提供时自动选当前 worst-case 桶。",
    )
    return parser.parse_args()


def _connect(db_path: Path) -> sqlite3.Connection:
    connection = sqlite3.connect(db_path)
    connection.row_factory = sqlite3.Row
    return connection


def _ranked_cte_sql() -> str:
    return '''
    WITH ranked AS (
      SELECT yime_code, hanzi, usage_tier,
             COALESCE(tier_sort_weight, 0.0)
               + CASE WHEN is_common_reading = 1 THEN COALESCE(modern_common_boost, 0.0) ELSE 0.0 END
               + COALESCE(reading_phrase_prior_boost, 0.0)
               + COALESCE(char_frequency_abs, 0)
               + COALESCE(reading_weight, CASE WHEN is_common_reading = 1 THEN 1.0 ELSE 0.5 END) AS sort_weight,
             ROW_NUMBER() OVER (
               PARTITION BY yime_code
               ORDER BY COALESCE(tier_sort_weight, 0.0)
                 + CASE WHEN is_common_reading = 1 THEN COALESCE(modern_common_boost, 0.0) ELSE 0.0 END
                 + COALESCE(reading_phrase_prior_boost, 0.0)
                 + COALESCE(char_frequency_abs, 0)
                 + COALESCE(reading_weight, CASE WHEN is_common_reading = 1 THEN 1.0 ELSE 0.5 END) DESC,
                 hanzi
             ) AS rn,
             COUNT(*) OVER (PARTITION BY yime_code) AS code_size
      FROM char_lexicon
      WHERE yime_code IS NOT NULL AND TRIM(yime_code) <> ''
    )
    '''


def load_worst_rare_buckets(
    connection: sqlite3.Connection,
    *,
    limit: int,
    min_code_size: int,
) -> list[sqlite3.Row]:
    return connection.execute(
        _ranked_cte_sql()
        + '''
        SELECT yime_code, code_size,
               SUM(CASE WHEN usage_tier = 'rare' THEN 1 ELSE 0 END) AS rare_count,
               MIN(CASE WHEN usage_tier = 'rare' THEN rn END) AS best_rare_rank,
               SUM(CASE WHEN usage_tier = 'common_high' THEN 1 ELSE 0 END) AS common_high_count,
               SUM(CASE WHEN usage_tier = 'special_high' THEN 1 ELSE 0 END) AS special_high_count,
               SUM(CASE WHEN usage_tier = 'special_low' THEN 1 ELSE 0 END) AS special_low_count
        FROM ranked
        GROUP BY yime_code, code_size
        HAVING rare_count > 0 AND code_size >= ?
        ORDER BY best_rare_rank DESC, code_size DESC, yime_code
        LIMIT ?
        ''',
        (max(int(min_code_size), 1), max(int(limit), 1)),
    ).fetchall()


def load_bucket_details(
    connection: sqlite3.Connection,
    *,
    lookup_code: str,
    detail_limit: int,
) -> list[sqlite3.Row]:
    return connection.execute(
        _ranked_cte_sql()
        + '''
        SELECT yime_code, hanzi, usage_tier, rn, code_size, sort_weight
        FROM ranked
        WHERE yime_code = ?
        ORDER BY rn
        LIMIT ?
        ''',
        (lookup_code, max(int(detail_limit), 1)),
    ).fetchall()


def load_first_rare_entry(connection: sqlite3.Connection, *, lookup_code: str) -> sqlite3.Row | None:
    row = connection.execute(
        _ranked_cte_sql()
        + '''
        SELECT yime_code, hanzi, usage_tier, rn, code_size, sort_weight
        FROM ranked
        WHERE yime_code = ? AND usage_tier = 'rare'
        ORDER BY rn
        LIMIT 1
        ''',
        (lookup_code,),
    ).fetchone()
    return row


def summarize_first_page_tiers(rows: list[sqlite3.Row], *, page_size: int) -> Counter[str]:
    counter: Counter[str] = Counter()
    for row in rows[: max(int(page_size), 0)]:
        counter[str(row["usage_tier"] or "unknown")] += 1
    return counter


def _record_tier_label(record: RuntimeCandidateRecord) -> str:
    if record.entry_type != "char":
        return record.entry_type
    return record.usage_tier or "char-unknown"


def load_stage_b_ranked_records(lookup_code: str) -> list[RuntimeCandidateRecord]:
    decoder = SQLiteRuntimeCandidateDecoder(APP_DIR)
    plan = build_runtime_lookup_plan(lookup_code)
    raw_candidates, priority_lookup_code = decoder._lookup_runtime_candidates_for_decode(lookup_code, plan)
    records = decoder._rank_runtime_candidates(
        decoder._payload_to_runtime_candidates(
            plan.lookup_code,
            raw_candidates,
            stage=plan.stage,
            priority_lookup_code=priority_lookup_code,
        )
    )
    if plan.stage == "B":
        return apply_stage_b_rare_representative_guardrail(records)
    return records


def summarize_stage_b_first_page_tiers(
    records: list[RuntimeCandidateRecord],
    *,
    page_size: int,
) -> Counter[str]:
    counter: Counter[str] = Counter()
    for record in records[: max(int(page_size), 0)]:
        counter[_record_tier_label(record)] += 1
    return counter


def summarize_stage_b_page_tiers(
    records: list[RuntimeCandidateRecord],
    *,
    page_size: int,
    page_number: int,
) -> Counter[str]:
    normalized_page_size = max(int(page_size), 0)
    normalized_page_number = max(int(page_number), 1)
    start = (normalized_page_number - 1) * normalized_page_size
    end = start + normalized_page_size
    counter: Counter[str] = Counter()
    for record in records[start:end]:
        counter[_record_tier_label(record)] += 1
    return counter


def find_stage_b_first_rare_record(records: list[RuntimeCandidateRecord]) -> tuple[int, RuntimeCandidateRecord] | None:
    for index, record in enumerate(records, start=1):
        if record.entry_type == "char" and record.usage_tier == "rare":
            return index, record
    return None


def main() -> None:
    args = parse_args()
    db_path = Path(args.db).resolve()
    if not db_path.exists():
        raise SystemExit(f"未找到数据库: {db_path}")

    with _connect(db_path) as connection:
        worst_buckets = load_worst_rare_buckets(
            connection,
            limit=args.limit,
            min_code_size=args.min_code_size,
        )
        if not worst_buckets:
            print("未找到满足条件的 rare 整码桶。")
            return

        selected_lookup_code = str(args.lookup_code or worst_buckets[0]["yime_code"] or "")
        detail_rows = load_bucket_details(
            connection,
            lookup_code=selected_lookup_code,
            detail_limit=args.detail_limit,
        )
        first_rare = load_first_rare_entry(connection, lookup_code=selected_lookup_code)

    stage_b_records = load_stage_b_ranked_records(selected_lookup_code)

    print(f"db_path={db_path}")
    print(f"min_code_size={args.min_code_size}")
    print(f"page_size={args.page_size}")
    print(f"worst_bucket_count={len(worst_buckets)}")
    print("worst_rare_buckets:")
    for index, row in enumerate(worst_buckets, start=1):
        print(
            f"#{index} lookup_code={row['yime_code']} code_size={row['code_size']} "
            f"rare_count={row['rare_count']} best_rare_rank={row['best_rare_rank']} "
            f"common_high={row['common_high_count']} special_high={row['special_high_count']} "
            f"special_low={row['special_low_count']}"
        )

    print()
    print(f"selected_lookup_code={selected_lookup_code}")
    if first_rare is None:
        print("selected_first_rare=None")
    else:
        print(
            f"selected_first_rare=hanzi:{first_rare['hanzi']} rank:{first_rare['rn']} "
            f"code_size:{first_rare['code_size']} sort_weight:{first_rare['sort_weight']}"
        )

    first_page_tiers = summarize_first_page_tiers(detail_rows, page_size=args.page_size)
    print(
        "selected_first_page_tier_counts="
        + ", ".join(
            f"{tier}:{count}"
            for tier, count in sorted(first_page_tiers.items())
        )
    )
    print("selected_bucket_first_page_entries:")
    for row in detail_rows[: max(int(args.page_size), 0)]:
        print(
            f"#{row['rn']} hanzi={row['hanzi']} usage_tier={row['usage_tier']} "
            f"sort_weight={row['sort_weight']}"
        )

    stage_b_first_page_tiers = summarize_stage_b_first_page_tiers(
        stage_b_records,
        page_size=args.page_size,
    )
    stage_b_second_page_tiers = summarize_stage_b_page_tiers(
        stage_b_records,
        page_size=args.page_size,
        page_number=2,
    )
    stage_b_first_rare = find_stage_b_first_rare_record(stage_b_records)
    print(
        "selected_stage_b_first_page_tier_counts="
        + ", ".join(
            f"{tier}:{count}"
            for tier, count in sorted(stage_b_first_page_tiers.items())
        )
    )
    print("selected_stage_b_first_page_entries:")
    for index, record in enumerate(stage_b_records[: max(int(args.page_size), 0)], start=1):
        print(
            f"#{index} text={record.text} entry_type={record.entry_type} tier={_record_tier_label(record)} "
            f"sort_weight={record.sort_weight}"
        )
    print(
        "selected_stage_b_second_page_tier_counts="
        + ", ".join(
            f"{tier}:{count}"
            for tier, count in sorted(stage_b_second_page_tiers.items())
        )
    )
    print("selected_stage_b_second_page_entries:")
    start = max(int(args.page_size), 0)
    end = start + max(int(args.page_size), 0)
    for index, record in enumerate(stage_b_records[start:end], start=start + 1):
        print(
            f"#{index} text={record.text} entry_type={record.entry_type} tier={_record_tier_label(record)} "
            f"sort_weight={record.sort_weight}"
        )
    if stage_b_first_rare is None:
        print("selected_stage_b_first_rare=None")
    else:
        rank, record = stage_b_first_rare
        print(
            f"selected_stage_b_first_rare=text:{record.text} rank:{rank} "
            f"tier:{_record_tier_label(record)} sort_weight:{record.sort_weight}"
        )

    print("selected_bucket_top_entries:")
    for row in detail_rows:
        print(
            f"#{row['rn']} hanzi={row['hanzi']} usage_tier={row['usage_tier']} "
            f"sort_weight={row['sort_weight']}"
        )


if __name__ == "__main__":
    main()
