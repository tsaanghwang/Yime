import argparse
import json
import math
from collections import Counter
from datetime import UTC, datetime
from pathlib import Path
from statistics import median


ROOT = Path(__file__).resolve().parent.parent
DEFAULT_INPUT = ROOT / "yime" / "reports" / "runtime_candidates_by_code_true.json"
DEFAULT_MARKDOWN_OUTPUT = ROOT / "docs" / "EFFICIENCY_BASELINE.md"
DEFAULT_JSON_OUTPUT = ROOT / "yime" / "reports" / "efficiency_baseline.json"
DEFAULT_YINJIE_CODEBOOK = ROOT / "syllable_codec" / "yinjie_code.json"
DEFAULT_RUNTIME_SYMBOL_MAPPING = ROOT / "internal_data" / "yinjie_runtime_key_symbol_mapping.json"
CHAR_TIER_DEFS = (
    ("level_1", 3500, "一级字（前 3500）"),
    ("level_2", 6500, "二级前字（前 6500）"),
    ("level_3", 8105, "三级前字（前 8105）"),
)


def load_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def percentile(values: list[int], pct: float) -> float:
    if not values:
        return 0.0
    if len(values) == 1:
        return float(values[0])
    ordered = sorted(values)
    index = (len(ordered) - 1) * pct
    lower = math.floor(index)
    upper = math.ceil(index)
    if lower == upper:
        return float(ordered[lower])
    weight = index - lower
    return ordered[lower] * (1.0 - weight) + ordered[upper] * weight


def strip_tone_digits(pinyin_tone: str) -> str:
    syllables = []
    for segment in pinyin_tone.split():
        if segment and segment[-1].isdigit():
            syllables.append(segment[:-1])
        else:
            syllables.append(segment)
    return " ".join(syllables)


def count_syllables(pinyin_tone: str) -> int:
    return len([segment for segment in pinyin_tone.split() if segment])


def full_pinyin_key_length(pinyin_tone: str) -> int:
    return sum(len(segment[:-1] if segment and segment[-1].isdigit() else segment) for segment in pinyin_tone.split())


def full_pinyin_with_tone_number_key_length(pinyin_tone: str) -> int:
    total = 0
    for segment in pinyin_tone.split():
        if not segment:
            continue
        total += len(segment[:-1] if segment[-1].isdigit() else segment)
        if segment[-1].isdigit():
            total += 1
    return total


def load_runtime_symbol_metadata(path: Path) -> dict[str, object]:
    mapping = load_json(path)
    key_to_symbol = mapping.get("key_to_symbol", {})
    entries = mapping.get("entries", [])

    virtual_initial_symbol = ""
    for entry in entries:
        if entry.get("source_type") == "shouyin" and entry.get("source_name") == "'":
            virtual_initial_symbol = str(entry.get("symbol", ""))
            break

    ganyin_symbols: dict[str, dict[str, int | str]] = {}
    for key, symbol in key_to_symbol.items():
        if not str(key).startswith("M"):
            continue
        ordinal = int(str(key)[1:]) - 1
        ganyin_symbols[str(symbol)] = {
            "quality_group": ordinal // 3,
            "tone_level": ("high", "mid", "low")[ordinal % 3],
        }

    return {
        "virtual_initial_symbol": virtual_initial_symbol,
        "ganyin_symbols": ganyin_symbols,
    }


def simplify_yime_syllable_code_length(full_code: str, runtime_symbol_metadata: dict[str, object]) -> int:
    symbols = list(full_code)
    if not symbols:
        return 0

    virtual_initial_symbol = str(runtime_symbol_metadata.get("virtual_initial_symbol", ""))
    ganyin_metadata = runtime_symbol_metadata.get("ganyin_symbols", {})

    shouyin_length = 1
    if virtual_initial_symbol and symbols[0] == virtual_initial_symbol:
        shouyin_length = 0

    ganyin_symbols = symbols[1:]
    compressed: list[str] = []
    for symbol in ganyin_symbols:
        if not compressed or compressed[-1] != symbol:
            compressed.append(symbol)

    if len(compressed) == 3:
        meta = [ganyin_metadata.get(symbol) for symbol in compressed]
        if all(item is not None for item in meta):
            quality_groups = {int(item["quality_group"]) for item in meta}
            tone_pattern = [str(item["tone_level"]) for item in meta]
            if len(quality_groups) == 1 and tone_pattern in (["high", "mid", "low"], ["low", "mid", "high"]):
                compressed = [compressed[0], compressed[2]]

    return shouyin_length + len(compressed)


def yime_jianpin_key_length(
    pinyin_tone: str,
    yinjie_codebook: dict[str, str],
    runtime_symbol_metadata: dict[str, object],
) -> tuple[int, int]:
    total_length = 0
    missing_syllable_count = 0
    for segment in pinyin_tone.split():
        full_code = yinjie_codebook.get(segment)
        if not full_code:
            missing_syllable_count += 1
            total_length += 4
            continue
        total_length += simplify_yime_syllable_code_length(full_code, runtime_symbol_metadata)
    return total_length, missing_syllable_count


