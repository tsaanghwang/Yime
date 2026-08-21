#!/usr/bin/env python3
"""Export a compact, commit-friendly review of the unified lexicon bundle."""

from __future__ import annotations

import argparse
import json
import sqlite3
from collections import defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_BUNDLE = ROOT / ".generated" / "lexicon_source_bundle"
DEFAULT_OUTPUT = ROOT / "internal_data" / "lexicon_source_review_summary.md"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Export high-frequency unresolved terms and reading conflicts.",
    )
    parser.add_argument("--bundle-dir", type=Path, default=DEFAULT_BUNDLE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--limit", type=int, default=100)
    return parser.parse_args()


def _source_label(raw_path: str) -> str:
    path = Path(raw_path)
    try:
        return path.resolve().relative_to(ROOT).as_posix()
    except ValueError:
        pass
    try:
        relative = path.resolve().relative_to(ROOT.parent)
        return f"../{relative.as_posix()}"
    except ValueError:
        return path.name


def _cell(value: object) -> str:
    return str(value).replace("|", "\\|").replace("\n", " ")


def _table(headers: tuple[str, ...], rows: list[tuple[object, ...]]) -> list[str]:
    lines = [
        "| " + " | ".join(headers) + " |",
        "| " + " | ".join("---" for _ in headers) + " |",
    ]
    lines.extend("| " + " | ".join(_cell(value) for value in row) + " |" for row in rows)
    return lines


def _bcc_evidence(conn: sqlite3.Connection, text: str) -> str:
    rows = conn.execute(
        """
        SELECT source_category, source_kind, frequency, source_file
        FROM bcc_frequency_evidence
        WHERE text = ?
        ORDER BY frequency DESC, source_category, source_kind, source_file
        """,
        (text,),
    )
    return "; ".join(
        f"{category}:{kind}:{_source_label(source_file)}={frequency}"
        for category, kind, frequency, source_file in rows
    )


def _rejection_evidence(conn: sqlite3.Connection, text: str) -> str:
    rows = list(
        conn.execute(
            """
            SELECT source, source_file, reading, reason
            FROM rejections
            WHERE text = ?
            ORDER BY source, source_file, reading, reason
            """,
            (text,),
        )
    )
    if not rows:
        return "无读音来源记录；no_reading_source_record"
    return "; ".join(
        f"{source}:{_source_label(source_file)}:{reading} -> {reason}"
        for source, source_file, reading, reason in rows
    )


def _accepted_readings(conn: sqlite3.Connection, text: str) -> str:
    grouped: dict[str, list[str]] = defaultdict(list)
    for marked, source, category, source_file in conn.execute(
        """
        SELECT marked, source, source_category, source_file
        FROM accepted_readings
        WHERE text = ?
        ORDER BY marked, source_rank, source, source_category, source_file
        """,
        (text,),
    ):
        evidence = f"{source}:{category}:{_source_label(source_file)}"
        if evidence not in grouped[str(marked)]:
            grouped[str(marked)].append(evidence)
    return "; ".join(
        f"{marked} [{', '.join(sources)}]" for marked, sources in grouped.items()
    )


def export_summary(bundle_dir: Path, output: Path, limit: int) -> None:
    if limit < 1:
        raise ValueError("limit must be positive")
    database = bundle_dir / "source_lexicon.sqlite3"
    manifest_path = bundle_dir / "manifest.json"
    if not database.is_file() or not manifest_path.is_file():
        raise FileNotFoundError(f"incomplete lexicon bundle: {bundle_dir}")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

    with sqlite3.connect(database) as conn:
        unresolved = list(
            conn.execute(
                """
                SELECT f.text, f.frequency
                FROM bcc_frequency AS f
                WHERE NOT EXISTS (
                    SELECT 1 FROM accepted_readings AS a WHERE a.text = f.text
                )
                ORDER BY f.frequency DESC, f.text
                LIMIT ?
                """,
                (limit,),
            )
        )
        rejected_unresolved = list(
            conn.execute(
                """
                SELECT DISTINCT f.text, f.frequency
                FROM bcc_frequency AS f
                JOIN rejections AS r USING (text)
                WHERE NOT EXISTS (
                    SELECT 1 FROM accepted_readings AS a WHERE a.text = f.text
                )
                ORDER BY f.frequency DESC, f.text
                """
            )
        )
        conflicts = list(
            conn.execute(
                """
                SELECT text, MAX(bcc_frequency) AS frequency, COUNT(*) AS reading_count
                FROM canonical_readings
                GROUP BY text
                HAVING COUNT(*) > 1
                ORDER BY frequency DESC, text
                LIMIT ?
                """,
                (limit,),
            )
        )

        unresolved_rows = [
            (
                rank,
                text,
                frequency,
                _bcc_evidence(conn, str(text)),
                _rejection_evidence(conn, str(text)),
            )
            for rank, (text, frequency) in enumerate(unresolved, start=1)
        ]
        rejected_rows = [
            (
                text,
                frequency,
                _bcc_evidence(conn, str(text)),
                _rejection_evidence(conn, str(text)),
            )
            for text, frequency in rejected_unresolved
        ]
        conflict_rows = [
            (
                rank,
                text,
                frequency,
                reading_count,
                _bcc_evidence(conn, str(text)),
                _accepted_readings(conn, str(text)),
                "multiple_gated_readings（均已准入，不是拒绝项）",
            )
            for rank, (text, frequency, reading_count) in enumerate(conflicts, start=1)
        ]

    counts = manifest["counts"]
    lines = [
        "# 高频未解码词与多读音冲突摘要",
        "",
        "本文件由 `tools/export_lexicon_review_summary.py` 从统一语料包 SQLite 机械导出。",
        "未解码词不使用逐字常用音猜测读音；读音、来源、拒绝原因和 BCC count 均来自本地上游证据。",
        "BCC 汇总频次是各分域原始 count 的最大值，表内同时列出逐分域证据。",
        "",
        f"- 语料包生成时间（UTC）：`{manifest['created_at_utc']}`",
        f"- 合规来源记录：`{counts['accepted_source_rows']}`",
        f"- 字词—读音记录：`{counts['output_text_readings']}`",
        f"- BCC 未解码字词总数：`{counts['unresolved_bcc_texts']}`",
        f"- 多读音冲突行数：`{counts['reading_conflict_rows']}`",
        f"- 下列高频表各保留前 `{limit}` 项；排序为 `bcc_frequency DESC, text ASC`。",
        "",
        f"## 高频未解码字词（前 {limit} 项）",
        "",
        *_table(("排名", "字词", "BCC 汇总频次", "BCC 来源证据", "读音门禁结果/拒绝原因"), unresolved_rows),
        "",
        "## 有读音记录但全部被拒绝的 BCC 字词（全量）",
        "",
        "这些记录单独列出，以免具体门禁原因被高频表中的大量“无读音来源记录”淹没。",
        "",
        *_table(("字词", "BCC 汇总频次", "BCC 来源证据", "被拒绝读音、来源与原因"), rejected_rows),
        "",
        f"## 高频多读音冲突（前 {limit} 项）",
        "",
        *_table(("排名", "字词", "BCC 汇总频次", "读音数", "BCC 来源证据", "合规读音与来源", "状态"), conflict_rows),
        "",
    ]
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    args = parse_args()
    export_summary(args.bundle_dir.resolve(), args.output.resolve(), args.limit)
    print(f"review_summary: {args.output.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
