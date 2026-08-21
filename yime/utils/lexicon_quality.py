from __future__ import annotations

import json
import sqlite3
from collections import defaultdict
from pathlib import Path
from typing import Any, Iterable
from urllib.parse import quote

from yime.input_model.particle_constructions import review_particle_construction

# 助词 / 语气词尾字及其当前数字标调读音。只按字形会把“目的 di4”“花呢 ni2”
# “爪哇 wa1”等词误报；运行扫描必须同时命中末字和末音节读音。
PARTICLE_SUFFIX_PINYIN = {
    "的": frozenset({"de5"}),
    "地": frozenset({"de5"}),
    "得": frozenset({"de5"}),
    "着": frozenset({"zhe5"}),
    "了": frozenset({"le5"}),
    "过": frozenset({"guo4"}),
    "吗": frozenset({"ma5"}),
    "呢": frozenset({"ne5"}),
    "吧": frozenset({"ba5"}),
    "啊": frozenset({"a5"}),
    "嘛": frozenset({"ma5"}),
    "呀": frozenset({"ya5"}),
    "哦": frozenset({"o2", "o4", "o5", "e2"}),
    "呗": frozenset({"bei5"}),
    "哇": frozenset({"wa5"}),
    "呐": frozenset({"na4"}),
    "麽": frozenset({"me5"}),
}
PARTICLE_SUFFIX_CHARS = frozenset(PARTICLE_SUFFIX_PINYIN)

# 常见短语白名单：即使以助词结尾也跳过 suffix_particle 警告。
PARTICLE_SUFFIX_WHITELIST = frozenset({
    "你的",
    "我的",
    "他的",
    "她的",
    "它的",
    "我们的",
    "你们的",
    "他们的",
    "好的",
    "对了",
    "行了",
    "可以了",
    "知道了",
    "怎么了",
    "为什么",
    "是不是",
})

REQUIRED_CANDIDATE_FIELDS = (
    "text",
    "entry_type",
    "entry_id",
    "pinyin_tone",
    "yime_code",
    "sort_weight",
    "is_common",
    "text_length",
    "updated_at",
)

RUNTIME_CANDIDATES_COLUMNS = """
SELECT
    text,
    entry_type,
    CAST(entry_id AS TEXT) AS entry_id,
    pinyin_tone,
    yime_code,
    sort_weight,
    is_common,
    text_length,
    updated_at
"""

SOURCE_PHRASE_SQL = """
SELECT id, phrase, marked_pinyin, numeric_pinyin, reading_rank
FROM phrase_readings
ORDER BY id
"""

RUNTIME_TABLE_PREFERENCE = (
    "runtime_candidates_materialized",
    "runtime_candidates",
)

CORE_COMPONENT_MAXIMUM_LENGTH = 4


def particle_suffix_review_role(
    text: str,
    *,
    numeric_pinyin: str | None = None,
    maximum_component_length: int = CORE_COMPONENT_MAXIMUM_LENGTH,
) -> str:
    """Route a suffix signal to role review without deciding lexical status."""

    stripped = str(text or "").strip()
    if not stripped:
        raise ValueError("text must be non-empty")
    if maximum_component_length < 1:
        raise ValueError("maximum_component_length must be positive")
    if numeric_pinyin:
        return review_particle_construction(
            stripped,
            numeric_pinyin,
            maximum_component_length=maximum_component_length,
        ).suggested_role
    if len(stripped) <= maximum_component_length:
        return "core_component_candidate"
    return "dynamic_sentence_candidate"


def make_report(*, sample_limit: int, inputs: dict[str, str]) -> dict[str, Any]:
    return {
        "tool": "lexicon_lint",
        "inputs": inputs,
        "summary": {
            "candidate_rows": 0,
            "source_phrase_rows": 0,
            "error_count": 0,
            "warning_count": 0,
            "suffix_particle_count": 0,
            "source_suffix_particle_count": 0,
            "placeholder_phrase_count": 0,
            "suffix_particle_by_char": {},
            "source_suffix_particle_by_char": {},
        },
        "errors": defaultdict(list),
        "warnings": defaultdict(list),
        "sample_limit": sample_limit,
        "notes": [
            (
                "suffix_particle 是候选角色审阅信号：1–4 字项优先审查其"
                "核心组件价值，更长项优先审查动态句子恢复；不会自动清理词库。"
            ),
            "请配合 docs/LEXICON_LINT.md 使用；人工决定应进入独立候选整理覆盖层。",
        ],
    }


