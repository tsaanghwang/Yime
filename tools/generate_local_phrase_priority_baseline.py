from __future__ import annotations

import argparse
import json
import sqlite3
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent.parent
SCAN_PATH = ROOT / "yime" / "reports" / "runtime_tuning_scan.json"
RUNTIME_DB_PATH = ROOT / "yime" / "pinyin_hanzi.db"
RULES_PATH = ROOT / "internal_data" / "local_phrase_priority_rules.json"
SAMPLES_PATH = ROOT / "internal_data" / "local_phrase_priority_samples.json"

DEFAULT_BUCKET_LIMIT = 20
DEFAULT_TARGET_COUNT = 5
DEFAULT_SAMPLE_COUNT = 10
DEFAULT_BASE_BOOST = 500_000.0
DEFAULT_BOOST_STEP = 100_000.0

STRONG_FRAGMENT_SUFFIXES = (
    "的",
    "了",
    "着",
    "过",
    "吗",
    "吧",
    "呢",
    "啊",
    "呀",
    "嘛",
    "啦",
    "呗",
    "一个",
    "一种",
    "一样",
    "一些",
    "一位",
    "一点",
    "一次",
    "一段",
    "一个人",
    "一定的",
    "的时候",
    "之后",
    "以后",
    "的话",
)
WEAK_FRAGMENT_SUFFIX_CHARS = frozenset("能会要在将给让")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="生成或校验局部词语优先规则与样本集。"
    )
    parser.add_argument(
        "--bucket-limit",
        type=int,
        default=DEFAULT_BUCKET_LIMIT,
        help="从 runtime_tuning_scan 高碰撞桶中取前多少个桶，默认 20。",
    )
    parser.add_argument(
        "--target-count",
        type=int,
        default=DEFAULT_TARGET_COUNT,
        help="每个桶生成多少条定点规则，默认 5。",
    )
    parser.add_argument(
        "--sample-count",
        type=int,
        default=DEFAULT_SAMPLE_COUNT,
        help="每个桶保留多少条样本词语，默认 10。",
    )
    parser.add_argument(
        "--write",
        action="store_true",
        help="将生成结果写回 rules/samples JSON。",
    )
    parser.add_argument(
        "--validate",
        action="store_true",
        help="校验当前 files 是否与按当前参数生成的结果一致。",
    )
    return parser.parse_args()


def _load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _load_high_collision_buckets(scan_path: Path, bucket_limit: int) -> list[dict[str, Any]]:
    payload = _load_json(scan_path)
    buckets = payload["baseline"]["high_collision_focus"]["buckets"]
    return [dict(bucket) for bucket in buckets[:bucket_limit]]


def _query_prefix_phrases(
    conn: sqlite3.Connection,
    lookup_code: str,
    sample_count: int,
) -> list[dict[str, Any]]:
    rows = conn.execute(
        """
        SELECT phrase, pinyin_tone, COALESCE(phrase_frequency, 0) AS phrase_frequency, reading_rank
        FROM phrase_lexicon_view
        WHERE yime_code >= ?
          AND yime_code < ?
          AND LENGTH(yime_code) > ?
          AND LENGTH(phrase) BETWEEN 2 AND 4
        ORDER BY COALESCE(phrase_frequency, 0) DESC, reading_rank, phrase
        LIMIT ?
        """,
        (lookup_code, lookup_code + "\U0010ffff", len(lookup_code), sample_count),
    ).fetchall()
    return [
        {
            "phrase": str(row["phrase"] or "").strip(),
            "pinyin_tone": str(row["pinyin_tone"] or "").strip(),
            "phrase_frequency": float(row["phrase_frequency"] or 0.0),
            "reading_rank": int(row["reading_rank"] or 0),
        }
        for row in rows
        if str(row["phrase"] or "").strip()
    ]


def _fragment_penalty(phrase: str) -> int:
    normalized = str(phrase or "").strip()
    if not normalized:
        return 99

    penalty = 0
    if any(normalized.endswith(suffix) for suffix in STRONG_FRAGMENT_SUFFIXES):
        penalty += 2
    if len(normalized) >= 3 and normalized[-1] in WEAK_FRAGMENT_SUFFIX_CHARS:
        penalty += 1
    if normalized.startswith("是") and len(normalized) >= 3:
        penalty += 1
    return penalty


def _prefix_phrase_priority_sort_key(entry: dict[str, Any]) -> tuple[int, float, int, str]:
    phrase = str(entry.get("phrase") or "").strip()
    return (
        _fragment_penalty(phrase),
        -float(entry.get("phrase_frequency", 0.0) or 0.0),
        int(entry.get("reading_rank", 0) or 0),
        phrase,
    )