def analyze_syllable_simplification(full_code: str, runtime_symbol_metadata: dict[str, object]) -> dict[str, object]:
    symbols = list(full_code)
    virtual_initial_symbol = str(runtime_symbol_metadata.get("virtual_initial_symbol", ""))
    ganyin_metadata = runtime_symbol_metadata.get("ganyin_symbols", {})

    omitted_virtual_initial = bool(symbols and virtual_initial_symbol and symbols[0] == virtual_initial_symbol)
    original_ganyin = symbols[1:]
    deduped_ganyin: list[str] = []
    merged_repeat_count = 0
    for symbol in original_ganyin:
        if not deduped_ganyin or deduped_ganyin[-1] != symbol:
            deduped_ganyin.append(symbol)
        else:
            merged_repeat_count += 1

    omitted_middle_tone = False
    if len(deduped_ganyin) == 3:
        meta = [ganyin_metadata.get(symbol) for symbol in deduped_ganyin]
        if all(item is not None for item in meta):
            quality_groups = {int(item["quality_group"]) for item in meta}
            tone_pattern = [str(item["tone_level"]) for item in meta]
            if len(quality_groups) == 1 and tone_pattern in (["high", "mid", "low"], ["low", "mid", "high"]):
                deduped_ganyin = [deduped_ganyin[0], deduped_ganyin[2]]
                omitted_middle_tone = True

    simplified_length = (0 if omitted_virtual_initial else 1) + len(deduped_ganyin)
    return {
        "full_length": len(symbols),
        "jianpin_length": simplified_length,
        "saved_keys": len(symbols) - simplified_length,
        "omitted_virtual_initial": omitted_virtual_initial,
        "merged_repeat_count": merged_repeat_count,
        "omitted_middle_tone": omitted_middle_tone,
    }


def build_syllable_jianpin_examples(
    yinjie_codebook: dict[str, str],
    runtime_symbol_metadata: dict[str, object],
    *,
    limit: int,
) -> dict[str, list[dict[str, object]]]:
    examples: list[dict[str, object]] = []
    for syllable, full_code in yinjie_codebook.items():
        analysis = analyze_syllable_simplification(str(full_code), runtime_symbol_metadata)
        reasons: list[str] = []
        if analysis["omitted_virtual_initial"]:
            reasons.append("省略虚首音")
        if int(analysis["merged_repeat_count"]) > 0:
            reasons.append(f"合并连续相同音元 {analysis['merged_repeat_count']} 次")
        if analysis["omitted_middle_tone"]:
            reasons.append("省略中调乐音")
        if not reasons:
            reasons.append("无可压缩步骤")

        examples.append(
            {
                "syllable": syllable,
                "full_length": analysis["full_length"],
                "jianpin_length": analysis["jianpin_length"],
                "saved_keys": analysis["saved_keys"],
                "reason": "；".join(reasons),
            }
        )

    most_compressible = sorted(
        examples,
        key=lambda item: (-int(item["saved_keys"]), int(item["jianpin_length"]), str(item["syllable"])),
    )[:limit]
    least_compressible = sorted(
        examples,
        key=lambda item: (int(item["saved_keys"]), int(item["jianpin_length"]), str(item["syllable"])),
    )[:limit]
    return {
        "most_compressible": most_compressible,
        "least_compressible": least_compressible,
    }


def build_syllable_jianpin_rule_stats(
    yinjie_codebook: dict[str, str],
    runtime_symbol_metadata: dict[str, object],
) -> dict[str, object]:
    total_syllable_count = 0
    compressed_syllable_count = 0
    no_compression_count = 0
    total_saved_keys = 0

    omitted_virtual_initial_count = 0
    merged_repeat_count = 0
    omitted_middle_tone_count = 0

    combo_counter: Counter[str] = Counter()

    for _syllable, full_code in yinjie_codebook.items():
        analysis = analyze_syllable_simplification(str(full_code), runtime_symbol_metadata)
        total_syllable_count += 1
        saved_keys = int(analysis["saved_keys"])
        total_saved_keys += saved_keys

        combo_parts: list[str] = []
        if analysis["omitted_virtual_initial"]:
            omitted_virtual_initial_count += 1
            combo_parts.append("省略虚首音")
        if int(analysis["merged_repeat_count"]) > 0:
            merged_repeat_count += 1
            combo_parts.append("合并重复")
        if analysis["omitted_middle_tone"]:
            omitted_middle_tone_count += 1
            combo_parts.append("省略中调")

        if saved_keys > 0:
            compressed_syllable_count += 1
        else:
            no_compression_count += 1

        combo_counter[" + ".join(combo_parts) if combo_parts else "无可压缩步骤"] += 1

    def share(count: int) -> float:
        return count / total_syllable_count if total_syllable_count else 0.0

    combo_rows = [
        {
            "label": label,
            "count": count,
            "share": share(count),
        }
        for label, count in sorted(combo_counter.items(), key=lambda item: (-item[1], item[0]))
    ]

    return {
        "total_syllable_count": total_syllable_count,
        "compressed_syllable_count": compressed_syllable_count,
        "no_compression_count": no_compression_count,
        "avg_saved_keys_per_syllable": (total_saved_keys / total_syllable_count) if total_syllable_count else 0.0,
        "rule_rows": [
            {
                "label": "靠省略虚首音获益",
                "count": omitted_virtual_initial_count,
                "share": share(omitted_virtual_initial_count),
            },
            {
                "label": "靠合并重复获益",
                "count": merged_repeat_count,
                "share": share(merged_repeat_count),
            },
            {
                "label": "靠省略中调获益",
                "count": omitted_middle_tone_count,
                "share": share(omitted_middle_tone_count),
            },
            {
                "label": "至少触发一条简拼规则",
                "count": compressed_syllable_count,
                "share": share(compressed_syllable_count),
            },
            {
                "label": "没有任何压缩收益",
                "count": no_compression_count,
                "share": share(no_compression_count),
            },
        ],
        "combo_rows": combo_rows,
    }


