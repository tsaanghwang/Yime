"""Export reviewable lexicon-quality signals without writing candidate decisions."""

from __future__ import annotations

import csv
import json
import sqlite3
from collections import Counter
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import quote

from .lexicon_quality import (
    PARTICLE_SUFFIX_PINYIN,
    PARTICLE_SUFFIX_WHITELIST,
    RUNTIME_TABLE_PREFERENCE,
)
from yime.input_model.particle_constructions import (
    review_particle_construction_readings,
)


REVIEW_TIER_ORDER = {
    "bcc_ge_10000": 0,
    "bcc_1000_9999": 1,
    "bcc_100_999": 2,
    "bcc_10_99": 3,
    "bcc_1_9": 4,
    "no_bcc": 5,
}

QUEUE_FIELDS = (
    "rank",
    "review_tier",
    "policy_lane",
    "suggested_role",
    "construction_systems",
    "construction_ids",
    "construction_interfaces",
    "theoretical_basis",
    "text",
    "pinyin_tones",
    "suffix_char",
    "runtime_sort_weight",
    "runtime_reading_rows",
    "bcc_frequency",
    "candidate_class",
    "integration_policy",
    "decision_status",
    "has_context_evidence",
    "rationale",
    "assessor",
)


@dataclass(frozen=True)
class ReviewQueueRow:
    rank: int
    review_tier: str
    policy_lane: str
    suggested_role: str
    construction_systems: str
    construction_ids: str
    construction_interfaces: str
    theoretical_basis: str
    text: str
    pinyin_tones: str
    suffix_char: str
    runtime_sort_weight: float
    runtime_reading_rows: int
    bcc_frequency: int
    candidate_class: str
    integration_policy: str
    decision_status: str
    has_context_evidence: int
    rationale: str
    assessor: str


@dataclass(frozen=True)
class ReviewExportResult:
    queue_path: Path
    summary_path: Path
    manifest_path: Path
    queue_count: int
    excluded_decided_count: int
    tier_counts: dict[str, int]
    suffix_counts: dict[str, int]
    role_counts: dict[str, int]


def _readonly_uri(path: Path) -> str:
    resolved = path.resolve().as_posix()
    return f"file:{quote(resolved, safe='/:')}?mode=ro"


def _runtime_table(conn: sqlite3.Connection) -> str:
    for table_name in RUNTIME_TABLE_PREFERENCE:
        row = conn.execute(
            "SELECT type FROM sqlite_master WHERE name = ?",
            (table_name,),
        ).fetchone()
        if row is not None and row[0] in {"table", "view"}:
            return table_name
    raise ValueError("runtime database has no runtime candidate table")


def _validate_input_model(conn: sqlite3.Connection) -> None:
    existing = {
        str(row[0])
        for row in conn.execute(
            """
            SELECT name
            FROM input_model.sqlite_master
            WHERE type IN ('table', 'view')
            """
        )
    }
    required = {
        "candidate_universe",
        "assessments",
        "context_evidence",
    }
    missing = required - existing
    if missing:
        raise ValueError(
            "input model is missing required objects: " + ", ".join(sorted(missing))
        )


def review_tier(bcc_frequency: int) -> str:
    if bcc_frequency >= 10_000:
        return "bcc_ge_10000"
    if bcc_frequency >= 1_000:
        return "bcc_1000_9999"
    if bcc_frequency >= 100:
        return "bcc_100_999"
    if bcc_frequency >= 10:
        return "bcc_10_99"
    if bcc_frequency >= 1:
        return "bcc_1_9"
    return "no_bcc"


def _flagged_where() -> tuple[str, list[object]]:
    clauses: list[str] = []
    parameters: list[object] = []
    for suffix_char, readings in sorted(PARTICLE_SUFFIX_PINYIN.items()):
        reading_clauses: list[str] = []
        clause_parameters: list[object] = [suffix_char]
        for reading in sorted(readings):
            reading_clauses.append(
                "(pinyin_tone = ? OR pinyin_tone LIKE ?)"
            )
            clause_parameters.extend((reading, f"% {reading}"))
        clauses.append(
            f"(SUBSTR(text, -1, 1) = ? AND ({' OR '.join(reading_clauses)}))"
        )
        parameters.extend(clause_parameters)

    whitelist_clause = ""
    if PARTICLE_SUFFIX_WHITELIST:
        placeholders = ", ".join("?" for _ in PARTICLE_SUFFIX_WHITELIST)
        whitelist_clause = f" AND text NOT IN ({placeholders})"
        parameters.extend(sorted(PARTICLE_SUFFIX_WHITELIST))

    return (
        "(" + " OR ".join(clauses) + ")" + whitelist_clause,
        parameters,
    )