def record_issue(
    report: dict[str, Any],
    level: str,
    category: str,
    detail: dict[str, Any],
) -> None:
    summary_key = "error_count" if level == "errors" else "warning_count"
    report["summary"][summary_key] += 1
    if category == "suffix_particle":
        report["summary"]["suffix_particle_count"] += 1
        suffix_char = str(detail.get("suffix_char") or "")
        counts = report["summary"]["suffix_particle_by_char"]
        counts[suffix_char] = counts.get(suffix_char, 0) + 1
    if category == "source_suffix_particle":
        report["summary"]["source_suffix_particle_count"] += 1
        suffix_char = str(detail.get("suffix_char") or "")
        counts = report["summary"]["source_suffix_particle_by_char"]
        counts[suffix_char] = counts.get(suffix_char, 0) + 1
    if category == "placeholder_phrase_code":
        report["summary"]["placeholder_phrase_count"] += 1
    bucket = report[level][category]
    sample_limit = report["sample_limit"]
    if sample_limit <= 0:
        return
    if "sort_weight" in detail:
        bucket.append(detail)
        bucket.sort(
            key=lambda item: (
                -float(item.get("sort_weight") or 0.0),
                str(item.get("text") or item.get("phrase") or ""),
            )
        )
        del bucket[sample_limit:]
    elif len(bucket) < sample_limit:
        bucket.append(detail)


def finalize_report(report: dict[str, Any]) -> dict[str, Any]:
    report["errors"] = {key: value for key, value in sorted(report["errors"].items())}
    report["warnings"] = {key: value for key, value in sorted(report["warnings"].items())}
    return report


def ends_with_particle(
    text: str,
    *,
    pinyin_tone: str | None = None,
    min_length: int = 2,
) -> bool:
    stripped = str(text or "").strip()
    if len(stripped) < min_length:
        return False
    suffix_char = stripped[-1]
    if suffix_char not in PARTICLE_SUFFIX_CHARS:
        return False
    if pinyin_tone is None:
        return True
    pinyin_tokens = str(pinyin_tone or "").split()
    if not pinyin_tokens:
        return False
    return pinyin_tokens[-1] in PARTICLE_SUFFIX_PINYIN[suffix_char]


def is_whitelisted_phrase(text: str) -> bool:
    return str(text or "").strip() in PARTICLE_SUFFIX_WHITELIST


def is_placeholder_phrase(entry_type: str, yime_code: str, pinyin_tone: str) -> bool:
    return (
        entry_type == "phrase"
        and str(yime_code or "").strip() != ""
        and str(yime_code or "").strip() == str(pinyin_tone or "").strip()
    )


def lint_candidate_row(
    report: dict[str, Any],
    *,
    code_key: str,
    candidate: dict[str, Any],
    source: str,
) -> None:
    report["summary"]["candidate_rows"] += 1

    missing_fields = [field for field in REQUIRED_CANDIDATE_FIELDS if field not in candidate]
    if missing_fields:
        record_issue(report, "errors", "missing_required_fields", {
            "source": source,
            "code_key": code_key,
            "text": candidate.get("text"),
            "missing_fields": missing_fields,
        })
        return

    text = str(candidate.get("text") or "")
    entry_type = str(candidate.get("entry_type") or "")
    yime_code = str(candidate.get("yime_code") or "")
    pinyin_tone = str(candidate.get("pinyin_tone") or "")

    if yime_code != code_key:
        record_issue(report, "errors", "json_code_key_mismatch", {
            "source": source,
            "code_key": code_key,
            "text": text,
            "candidate_yime_code": yime_code,
        })

    if entry_type not in {"char", "phrase"}:
        record_issue(report, "errors", "invalid_entry_type", {
            "source": source,
            "text": text,
            "entry_type": entry_type,
        })

    if is_placeholder_phrase(entry_type, yime_code, pinyin_tone):
        sort_weight = float(candidate.get("sort_weight") or 0.0)
        record_issue(report, "warnings", "placeholder_phrase_code", {
            "source": source,
            "text": text,
            "pinyin_tone": pinyin_tone,
            "yime_code": yime_code,
            "sort_weight": sort_weight,
            "entry_id": candidate.get("entry_id"),
        })

    if (
        entry_type == "phrase"
        and ends_with_particle(text, pinyin_tone=pinyin_tone)
        and not is_whitelisted_phrase(text)
    ):
        sort_weight = float(candidate.get("sort_weight") or 0.0)
        record_issue(report, "warnings", "suffix_particle", {
            "source": source,
            "text": text,
            "suffix_char": text[-1],
            "pinyin_tone": pinyin_tone,
            "suggested_role": particle_suffix_review_role(
                text,
                numeric_pinyin=pinyin_tone,
            ),
            "construction_evidence": [
                item.to_dict()
                for item in review_particle_construction(
                    text,
                    pinyin_tone,
                ).evidence
            ],
            "sort_weight": sort_weight,
            "entry_id": candidate.get("entry_id"),
        })