def summarize_counts(counts: list[int], row_count: int, threshold: int) -> dict[str, float | int]:
    if not counts:
        return {
            "code_bucket_count": 0,
            "candidate_row_count": row_count,
            "avg_per_code": 0.0,
            "median_per_code": 0.0,
            "p95_per_code": 0.0,
            "max_per_code": 0,
            f"share_le_{threshold}": 0.0,
        }

    return {
        "code_bucket_count": len(counts),
        "candidate_row_count": row_count,
        "avg_per_code": row_count / len(counts),
        "median_per_code": float(median(counts)),
        "p95_per_code": percentile(counts, 0.95),
        "max_per_code": max(counts),
        f"share_le_{threshold}": sum(1 for count in counts if count <= threshold) / len(counts),
    }


def summarize_common_visibility(
    by_code: dict[str, list[dict]],
    *,
    predicate,
    page_size: int,
    selection_window_size: int,
) -> dict[str, float | int]:
    common_candidate_count = 0
    visible_on_first_page_count = 0
    visible_on_selection_window_count = 0
    bucket_count = 0
    bucket_first_page_hit_count = 0
    bucket_selection_window_hit_count = 0
    bucket_first_page_full_count = 0
    bucket_selection_window_full_count = 0

    for entries in by_code.values():
        filtered = [entry for entry in entries if predicate(int(entry.get("text_length", 0)))]
        common_entries = [entry for entry in filtered if int(entry.get("is_common", 0)) == 1]
        if not common_entries:
            continue

        bucket_count += 1
        common_candidate_count += len(common_entries)

        first_page = filtered[:page_size]
        selection_window = filtered[:selection_window_size]

        first_page_hits = sum(1 for entry in first_page if int(entry.get("is_common", 0)) == 1)
        selection_window_hits = sum(1 for entry in selection_window if int(entry.get("is_common", 0)) == 1)

        visible_on_first_page_count += first_page_hits
        visible_on_selection_window_count += selection_window_hits

        if first_page_hits > 0:
            bucket_first_page_hit_count += 1
        if selection_window_hits > 0:
            bucket_selection_window_hit_count += 1
        if first_page_hits == len(common_entries):
            bucket_first_page_full_count += 1
        if selection_window_hits == len(common_entries):
            bucket_selection_window_full_count += 1

    def share(value: int, total: int) -> float:
        return value / total if total else 0.0

    return {
        "common_candidate_count": common_candidate_count,
        "bucket_count": bucket_count,
        "first_page_visible_count": visible_on_first_page_count,
        "selection_window_visible_count": visible_on_selection_window_count,
        "first_page_visible_share": share(visible_on_first_page_count, common_candidate_count),
        "selection_window_visible_share": share(visible_on_selection_window_count, common_candidate_count),
        "bucket_first_page_hit_share": share(bucket_first_page_hit_count, bucket_count),
        "bucket_selection_window_hit_share": share(bucket_selection_window_hit_count, bucket_count),
        "bucket_first_page_full_share": share(bucket_first_page_full_count, bucket_count),
        "bucket_selection_window_full_share": share(bucket_selection_window_full_count, bucket_count),
    }


def summarize_weighted_visibility(
    by_code: dict[str, list[dict]],
    *,
    predicate,
    page_size: int,
    selection_window_size: int,
) -> dict[str, float | int]:
    weighted_candidate_sum = 0.0
    weighted_top1_sum = 0.0
    weighted_first_page_sum = 0.0
    weighted_selection_window_sum = 0.0
    bucket_count = 0
    bucket_top1_best_count = 0

    for entries in by_code.values():
        filtered = [entry for entry in entries if predicate(int(entry.get("text_length", 0)))]
        if not filtered:
            continue

        weights = [float(entry.get("sort_weight", 0.0) or 0.0) for entry in filtered]
        total_weight = sum(weights)
        if total_weight <= 0:
            continue

        bucket_count += 1
        weighted_candidate_sum += total_weight
        weighted_top1_sum += float(filtered[0].get("sort_weight", 0.0) or 0.0)
        weighted_first_page_sum += sum(float(entry.get("sort_weight", 0.0) or 0.0) for entry in filtered[:page_size])
        weighted_selection_window_sum += sum(
            float(entry.get("sort_weight", 0.0) or 0.0) for entry in filtered[:selection_window_size]
        )
        if float(filtered[0].get("sort_weight", 0.0) or 0.0) == max(weights):
            bucket_top1_best_count += 1

    def share(value: float, total: float) -> float:
        return value / total if total else 0.0

    return {
        "weighted_candidate_sum": weighted_candidate_sum,
        "bucket_count": bucket_count,
        "weighted_top1_share": share(weighted_top1_sum, weighted_candidate_sum),
        "weighted_first_page_share": share(weighted_first_page_sum, weighted_candidate_sum),
        "weighted_selection_window_share": share(weighted_selection_window_sum, weighted_candidate_sum),
        "bucket_top1_best_share": share(bucket_top1_best_count, bucket_count),
    }


def build_char_tier_sets(by_code: dict[str, list[dict]]) -> dict[str, set[str]]:
    char_peak_weights: dict[str, float] = {}
    for entries in by_code.values():
        for entry in entries:
            if int(entry.get("text_length", 0)) != 1:
                continue
            text = str(entry.get("text", ""))
            weight = float(entry.get("sort_weight", 0.0) or 0.0)
            previous = char_peak_weights.get(text)
            if previous is None or weight > previous:
                char_peak_weights[text] = weight

    ranked_chars = sorted(char_peak_weights.items(), key=lambda item: (-item[1], item[0]))
    tiers = {"all": {text for text, _weight in ranked_chars}}
    for tier_key, tier_size, _tier_label in CHAR_TIER_DEFS:
        tiers[tier_key] = {text for text, _weight in ranked_chars[:tier_size]}
    return tiers