def _rank_prefix_phrases(entries: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return sorted(entries, key=_prefix_phrase_priority_sort_key)


def _build_target_boosts(target_count: int, *, base_boost: float, step: float) -> list[float]:
    return [max(base_boost - step * index, step) for index in range(target_count)]


def _build_sample_bucket_entry(
    bucket: dict[str, Any],
    *,
    lookup_code: str,
    lookup_pinyin_tone: str,
    prefix_phrases: list[dict[str, Any]],
    targets: list[dict[str, Any]],
) -> dict[str, Any]:
    return {
        "lookup_code": lookup_code,
        "lookup_pinyin_tone": lookup_pinyin_tone,
        "candidate_count": int(bucket.get("candidate_count", 0) or 0),
        "demand_weight_sum": float(bucket.get("demand_weight_sum", 0.0) or 0.0),
        "collision_demand_score": float(bucket.get("collision_demand_score", 0.0) or 0.0),
        "top_current_runtime_texts": [str(text) for text in bucket.get("top_current_runtime_texts", [])],
        "target_phrases": [str(target.get("text") or "") for target in targets],
        "sample_phrases": [str(entry.get("phrase") or "") for entry in prefix_phrases],
    }


def build_payloads(
    *,
    bucket_limit: int,
    target_count: int,
    sample_count: int,
) -> tuple[dict[str, Any], dict[str, Any]]:
    buckets = _load_high_collision_buckets(SCAN_PATH, bucket_limit)
    boosts = _build_target_boosts(
        target_count,
        base_boost=DEFAULT_BASE_BOOST,
        step=DEFAULT_BOOST_STEP,
    )

    rules: list[dict[str, Any]] = []
    sample_buckets: list[dict[str, Any]] = []

    with sqlite3.connect(RUNTIME_DB_PATH) as conn:
        conn.row_factory = sqlite3.Row
        for bucket in buckets:
            lookup_code = str(bucket["yime_code"] or "").strip()
            lookup_pinyin_tone = str(bucket["pinyin_tone"] or "").strip()
            raw_prefix_phrases = _query_prefix_phrases(conn, lookup_code, sample_count * 3)
            prefix_phrases = _rank_prefix_phrases(raw_prefix_phrases)[:sample_count]
            if len(prefix_phrases) < target_count:
                raise ValueError(
                    f"高碰撞桶 {lookup_pinyin_tone} 仅找到 {len(prefix_phrases)} 条词语样本，少于 target_count={target_count}"
                )

            targets = [
                {"text": prefix_phrases[index]["phrase"], "boost": boosts[index]}
                for index in range(target_count)
            ]
            sample_phrases = [entry["phrase"] for entry in prefix_phrases]

            rules.append(
                {
                    "lookup_pinyin_tone": lookup_pinyin_tone,
                    "targets": targets,
                }
            )
            sample_buckets.append(
                _build_sample_bucket_entry(
                    bucket,
                    lookup_code=lookup_code,
                    lookup_pinyin_tone=lookup_pinyin_tone,
                    prefix_phrases=prefix_phrases,
                    targets=targets,
                )
            )

    rules_payload = {
        "version": 1,
        "scope": "single_syllable_prefix",
        "description": "Local phrase-priority boosts for the highest-collision single-syllable buckets. Rules only apply to partial phrase expansion after one full syllable.",
        "rules": rules,
    }
    samples_payload = {
        "version": 1,
        "source": "yime/reports/runtime_tuning_scan.json baseline.high_collision_focus.buckets + runtime phrase_lexicon_view prefix query",
        "scope": "single_syllable_prefix",
        "buckets": sample_buckets,
    }
    return rules_payload, samples_payload


def _dump_payload(payload: dict[str, Any]) -> str:
    return json.dumps(payload, ensure_ascii=False, indent=2) + "\n"


def validate_payloads(expected_rules: dict[str, Any], expected_samples: dict[str, Any]) -> list[str]:
    mismatches: list[str] = []
    current_rules = _load_json(RULES_PATH)
    current_samples = _load_json(SAMPLES_PATH)

    if current_rules != expected_rules:
        mismatches.append("local_phrase_priority_rules.json 与生成结果不一致")
    if current_samples != expected_samples:
        mismatches.append("local_phrase_priority_samples.json 与生成结果不一致")
    return mismatches


def write_payloads(rules_payload: dict[str, Any], samples_payload: dict[str, Any]) -> None:
    RULES_PATH.write_text(_dump_payload(rules_payload), encoding="utf-8")
    SAMPLES_PATH.write_text(_dump_payload(samples_payload), encoding="utf-8")


def print_summary(rules_payload: dict[str, Any], samples_payload: dict[str, Any]) -> None:
    print(f"buckets={len(samples_payload['buckets'])} target_count={len(rules_payload['rules'][0]['targets']) if rules_payload['rules'] else 0}")
    for rule, sample in zip(rules_payload["rules"], samples_payload["buckets"]):
        print(
            f"{rule['lookup_pinyin_tone']}: top5={[target['text'] for target in rule['targets']]} sample_size={len(sample['sample_phrases'])}"
        )


def main() -> None:
    args = parse_args()
    if not args.write and not args.validate:
        raise SystemExit("请至少指定 --write 或 --validate。")

    rules_payload, samples_payload = build_payloads(
        bucket_limit=max(int(args.bucket_limit), 1),
        target_count=max(int(args.target_count), 1),
        sample_count=max(int(args.sample_count), max(int(args.target_count), 1)),
    )
    print_summary(rules_payload, samples_payload)

    if args.write:
        write_payloads(rules_payload, samples_payload)
        print(f"wrote: {RULES_PATH}")
        print(f"wrote: {SAMPLES_PATH}")

    if args.validate:
        mismatches = validate_payloads(rules_payload, samples_payload)
        if mismatches:
            raise SystemExit("\n".join(mismatches))
        print("validate: ok")


if __name__ == "__main__":
    main()