def lint_runtime_json_payload(
    payload: dict[str, Any],
    report: dict[str, Any],
    *,
    source_label: str,
) -> None:
    by_code = payload.get("by_code")
    if not isinstance(by_code, dict):
        record_issue(report, "errors", "invalid_runtime_json", {
            "source": source_label,
            "detail": "top-level by_code is missing or not an object",
        })
        return

    for code_key, candidates in by_code.items():
        if not isinstance(candidates, list):
            record_issue(report, "errors", "invalid_runtime_json", {
                "source": source_label,
                "code_key": code_key,
                "detail": "candidate bucket is not a list",
            })
            continue
        for candidate in candidates:
            if not isinstance(candidate, dict):
                record_issue(report, "errors", "invalid_runtime_json", {
                    "source": source_label,
                    "code_key": code_key,
                    "detail": "candidate row is not an object",
                })
                continue
            lint_candidate_row(
                report,
                code_key=str(code_key),
                candidate=candidate,
                source=source_label,
            )


def _readonly_connection(path: Path) -> sqlite3.Connection:
    resolved = path.resolve().as_posix()
    uri = f"file:{quote(resolved, safe='/:')}?mode=ro"
    return sqlite3.connect(uri, uri=True)


def _resolve_runtime_table(conn: sqlite3.Connection) -> str:
    for table_name in RUNTIME_TABLE_PREFERENCE:
        row = conn.execute(
            "SELECT type FROM sqlite_master WHERE name = ?",
            (table_name,),
        ).fetchone()
        if row is not None and row[0] in {"table", "view"}:
            return table_name
    raise sqlite3.OperationalError(
        "missing runtime_candidates_materialized/runtime_candidates"
    )


def load_runtime_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def lint_runtime_json_file(path: Path, report: dict[str, Any]) -> None:
    try:
        payload = load_runtime_json(path)
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        record_issue(report, "errors", "runtime_json_read_error", {
            "source": str(path),
            "detail": str(exc),
        })
        return
    lint_runtime_json_payload(payload, report, source_label=str(path))


def lint_runtime_db_file(path: Path, report: dict[str, Any]) -> None:
    try:
        conn = _readonly_connection(path)
    except sqlite3.Error as exc:
        record_issue(report, "errors", "runtime_db_read_error", {
            "source": str(path),
            "detail": str(exc),
        })
        return
    conn.row_factory = sqlite3.Row
    try:
        table_name = _resolve_runtime_table(conn)
        cursor = conn.execute(
            f"{RUNTIME_CANDIDATES_COLUMNS} "
            f"FROM {table_name} "
            "ORDER BY entry_type, entry_id"
        )
        for row in cursor:
            candidate = {key: row[key] for key in row.keys()}
            lint_candidate_row(
                report,
                code_key=str(candidate["yime_code"]),
                candidate=candidate,
                source=str(path),
            )
    except sqlite3.Error as exc:
        record_issue(report, "errors", "runtime_db_read_error", {
            "source": str(path),
            "detail": str(exc),
        })
    finally:
        conn.close()


def lint_source_db_file(path: Path, report: dict[str, Any]) -> None:
    try:
        conn = _readonly_connection(path)
    except sqlite3.Error as exc:
        record_issue(report, "errors", "source_db_read_error", {
            "source": str(path),
            "detail": str(exc),
        })
        return
    try:
        cursor = conn.execute(SOURCE_PHRASE_SQL)
        for row_id, phrase, marked_pinyin, numeric_pinyin, reading_rank in cursor:
            report["summary"]["source_phrase_rows"] += 1
            phrase_text = str(phrase or "").strip()
            if not phrase_text:
                record_issue(report, "errors", "empty_source_phrase", {
                    "source": str(path),
                    "id": row_id,
                })
                continue

            if (
                ends_with_particle(
                    phrase_text,
                    pinyin_tone=str(numeric_pinyin or ""),
                )
                and not is_whitelisted_phrase(phrase_text)
            ):
                record_issue(report, "warnings", "source_suffix_particle", {
                    "source": str(path),
                    "id": row_id,
                    "phrase": phrase_text,
                    "suffix_char": phrase_text[-1],
                    "marked_pinyin": marked_pinyin,
                    "numeric_pinyin": numeric_pinyin,
                    "reading_rank": reading_rank,
                    "suggested_role": particle_suffix_review_role(
                        phrase_text,
                        numeric_pinyin=str(numeric_pinyin or ""),
                    ),
                    "construction_evidence": [
                        item.to_dict()
                        for item in review_particle_construction(
                            phrase_text,
                            str(numeric_pinyin or ""),
                        ).evidence
                    ],
                })
    except sqlite3.Error as exc:
        record_issue(report, "errors", "source_db_read_error", {
            "source": str(path),
            "detail": str(exc),
        })
    finally:
        conn.close()


def iter_review_samples(report: dict[str, Any]) -> Iterable[dict[str, Any]]:
    """Return sampled warnings for human review, never an exhaustive clean set."""
    for category in ("suffix_particle", "placeholder_phrase_code", "source_suffix_particle"):
        for item in report.get("warnings", {}).get(category, []):
            yield {"category": category, **item}