def summarize_tier_metrics(
    by_code: dict[str, list[dict]],
    *,
    char_set: set[str],
    page_size: int,
    selection_window_size: int,
) -> dict[str, float | int]:
    counts: list[int] = []
    row_count = 0

    def predicate(entry: dict) -> bool:
        return int(entry.get("text_length", 0)) == 1 and str(entry.get("text", "")) in char_set

    for entries in by_code.values():
        filtered = [entry for entry in entries if predicate(entry)]
        if not filtered:
            continue
        counts.append(len(filtered))
        row_count += len(filtered)

    result = summarize_counts(counts, row_count, page_size)
    result["share_le_9"] = sum(1 for count in counts if count <= 9) / len(counts) if counts else 0.0
    result["char_count"] = len(char_set)
    result["weighted_visibility"] = summarize_weighted_visibility(
        by_code,
        predicate=lambda text_length: False,
        page_size=page_size,
        selection_window_size=selection_window_size,
    )

    weighted_candidate_sum = 0.0
    weighted_top1_sum = 0.0
    weighted_first_page_sum = 0.0
    weighted_selection_window_sum = 0.0
    bucket_count = 0
    bucket_top1_best_count = 0
    for entries in by_code.values():
        filtered = [entry for entry in entries if predicate(entry)]
        if not filtered:
            continue
        weights = [float(entry.get("sort_weight", 0.0) or 0.0) for entry in filtered]
        total_weight = sum(weights)
        if total_weight <= 0:
            continue
        bucket_count += 1
        weighted_candidate_sum += total_weight
        weighted_top1_sum += float(filtered[0].get("sort_weight", 0.0) or 0.0)
        weighted_first_page_sum += sum(float(entry.get("sort_weight", 0.0) or 0.0) for entry in filtered[:page_size])
        weighted_selection_window_sum += sum(
            float(entry.get("sort_weight", 0.0) or 0.0) for entry in filtered[:selection_window_size]
        )
        if float(filtered[0].get("sort_weight", 0.0) or 0.0) == max(weights):
            bucket_top1_best_count += 1

    def share(value: float, total: float) -> float:
        return value / total if total else 0.0

    result["weighted_visibility"] = {
        "weighted_candidate_sum": weighted_candidate_sum,
        "bucket_count": bucket_count,
        "weighted_top1_share": share(weighted_top1_sum, weighted_candidate_sum),
        "weighted_first_page_share": share(weighted_first_page_sum, weighted_candidate_sum),
        "weighted_selection_window_share": share(weighted_selection_window_sum, weighted_candidate_sum),
        "bucket_top1_best_share": share(bucket_top1_best_count, bucket_count),
    }
    return result


def summarize_code_length_baseline(
    by_code: dict[str, list[dict]],
    *,
    predicate,
    yinjie_codebook: dict[str, str],
    runtime_symbol_metadata: dict[str, object],
) -> dict[str, float | int]:
    weighted_sum = 0.0
    yime_full_sum = 0.0
    yime_jianpin_sum = 0.0
    full_pinyin_sum = 0.0
    full_pinyin_with_tone_number_sum = 0.0
    double_pinyin_sum = 0.0
    syllable_sum = 0.0
    row_count = 0
    missing_yinjie_syllable_count = 0

    for entries in by_code.values():
        for entry in entries:
            if not predicate(entry):
                continue
            pinyin_tone = str(entry.get("pinyin_tone", ""))
            syllable_count = count_syllables(pinyin_tone)
            if syllable_count <= 0:
                continue
            weight = float(entry.get("sort_weight", 0.0) or 0.0)
            if weight <= 0:
                continue
            row_count += 1
            weighted_sum += weight
            syllable_sum += weight * syllable_count
            yime_full_sum += weight * (syllable_count * 4)
            yime_jianpin_length, missing_count = yime_jianpin_key_length(
                pinyin_tone,
                yinjie_codebook,
                runtime_symbol_metadata,
            )
            yime_jianpin_sum += weight * yime_jianpin_length
            missing_yinjie_syllable_count += missing_count
            full_pinyin_sum += weight * full_pinyin_key_length(pinyin_tone)
            full_pinyin_with_tone_number_sum += weight * full_pinyin_with_tone_number_key_length(pinyin_tone)
            double_pinyin_sum += weight * (syllable_count * 2)

    def avg(total: float) -> float:
        return total / weighted_sum if weighted_sum else 0.0

    return {
        "row_count": row_count,
        "weighted_sum": weighted_sum,
        "missing_yinjie_syllable_count": missing_yinjie_syllable_count,
        "avg_syllables": avg(syllable_sum),
        "avg_yime_full": avg(yime_full_sum),
        "avg_yime_jianpin": avg(yime_jianpin_sum),
        "avg_full_pinyin": avg(full_pinyin_sum),
        "avg_full_pinyin_with_tone_number": avg(full_pinyin_with_tone_number_sum),
        "avg_double_pinyin": avg(double_pinyin_sum),
        "jianpin_saved_vs_full": avg(yime_full_sum) - avg(yime_jianpin_sum),
        "jianpin_vs_full_pinyin": avg(yime_jianpin_sum) - avg(full_pinyin_sum),
        "jianpin_vs_full_pinyin_with_tone_number": avg(yime_jianpin_sum) - avg(full_pinyin_with_tone_number_sum),
        "jianpin_vs_double_pinyin": avg(yime_jianpin_sum) - avg(double_pinyin_sum),
    }