def collect_review_queue(
    *,
    runtime_database: Path,
    input_model_database: Path,
) -> tuple[list[ReviewQueueRow], int]:
    if not runtime_database.is_file():
        raise FileNotFoundError(f"runtime database does not exist: {runtime_database}")
    if not input_model_database.is_file():
        raise FileNotFoundError(
            f"input model database does not exist: {input_model_database}"
        )

    conn = sqlite3.connect(_readonly_uri(runtime_database), uri=True)
    conn.row_factory = sqlite3.Row
    try:
        runtime_table = _runtime_table(conn)
        conn.execute(
            "ATTACH DATABASE ? AS input_model",
            (_readonly_uri(input_model_database),),
        )
        _validate_input_model(conn)
        where_sql, parameters = _flagged_where()
        rows = conn.execute(
            f"""
            WITH flagged AS (
                SELECT
                    text,
                    SUBSTR(text, -1, 1) AS suffix_char,
                    GROUP_CONCAT(DISTINCT pinyin_tone) AS pinyin_tones,
                    MAX(sort_weight) AS runtime_sort_weight,
                    COUNT(*) AS runtime_reading_rows
                FROM {runtime_table}
                WHERE entry_type = 'phrase'
                  AND LENGTH(text) >= 2
                  AND {where_sql}
                GROUP BY text
            )
            SELECT
                f.text,
                f.suffix_char,
                f.pinyin_tones,
                f.runtime_sort_weight,
                f.runtime_reading_rows,
                COALESCE(u.bcc_frequency, 0) AS bcc_frequency,
                COALESCE(a.candidate_class, u.baseline_class, 'unknown')
                    AS candidate_class,
                COALESCE(a.integration_policy, u.baseline_policy, 'needs_review')
                    AS integration_policy,
                COALESCE(a.decision_status, 'proposed') AS decision_status,
                CASE WHEN EXISTS (
                    SELECT 1
                    FROM input_model.context_evidence AS e
                    WHERE e.text = f.text
                ) THEN 1 ELSE 0 END AS has_context_evidence,
                COALESCE(a.rationale, u.baseline_rule, 'missing_candidate_universe')
                    AS rationale,
                COALESCE(a.assessor, 'baseline:' || COALESCE(u.baseline_rule, 'missing'))
                    AS assessor
            FROM flagged AS f
            LEFT JOIN input_model.candidate_universe AS u USING (text)
            LEFT JOIN input_model.assessments AS a USING (text)
            """,
            parameters,
        ).fetchall()
    finally:
        conn.close()

    active_rows: list[sqlite3.Row] = []
    excluded_decided_count = 0
    for row in rows:
        if str(row["decision_status"]) in {"approved", "rejected"}:
            excluded_decided_count += 1
            continue
        active_rows.append(row)

    active_rows.sort(
        key=lambda row: (
            REVIEW_TIER_ORDER[review_tier(int(row["bcc_frequency"]))],
            -int(row["bcc_frequency"]),
            -float(row["runtime_sort_weight"]),
            str(row["text"]),
        )
    )

    queue: list[ReviewQueueRow] = []
    for rank, row in enumerate(active_rows, start=1):
        integration_policy = str(row["integration_policy"])
        pinyin_tones = "; ".join(
            sorted(set(str(row["pinyin_tones"] or "").split(",")))
        )
        construction_review = review_particle_construction_readings(
            str(row["text"]),
            pinyin_tones.split("; "),
        )
        queue.append(
            ReviewQueueRow(
                rank=rank,
                review_tier=review_tier(int(row["bcc_frequency"])),
                policy_lane=(
                    "unclassified"
                    if integration_policy == "needs_review"
                    else "source_classified"
                ),
                suggested_role=construction_review.suggested_role,
                construction_systems="; ".join(construction_review.systems),
                construction_ids="; ".join(construction_review.construction_ids),
                construction_interfaces="; ".join(construction_review.interfaces),
                theoretical_basis=construction_review.theoretical_basis,
                text=str(row["text"]),
                pinyin_tones=pinyin_tones,
                suffix_char=str(row["suffix_char"]),
                runtime_sort_weight=float(row["runtime_sort_weight"]),
                runtime_reading_rows=int(row["runtime_reading_rows"]),
                bcc_frequency=int(row["bcc_frequency"]),
                candidate_class=str(row["candidate_class"]),
                integration_policy=integration_policy,
                decision_status=str(row["decision_status"]),
                has_context_evidence=int(row["has_context_evidence"]),
                rationale=str(row["rationale"]),
                assessor=str(row["assessor"]),
            )
        )
    return queue, excluded_decided_count