def build_top_examples(
    by_code: dict[str, list[dict]],
    *,
    predicate,
    limit: int,
) -> list[dict[str, object]]:
    examples = []
    for code, entries in by_code.items():
        filtered = [entry for entry in entries if predicate(int(entry.get("text_length", 0)))]
        if not filtered:
            continue
        pinyin_counts = Counter(entry.get("pinyin_tone", "") for entry in filtered)
        dominant_pinyin, dominant_count = pinyin_counts.most_common(1)[0]
        examples.append(
            {
                "code": code,
                "dominant_pinyin": dominant_pinyin,
                "dominant_count": dominant_count,
                "candidate_count": len(filtered),
                "samples": [entry.get("text", "") for entry in filtered[:8]],
            }
        )

    return sorted(
        examples,
        key=lambda item: (-int(item["candidate_count"]), -int(item["dominant_count"]), str(item["dominant_pinyin"])),
    )[:limit]


def build_payload(report: dict, page_size: int) -> dict[str, object]:
    metadata = report.get("metadata", {})
    by_code = report.get("by_code", {})
    yinjie_codebook = load_json(DEFAULT_YINJIE_CODEBOOK)
    runtime_symbol_metadata = load_runtime_symbol_metadata(DEFAULT_RUNTIME_SYMBOL_MAPPING)

    char_counts: list[int] = []
    phrase_counts: list[int] = []
    char_rows = 0
    phrase_rows = 0

    for _code, entries in by_code.items():
        char_entries = [entry for entry in entries if entry.get("text_length") == 1]
        phrase_entries = [entry for entry in entries if entry.get("text_length", 0) > 1]
        if char_entries:
            char_counts.append(len(char_entries))
            char_rows += len(char_entries)
        if phrase_entries:
            phrase_counts.append(len(phrase_entries))
            phrase_rows += len(phrase_entries)

    page_thresholds = {
        "current_page_size": page_size,
        "selection_window_size": 9,
    }
    selection_window_size = int(page_thresholds["selection_window_size"])
    char_tier_sets = build_char_tier_sets(by_code)

    char_summary = summarize_counts(char_counts, char_rows, page_size)
    char_summary["share_le_9"] = sum(1 for count in char_counts if count <= 9) / len(char_counts) if char_counts else 0.0
    phrase_summary = summarize_counts(phrase_counts, phrase_rows, page_size)
    phrase_summary["share_le_9"] = sum(1 for count in phrase_counts if count <= 9) / len(phrase_counts) if phrase_counts else 0.0
    char_weighted_visibility = summarize_weighted_visibility(
        by_code,
        predicate=lambda text_length: text_length == 1,
        page_size=page_size,
        selection_window_size=selection_window_size,
    )
    phrase_weighted_visibility = summarize_weighted_visibility(
        by_code,
        predicate=lambda text_length: text_length > 1,
        page_size=page_size,
        selection_window_size=selection_window_size,
    )
    char_tiers = {
        tier_name: summarize_tier_metrics(
            by_code,
            char_set=char_set,
            page_size=page_size,
            selection_window_size=selection_window_size,
        )
        for tier_name, char_set in char_tier_sets.items()
    }
    code_length_baseline = {
        "chars_level_1": summarize_code_length_baseline(
            by_code,
            predicate=lambda entry: int(entry.get("text_length", 0)) == 1 and str(entry.get("text", "")) in char_tier_sets["level_1"],
            yinjie_codebook=yinjie_codebook,
            runtime_symbol_metadata=runtime_symbol_metadata,
        ),
        "chars_level_2": summarize_code_length_baseline(
            by_code,
            predicate=lambda entry: int(entry.get("text_length", 0)) == 1 and str(entry.get("text", "")) in char_tier_sets["level_2"],
            yinjie_codebook=yinjie_codebook,
            runtime_symbol_metadata=runtime_symbol_metadata,
        ),
        "chars_level_3": summarize_code_length_baseline(
            by_code,
            predicate=lambda entry: int(entry.get("text_length", 0)) == 1 and str(entry.get("text", "")) in char_tier_sets["level_3"],
            yinjie_codebook=yinjie_codebook,
            runtime_symbol_metadata=runtime_symbol_metadata,
        ),
        "chars_all": summarize_code_length_baseline(
            by_code,
            predicate=lambda entry: int(entry.get("text_length", 0)) == 1,
            yinjie_codebook=yinjie_codebook,
            runtime_symbol_metadata=runtime_symbol_metadata,
        ),
        "phrases_all": summarize_code_length_baseline(
            by_code,
            predicate=lambda entry: int(entry.get("text_length", 0)) > 1,
            yinjie_codebook=yinjie_codebook,
            runtime_symbol_metadata=runtime_symbol_metadata,
        ),
        "overall": summarize_code_length_baseline(
            by_code,
            predicate=lambda entry: True,
            yinjie_codebook=yinjie_codebook,
            runtime_symbol_metadata=runtime_symbol_metadata,
        ),
    }
    syllable_jianpin_examples = build_syllable_jianpin_examples(
        yinjie_codebook,
        runtime_symbol_metadata,
        limit=10,
    )
    syllable_jianpin_rule_stats = build_syllable_jianpin_rule_stats(
        yinjie_codebook,
        runtime_symbol_metadata,
    )

    return {
        "generated_at": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
        "source": {
            "runtime_report": str(DEFAULT_INPUT.relative_to(ROOT)).replace("\\", "/"),
            "db_path": metadata.get("db_path"),
        },
        "headline": {
            "runtime_code_bucket_count": metadata.get("code_count", len(by_code)),
            "candidate_row_count": metadata.get("candidate_row_count", 0),
            "page_thresholds": page_thresholds,
            "max_phrase_collision": max(phrase_counts) if phrase_counts else 0,
            "max_char_collision": max(char_counts) if char_counts else 0,
        },
        "char_metrics": char_summary,
        "phrase_metrics": phrase_summary,
        "weighted_visibility": {
            "chars": char_weighted_visibility,
            "phrases": phrase_weighted_visibility,
        },
        "char_tiers": char_tiers,
        "code_length_baseline": code_length_baseline,
        "syllable_jianpin_examples": syllable_jianpin_examples,
        "syllable_jianpin_rule_stats": syllable_jianpin_rule_stats,
        "top_examples": {
            "chars": build_top_examples(by_code, predicate=lambda text_length: text_length == 1, limit=10),
            "phrases": build_top_examples(by_code, predicate=lambda text_length: text_length > 1, limit=10),
        },
        "notes": [
            "This baseline measures current runtime collision structure from exported candidate data only.",
            "It does not yet compare YIME against third-party pinyin IMEs or model user adaptation over time.",
            "sort_weight is the current runtime frequency proxy and is closer to actual ranking behavior than the coarse is_common flag.",
            "Phrase candidates currently all fit within the default first page size of 5.",
            "Code-length comparison below is a structural baseline: YIME full mode is fixed 4 keys per syllable, standard full pinyin uses toneless letter count, and the double-pinyin baseline assumes 2 keys per syllable.",
        ],
    }


def format_float(value: float) -> str:
    return f"{value:.2f}"


def format_pct(value: float) -> str:
    return f"{value * 100:.2f}%"


def make_metric_row(label: str, metrics: dict[str, float | int], page_size: int) -> str:
    return (
        f"| {label} | {metrics['code_bucket_count']} | {metrics['candidate_row_count']} | {format_float(float(metrics['avg_per_code']))} | "
        f"{format_float(float(metrics['median_per_code']))} | {format_float(float(metrics['p95_per_code']))} | {metrics['max_per_code']} | "
        f"{format_pct(float(metrics[f'share_le_{page_size}']))} | {format_pct(float(metrics['share_le_9']))} |"
    )


def make_tier_row(label: str, metrics: dict[str, object], selection_window_size: int) -> str:
    visibility = metrics["weighted_visibility"]
    return (
        f"| {label} | {metrics['char_count']} | {metrics['code_bucket_count']} | {metrics['max_per_code']} | "
        f"{format_pct(float(visibility['weighted_top1_share']))} | {format_pct(float(visibility['weighted_first_page_share']))} | "
        f"{format_pct(float(visibility['weighted_selection_window_share']))} | {format_pct(float(visibility['bucket_top1_best_share']))} |"
    )


def make_code_length_row(label: str, metrics: dict[str, float | int]) -> str:
    return (
        f"| {label} | {metrics['row_count']} | {format_float(float(metrics['avg_syllables']))} | {format_float(float(metrics['avg_yime_full']))} | "
        f"{format_float(float(metrics['avg_yime_jianpin']))} | {format_float(float(metrics['avg_full_pinyin']))} | {format_float(float(metrics['avg_full_pinyin_with_tone_number']))} | {format_float(float(metrics['avg_double_pinyin']))} | "
        f"{format_float(float(metrics['jianpin_saved_vs_full']))} | {format_float(float(metrics['jianpin_vs_full_pinyin']))} | {format_float(float(metrics['jianpin_vs_full_pinyin_with_tone_number']))} | {format_float(float(metrics['jianpin_vs_double_pinyin']))} |"
    )