def _write_queue(path: Path, rows: list[ReviewQueueRow]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=QUEUE_FIELDS,
            delimiter="\t",
            lineterminator="\n",
        )
        writer.writeheader()
        for row in rows:
            writer.writerow(asdict(row))


def _cell(value: object) -> str:
    return str(value).replace("|", "\\|").replace("\n", " ")


def _table(headers: tuple[str, ...], rows: list[tuple[object, ...]]) -> list[str]:
    lines = [
        "| " + " | ".join(headers) + " |",
        "| " + " | ".join("---" for _ in headers) + " |",
    ]
    lines.extend(
        "| " + " | ".join(_cell(value) for value in row) + " |"
        for row in rows
    )
    return lines


def _summary_lines(
    *,
    queue: list[ReviewQueueRow],
    excluded_decided_count: int,
    summary_limit: int,
    per_suffix_limit: int,
) -> list[str]:
    tier_counts = Counter(row.review_tier for row in queue)
    suffix_counts = Counter(row.suffix_char for row in queue)
    lane_counts = Counter(row.policy_lane for row in queue)
    role_counts = Counter(row.suggested_role for row in queue)
    system_counts: Counter[str] = Counter()
    for row in queue:
        system_counts.update(
            item for item in row.construction_systems.split("; ") if item
        )
    context_count = sum(row.has_context_evidence for row in queue)
    high_frequency_count = sum(
        tier_counts.get(tier, 0)
        for tier in ("bcc_ge_10000", "bcc_1000_9999")
    )

    top_rows = [
        (
            row.rank,
            row.text,
            row.pinyin_tones,
            row.suffix_char,
            row.review_tier,
            row.bcc_frequency,
            f"{row.runtime_sort_weight:.3f}",
            row.candidate_class,
            row.integration_policy,
            row.decision_status,
        )
        for row in queue[:summary_limit]
    ]
    lines = [
        "# 助词构式部件审阅摘要",
        "",
        "本文件由 `tools/export_lexicon_quality_review.py` 机械导出。命中项只是待审信号，",
        "不会自动写入 `assessments`，也不是删除清单。排序优先使用 BCC 频次，再使用运行权重。",
        "",
        f"- 待审不同字串：`{len(queue)}`",
        f"- 已有 approved/rejected 决策而从队列排除：`{excluded_decided_count}`",
        f"- 已有上下文证据：`{context_count}`",
        f"- BCC 频次不低于 1,000 的首批队列：`{high_frequency_count}`",
        f"- 未分类通道：`{lane_counts.get('unclassified', 0)}`",
        f"- 来源已分类通道：`{lane_counts.get('source_classified', 0)}`",
        (
            "- 长串动态句子角色候选："
            f"`{role_counts.get('dynamic_sentence_candidate', 0)}`"
        ),
        (
            "- 上下文证据缺口：当前队列没有 KWIC；本地 BCC 输入是频次表，"
            "不能从计数反向重建原句。"
            if context_count == 0 and queue
            else f"- 仍缺上下文证据：`{len(queue) - context_count}`"
        ),
        "",
        "## 构式系统与建议角色",
        "",
        *_table(
            ("构式系统", "数量"),
            sorted(system_counts.items(), key=lambda item: (-item[1], item[0])),
        ),
        "",
        *_table(
            ("建议角色", "数量"),
            sorted(role_counts.items(), key=lambda item: (-item[1], item[0])),
        ),
        "",
        "## BCC 分层",
        "",
        *_table(
            ("分层", "数量"),
            [
                (tier, tier_counts.get(tier, 0))
                for tier in REVIEW_TIER_ORDER
            ],
        ),
        "",
        "## 尾字分布",
        "",
        *_table(
            ("尾字", "数量"),
            sorted(suffix_counts.items(), key=lambda item: (-item[1], item[0])),
        ),
        "",
        f"## 全局优先队列（前 {summary_limit} 项）",
        "",
        *_table(
            (
                "排名",
                "字串",
                "数字标调",
                "尾字",
                "BCC 分层",
                "BCC 频次",
                "运行权重",
                "当前分类",
                "整合政策",
                "决策状态",
            ),
            top_rows,
        ),
        "",
        f"## 各尾字优先样例（每类前 {per_suffix_limit} 项）",
        "",
    ]
    for suffix_char in sorted(suffix_counts):
        suffix_rows = [
            (
                row.rank,
                row.text,
                row.pinyin_tones,
                row.bcc_frequency,
                f"{row.runtime_sort_weight:.3f}",
                row.candidate_class,
                row.integration_policy,
            )
            for row in queue
            if row.suffix_char == suffix_char
        ][:per_suffix_limit]
        lines.extend(
            [
                f"### {suffix_char}",
                "",
                *_table(
                    (
                        "全局排名",
                        "字串",
                        "数字标调",
                        "BCC 频次",
                        "运行权重",
                        "当前分类",
                        "整合政策",
                    ),
                    suffix_rows,
                ),
                "",
            ]
        )
    return lines


def export_review_queue(
    *,
    runtime_database: Path,
    input_model_database: Path,
    output_directory: Path,
    summary_limit: int = 100,
    per_suffix_limit: int = 10,
) -> ReviewExportResult:
    if summary_limit < 1:
        raise ValueError("summary_limit must be positive")
    if per_suffix_limit < 1:
        raise ValueError("per_suffix_limit must be positive")

    queue, excluded_decided_count = collect_review_queue(
        runtime_database=runtime_database,
        input_model_database=input_model_database,
    )
    output_directory.mkdir(parents=True, exist_ok=True)
    queue_path = output_directory / "review_queue.tsv"
    summary_path = output_directory / "review_summary.md"
    manifest_path = output_directory / "manifest.json"
    _write_queue(queue_path, queue)
    summary_path.write_text(
        "\n".join(
            _summary_lines(
                queue=queue,
                excluded_decided_count=excluded_decided_count,
                summary_limit=summary_limit,
                per_suffix_limit=per_suffix_limit,
            )
        ),
        encoding="utf-8",
    )

    tier_counts = dict(Counter(row.review_tier for row in queue))
    suffix_counts = dict(Counter(row.suffix_char for row in queue))
    role_counts = dict(Counter(row.suggested_role for row in queue))
    construction_system_counts: Counter[str] = Counter()
    for row in queue:
        construction_system_counts.update(
            item for item in row.construction_systems.split("; ") if item
        )
    manifest = {
        "schema_version": 1,
        "tool": "export_lexicon_quality_review",
        "created_at_utc": datetime.now(timezone.utc).isoformat(),
        "inputs": {
            "runtime_database": str(runtime_database.resolve()),
            "input_model_database": str(input_model_database.resolve()),
        },
        "outputs": {
            "queue": str(queue_path.resolve()),
            "summary": str(summary_path.resolve()),
        },
        "counts": {
            "queue": len(queue),
            "excluded_decided": excluded_decided_count,
            "tiers": tier_counts,
            "suffixes": suffix_counts,
            "suggested_roles": role_counts,
            "construction_systems": dict(construction_system_counts),
        },
        "policy": {
            "writes_assessments": False,
            "construction_policy": (
                "internal_data/particle_construction_policy.json"
            ),
            "construction_evidence_is_not_noise_decision": True,
            "frequency_tiers": list(REVIEW_TIER_ORDER),
        },
    }
    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    return ReviewExportResult(
        queue_path=queue_path,
        summary_path=summary_path,
        manifest_path=manifest_path,
        queue_count=len(queue),
        excluded_decided_count=excluded_decided_count,
        tier_counts=tier_counts,
        suffix_counts=suffix_counts,
        role_counts=role_counts,
    )