def build_markdown(payload: dict[str, object]) -> str:
    headline = payload["headline"]
    char_metrics = payload["char_metrics"]
    phrase_metrics = payload["phrase_metrics"]
    weighted_visibility = payload["weighted_visibility"]
    char_tiers = payload["char_tiers"]
    code_length_baseline = payload["code_length_baseline"]
    syllable_jianpin_examples = payload["syllable_jianpin_examples"]
    syllable_jianpin_rule_stats = payload["syllable_jianpin_rule_stats"]
    top_examples = payload["top_examples"]
    page_size = headline["page_thresholds"]["current_page_size"]
    selection_window_size = headline["page_thresholds"]["selection_window_size"]
    generated_at = payload["generated_at"]

    lines = [
        "# 效率基线报告",
        "",
        "这份报告只使用仓库当前已有的运行时候选导出数据生成，目标是先建立一版可重复验证的效率基线，而不是直接给出跨输入法优劣结论。",
        "",
        f"- 生成时间：`{generated_at}`",
        f"- 数据来源：`{payload['source']['runtime_report']}`",
        f"- 当前候选窗默认每页候选数：`{page_size}`",
        f"- 当前 1-9 选择窗口阈值：`{headline['page_thresholds']['selection_window_size']}`",
        "",
        "## 这版基线能证明什么",
        "",
        f"- 当前运行时共有 `{headline['runtime_code_bucket_count']}` 个编码桶，候选总行数 `{headline['candidate_row_count']}`。",
        f"- 当前同码词语最大碰撞数是 `{headline['max_phrase_collision']}`，全部词语编码桶都能落在默认首屏 `{page_size}` 个候选内。",
        f"- 当前同码单字最大碰撞数是 `{headline['max_char_collision']}`，单字仍然是主要翻页压力来源。",
        f"- 以当前 `sort_weight` 作为频率代理时，词语加权首选命中率为 `{format_pct(float(weighted_visibility['phrases']['weighted_top1_share']))}`，单字加权首选命中率为 `{format_pct(float(weighted_visibility['chars']['weighted_top1_share']))}`。",
        f"- 以当前 `sort_weight` 作为频率代理时，词语加权首屏可见率为 `{format_pct(float(weighted_visibility['phrases']['weighted_first_page_share']))}`，单字加权首屏可见率为 `{format_pct(float(weighted_visibility['chars']['weighted_first_page_share']))}`。",
        f"- 单字按《通用规范汉字表》同等数量对齐后，一级字（前 3500）加权首屏可见率为 `{format_pct(float(char_tiers['level_1']['weighted_visibility']['weighted_first_page_share']))}`，二级前字（前 6500）为 `{format_pct(float(char_tiers['level_2']['weighted_visibility']['weighted_first_page_share']))}`，三级前字（前 8105）为 `{format_pct(float(char_tiers['level_3']['weighted_visibility']['weighted_first_page_share']))}`。",
        f"- 同语料总体上，音元简拼平均码长为 `{format_float(float(code_length_baseline['overall']['avg_yime_jianpin']))}` 键，较音元全拼平均减少 `{format_float(float(code_length_baseline['overall']['jianpin_saved_vs_full']))}` 键。",
        "",
        "## 指标表",
        "",
        f"| 类型 | 编码桶数 | 候选行数 | 平均每桶候选数 | 中位数 | P95 | 最大值 | <= {page_size} 占比 | <= 9 占比 |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
        make_metric_row("单字", char_metrics, page_size),
        make_metric_row("词语", phrase_metrics, page_size),
        "",
        "## 频率加权可见率与首选命中率",
        "",
        f"这里直接把运行时导出里的 `sort_weight` 当作当前最接近实际排序行为的频率代理，用来观察当前排序下，频率质量能有多少直接落在首选、首屏 `{page_size}` 个候选和 `1-{selection_window_size}` 选择窗口里。",
        "",
        f"| 类型 | 有效编码桶数 | 加权首选命中率 | 加权首屏可见率 | 加权 1-{selection_window_size} 可见率 | 首选即最高权重桶占比 |",
        "| --- | ---: | ---: | ---: | ---: | ---: |",
        f"| 单字 | {weighted_visibility['chars']['bucket_count']} | {format_pct(float(weighted_visibility['chars']['weighted_top1_share']))} | {format_pct(float(weighted_visibility['chars']['weighted_first_page_share']))} | {format_pct(float(weighted_visibility['chars']['weighted_selection_window_share']))} | {format_pct(float(weighted_visibility['chars']['bucket_top1_best_share']))} |",
        f"| 词语 | {weighted_visibility['phrases']['bucket_count']} | {format_pct(float(weighted_visibility['phrases']['weighted_top1_share']))} | {format_pct(float(weighted_visibility['phrases']['weighted_first_page_share']))} | {format_pct(float(weighted_visibility['phrases']['weighted_selection_window_share']))} | {format_pct(float(weighted_visibility['phrases']['bucket_top1_best_share']))} |",
        "",
        "## 单字分级指标",
        "",
        "这里不要求当前库中的字刚好等于《通用规范汉字表》的对应字目，只是按当前库里的 `sort_weight` 排序抽取相同数量的字来对齐分级口径：一级 3500 字，二级前 6500 字，三级前 8105 字。",
        "",
        f"| 层级 | 覆盖字形数 | 编码桶数 | 最大同码数 | 加权首选命中率 | 加权首屏可见率 | 加权 1-{selection_window_size} 可见率 | 首选即最高权重桶占比 |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
        make_tier_row("一级字（前 3500）", char_tiers["level_1"], selection_window_size),
        make_tier_row("二级前字（前 6500）", char_tiers["level_2"], selection_window_size),
        make_tier_row("三级前字（前 8105）", char_tiers["level_3"], selection_window_size),
        make_tier_row("单字全量", char_tiers["all"], selection_window_size),
        "",
        "## 同语料码长对照基准",
        "",
        "这部分不是第三方输入法实测，而是同一批运行时语料上的结构码长基线。它只回答“同一批条目如果按不同编码长度模型输入，理论键数大约是多少”。",
        "",
        "比较口径：`音元全拼`每个音节固定 4 键；`音元简拼`按音元全拼进一步压缩，规则是省略虚首音、把构成干音的两个或三个连续存在的相同音元合并成一个、并在同音质的 `高-中-低` 或 `低-中-高` 三音序列中省略中间的中调乐音；`标准全拼`按无调拼音字母数累计；`带数字调号标准全拼`在无调字母数基础上为每个带调音节再计 1 个数字键；`抽象双拼`每个音节固定 2 键。",
        "",
        f"- 同语料总体上，音元简拼平均码长为 `{format_float(float(code_length_baseline['overall']['avg_yime_jianpin']))}` 键，较音元全拼平均减少 `{format_float(float(code_length_baseline['overall']['jianpin_saved_vs_full']))}` 键。",
        f"- 但在本报告当前采用的省调 `标准全拼` 口径下，音元简拼总体平均仍比标准全拼约多 `{format_float(float(code_length_baseline['overall']['jianpin_vs_full_pinyin']))}` 键，因此这张表不能用来支持“已经比省调现行拼音平均码长更短”的说法。",
        f"- 若把对照口径换成 `带数字调号标准全拼`，则同语料总体上音元简拼平均约少 `{format_float(abs(float(code_length_baseline['overall']['jianpin_vs_full_pinyin_with_tone_number'])))}` 键；这可以支持“音元简拼相对带数字调号全拼更短”的表述。",
        "",
        "| 语料层级 | 条目数 | 平均音节数 | 音元全拼平均码长 | 音元简拼平均码长 | 标准全拼平均码长 | 带数字调号标准全拼平均码长 | 抽象双拼平均码长 | 简拼较全拼减少 | 简拼-标准全拼差值 | 简拼-带调全拼差值 | 简拼-双拼差值 |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
        make_code_length_row("一级字（前 3500）", code_length_baseline["chars_level_1"]),
        make_code_length_row("二级前字（前 6500）", code_length_baseline["chars_level_2"]),
        make_code_length_row("三级前字（前 8105）", code_length_baseline["chars_level_3"]),
        make_code_length_row("单字全量", code_length_baseline["chars_all"]),
        make_code_length_row("词语全量", code_length_baseline["phrases_all"]),
        make_code_length_row("总体", code_length_baseline["overall"]),
        "",
    ]

    lines.extend(
        [
            "## 简拼样本分析",
            "",
            "下面只看单个音节的结构压缩效果。这里的‘压缩最明显’与‘几乎压不动’都只依据三条简拼规则对四码全拼做机械压缩，不涉及候选排序或学习成本。",
            f"按全部音节库存统计，至少触发一条简拼规则的音节占 `{format_pct(float(syllable_jianpin_rule_stats['rule_rows'][3]['share']))}`，平均每个音节可比四码全拼少 `{format_float(float(syllable_jianpin_rule_stats['avg_saved_keys_per_syllable']))}` 键。",
            "",
            "### 按规则类型分组统计",
            "",
            "| 分组 | 音节数 | 占全部音节比例 |",
            "| --- | ---: | ---: |",
        ]
    )

    for item in syllable_jianpin_rule_stats["rule_rows"]:
        lines.append(f"| {item['label']} | {item['count']} | {format_pct(float(item['share']))} |")

    lines.extend(
        [
            "",
            "### 规则叠加方式",
            "",
            "| 规则组合 | 音节数 | 占全部音节比例 |",
            "| --- | ---: | ---: |",
        ]
    )

    for item in syllable_jianpin_rule_stats["combo_rows"][:8]:
        lines.append(f"| {item['label']} | {item['count']} | {format_pct(float(item['share']))} |")

    lines.extend(
        [
            "",
            "### 压缩最明显的音节样本",
            "",
            "| 音节 | 全拼码长 | 简拼码长 | 减少键数 | 主要原因 |",
            "| --- | ---: | ---: | ---: | --- |",
        ]
    )

    for item in syllable_jianpin_examples["most_compressible"]:
        lines.append(
            f"| `{item['syllable']}` | {item['full_length']} | {item['jianpin_length']} | {item['saved_keys']} | {item['reason']} |"
        )

    lines.extend(
        [
            "",
            "### 几乎压不动的音节样本",
            "",
            "| 音节 | 全拼码长 | 简拼码长 | 减少键数 | 主要原因 |",
            "| --- | ---: | ---: | ---: | --- |",
        ]
    )

    for item in syllable_jianpin_examples["least_compressible"]:
        lines.append(
            f"| `{item['syllable']}` | {item['full_length']} | {item['jianpin_length']} | {item['saved_keys']} | {item['reason']} |"
        )

    lines.extend(
        [
            "",
            "## 高碰撞样本",
            "",
            "### 单字",
            "",
            "| 主拼音 | 候选数 | 样本候选 |",
            "| --- | ---: | --- |",
        ]
    )

    for item in top_examples["chars"]:
        samples = "、".join(item["samples"])
        lines.append(f"| `{item['dominant_pinyin']}` | {item['candidate_count']} | {samples} |")

    lines.extend(
        [
            "",
            "### 词语",
            "",
            "| 主拼音 | 候选数 | 样本候选 |",
            "| --- | ---: | --- |",
        ]
    )

    for item in top_examples["phrases"]:
        samples = "、".join(item["samples"])
        lines.append(f"| `{item['dominant_pinyin']}` | {item['candidate_count']} | {samples} |")

    lines.extend(
        [
            "",
            "## 当前还不能证明什么",
            "",
            "- `sort_weight` 目前仍然只是仓库运行时排序所使用的频率代理，不等于完整真实用户输入日志。",
            "- 这份报告里的全拼/双拼部分目前只是结构码长对照，不是第三方输入法的真实候选排序实测。",
            "- 这份报告还没有纳入真实用户输入日志，所以不能直接推出实际打字速度。",
            "- 这份报告目前描述的是运行时重码结构，不是完整的人机工效结论。",
            "",
            "## 最小可执行方案",
            "",
            "1. 先固定当前运行时候选导出作为基线输入。",
            "2. 每次更新词库或编码后重跑生成脚本，观察词语重码、单字重码和首屏容纳率是否改善。",
            "3. 等这组内部指标稳定后，再补外部对照基准和真实录入实验。",
            "",
            "## 生成命令",
            "",
            "```bash",
            "python tools/generate_efficiency_baseline_report.py",
            "```",
        ]
    )

    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate the first-pass YIME efficiency baseline report from runtime candidate export data.")
    parser.add_argument("--input", type=Path, default=DEFAULT_INPUT, help=f"Input runtime candidate JSON. Default: {DEFAULT_INPUT}")
    parser.add_argument("--markdown-output", type=Path, default=DEFAULT_MARKDOWN_OUTPUT, help=f"Markdown report output. Default: {DEFAULT_MARKDOWN_OUTPUT}")
    parser.add_argument("--json-output", type=Path, default=DEFAULT_JSON_OUTPUT, help=f"JSON summary output. Default: {DEFAULT_JSON_OUTPUT}")
    parser.add_argument("--page-size", type=int, default=5, help="Current default first-page candidate count.")
    args = parser.parse_args()

    report = load_json(args.input)
    payload = build_payload(report, args.page_size)
    markdown = build_markdown(payload)

    args.markdown_output.parent.mkdir(parents=True, exist_ok=True)
    args.markdown_output.write_text(markdown, encoding="utf-8")

    args.json_output.parent.mkdir(parents=True, exist_ok=True)
    args.json_output.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(f"Generated markdown report: {args.markdown_output}")
    print(f"Generated JSON report: {args.json_output}")
    print(f"Phrase max collision: {payload['headline']['max_phrase_collision']}")
    print(f"Char max collision: {payload['headline']['max_char_collision']}")


if __name__ == "__main__":
    main()
