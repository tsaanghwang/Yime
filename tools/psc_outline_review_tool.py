#!/usr/bin/env python3
"""Small GUI for reviewing OCR exceptions in a PSC outline SQLite database.

The tool never rewrites ``entries``, ``ocr_spans`` or the stored OCR JSON.
Manual decisions are stored separately in ``manual_corrections`` and every
change is appended to ``manual_review_history``.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import sqlite3
import sys
import unicodedata
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Sequence


REPO_ROOT = Path(__file__).resolve().parents[1]
INTERNAL_PSC_ROOT = REPO_ROOT / "internal_data" / "psc_outline"
DEFAULT_DATABASE = INTERNAL_PSC_ROOT / "psc_outline_ocr.sqlite3"


DECISION_LABELS = {
    "pending": "待处理",
    "corrected": "已修改",
    "confirmed": "确认无误",
    "unresolved": "暂无法判断",
}


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")


@dataclass
class ReviewItem:
    document_id: int
    entry_id: int
    table_number: int
    source_index: int
    page_number: int
    column_number: int
    hanzi: str
    pinyin: str
    raw_text: str
    index_origin: str
    minimum_confidence: float | None
    evidence_span_ids: list[int]
    issue_summary: str
    image_path: str
    decision: str
    corrected_hanzi: str
    corrected_pinyin: str
    review_note: str

    @property
    def key(self) -> tuple[int, int, int]:
        return self.document_id, self.table_number, self.source_index


@dataclass
class ContinuationSuggestion:
    text: str
    minimum_confidence: float
    span_ids: list[int]
    boxes: list[sqlite3.Row]


class ReviewStore:
    def __init__(self, database: Path) -> None:
        self.database = database.resolve()
        self.conn = sqlite3.connect(self.database)
        self.conn.row_factory = sqlite3.Row
        self.conn.execute("PRAGMA foreign_keys=ON")
        self.conn.execute("PRAGMA busy_timeout=5000")
        self._ensure_schema()

    def close(self) -> None:
        self.conn.close()

    def _ensure_schema(self) -> None:
        self.conn.executescript(
            """
            CREATE TABLE IF NOT EXISTS manual_corrections (
                document_id INTEGER NOT NULL,
                table_number INTEGER NOT NULL,
                source_index INTEGER NOT NULL,
                entry_id_at_review INTEGER NOT NULL,
                original_hanzi TEXT,
                original_pinyin TEXT,
                corrected_hanzi TEXT,
                corrected_pinyin TEXT,
                decision TEXT NOT NULL CHECK (
                    decision IN ('corrected', 'confirmed', 'unresolved')
                ),
                review_note TEXT,
                reviewer TEXT NOT NULL DEFAULT 'manual',
                reviewed_at_utc TEXT NOT NULL,
                PRIMARY KEY (document_id, table_number, source_index)
            );

            CREATE TABLE IF NOT EXISTS manual_review_history (
                id INTEGER PRIMARY KEY,
                document_id INTEGER NOT NULL,
                table_number INTEGER NOT NULL,
                source_index INTEGER NOT NULL,
                action TEXT NOT NULL,
                previous_json TEXT,
                current_json TEXT,
                occurred_at_utc TEXT NOT NULL
            );

            CREATE INDEX IF NOT EXISTS idx_manual_review_history_entry
                ON manual_review_history(
                    document_id, table_number, source_index, occurred_at_utc
                );

            CREATE VIEW IF NOT EXISTS manually_reviewed_entries AS
            SELECT
                e.document_id,
                e.table_number,
                e.source_index,
                e.page_number,
                e.column_number,
                e.hanzi AS ocr_hanzi,
                e.pinyin_raw AS ocr_pinyin,
                CASE
                    WHEN c.decision IN ('corrected', 'confirmed')
                    THEN c.corrected_hanzi
                    ELSE e.hanzi
                END AS reviewed_hanzi,
                CASE
                    WHEN c.decision IN ('corrected', 'confirmed')
                    THEN c.corrected_pinyin
                    ELSE e.pinyin_raw
                END AS reviewed_pinyin,
                COALESCE(c.decision, 'pending') AS review_decision,
                c.review_note,
                c.reviewed_at_utc
            FROM entries AS e
            LEFT JOIN manual_corrections AS c
              ON c.document_id = e.document_id
             AND c.table_number = e.table_number
             AND c.source_index = e.source_index;
            """
        )
        self.conn.commit()

    def load_items(self) -> list[ReviewItem]:
        rows = self.conn.execute(
            """
            SELECT
                e.document_id,
                e.id AS entry_id,
                e.table_number,
                e.source_index,
                e.page_number,
                e.column_number,
                COALESCE(e.hanzi, '') AS hanzi,
                COALESCE(e.pinyin_raw, '') AS pinyin,
                e.raw_text,
                e.index_origin,
                e.minimum_confidence,
                e.evidence_span_ids_json,
                p.image_path,
                COALESCE(c.decision, 'pending') AS decision,
                COALESCE(c.corrected_hanzi, e.hanzi, '') AS corrected_hanzi,
                COALESCE(c.corrected_pinyin, e.pinyin_raw, '') AS corrected_pinyin,
                COALESCE(c.review_note, '') AS review_note,
                COALESCE((
                    SELECT group_concat(i.code || '：' || i.message, char(10))
                      FROM issues AS i
                     WHERE i.document_id = e.document_id
                       AND i.page_number = e.page_number
                       AND i.table_number = e.table_number
                       AND i.source_index = e.source_index
                ), '') AS issue_summary
            FROM entries AS e
            JOIN pages AS p
              ON p.document_id = e.document_id
             AND p.page_number = e.page_number
            LEFT JOIN manual_corrections AS c
              ON c.document_id = e.document_id
             AND c.table_number = e.table_number
             AND c.source_index = e.source_index
            WHERE e.status = 'needs_review'
            ORDER BY e.table_number, e.source_index
            """
        ).fetchall()
        return [
            ReviewItem(
                document_id=int(row["document_id"]),
                entry_id=int(row["entry_id"]),
                table_number=int(row["table_number"]),
                source_index=int(row["source_index"]),
                page_number=int(row["page_number"]),
                column_number=int(row["column_number"]),
                hanzi=str(row["hanzi"]),
                pinyin=str(row["pinyin"]),
                raw_text=str(row["raw_text"]),
                index_origin=str(row["index_origin"]),
                minimum_confidence=(
                    float(row["minimum_confidence"])
                    if row["minimum_confidence"] is not None
                    else None
                ),
                evidence_span_ids=json.loads(row["evidence_span_ids_json"]),
                issue_summary=str(row["issue_summary"]),
                image_path=str(row["image_path"] or ""),
                decision=str(row["decision"]),
                corrected_hanzi=str(row["corrected_hanzi"]),
                corrected_pinyin=str(row["corrected_pinyin"]),
                review_note=str(row["review_note"]),
            )
            for row in rows
        ]

    def evidence_boxes(self, item: ReviewItem) -> list[sqlite3.Row]:
        if not item.evidence_span_ids:
            return []
        placeholders = ",".join("?" for _ in item.evidence_span_ids)
        return self.conn.execute(
            f"""
            SELECT id, text, confidence, x1, y1, x2, y2
              FROM ocr_spans
             WHERE id IN ({placeholders})
             ORDER BY span_order
            """,
            item.evidence_span_ids,
        ).fetchall()

    @staticmethod
    def _looks_like_pinyin_only(text: str) -> bool:
        if any("\u3400" <= character <= "\u9fff" for character in text):
            return False
        if any(character.isdigit() for character in text):
            return False
        return any(
            "a" <= character.lower() <= "z"
            or unicodedata.category(character).startswith("M")
            for character in text
        )

    def continuation_suggestion(
        self, item: ReviewItem, evidence_boxes: Sequence[sqlite3.Row]
    ) -> ContinuationSuggestion | None:
        """Find an unassigned pinyin-only OCR line immediately below an entry."""
        if item.pinyin or not evidence_boxes:
            return None
        evidence_bottom = max(float(row["y2"]) for row in evidence_boxes)
        candidates = self.conn.execute(
            """
            SELECT s.id, s.text, s.confidence, s.x1, s.y1, s.x2, s.y2
              FROM ocr_spans AS s
             WHERE s.document_id=?
               AND s.page_number=?
               AND s.column_number=?
               AND s.y1>=?
               AND s.y1<=?
               AND NOT EXISTS (
                    SELECT 1
                      FROM entries AS assigned_entry,
                           json_each(assigned_entry.evidence_span_ids_json) AS evidence
                     WHERE assigned_entry.document_id=s.document_id
                       AND assigned_entry.page_number=s.page_number
                       AND CAST(evidence.value AS INTEGER)=s.id
               )
             ORDER BY s.y1, s.x1
            """,
            (
                item.document_id,
                item.page_number,
                item.column_number,
                evidence_bottom + 5.0,
                evidence_bottom + 18.0,
            ),
        ).fetchall()
        candidates = [
            row for row in candidates if self._looks_like_pinyin_only(str(row["text"]).strip())
        ]
        if not candidates:
            return None

        # A wrapped recognition can itself be split into adjacent OCR spans.
        # Preserve visible spacing when boxes are clearly separated.
        fragments: list[str] = []
        previous_right: float | None = None
        for row in candidates:
            text = str(row["text"]).strip()
            if previous_right is not None and float(row["x1"]) - previous_right > 8.0:
                fragments.append(" ")
            fragments.append(text)
            previous_right = float(row["x2"])
        return ContinuationSuggestion(
            text="".join(fragments),
            minimum_confidence=min(float(row["confidence"]) for row in candidates),
            span_ids=[int(row["id"]) for row in candidates],
            boxes=candidates,
        )

    def save(
        self,
        item: ReviewItem,
        decision: str,
        corrected_hanzi: str,
        corrected_pinyin: str,
        note: str,
    ) -> None:
        if decision not in {"corrected", "confirmed", "unresolved"}:
            raise ValueError(f"unsupported decision: {decision}")
        previous = self.conn.execute(
            """
            SELECT * FROM manual_corrections
             WHERE document_id=? AND table_number=? AND source_index=?
            """,
            item.key,
        ).fetchone()
        current = {
            "entry_id_at_review": item.entry_id,
            "original_hanzi": item.hanzi,
            "original_pinyin": item.pinyin,
            "corrected_hanzi": corrected_hanzi,
            "corrected_pinyin": corrected_pinyin,
            "decision": decision,
            "review_note": note,
            "reviewer": "manual",
            "reviewed_at_utc": utc_now(),
        }
        previous_json = json.dumps(dict(previous), ensure_ascii=False) if previous else None
        with self.conn:
            self.conn.execute(
                """
                INSERT INTO manual_corrections(
                    document_id, table_number, source_index, entry_id_at_review,
                    original_hanzi, original_pinyin, corrected_hanzi,
                    corrected_pinyin, decision, review_note, reviewer,
                    reviewed_at_utc
                ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)
                ON CONFLICT(document_id, table_number, source_index) DO UPDATE SET
                    entry_id_at_review=excluded.entry_id_at_review,
                    original_hanzi=excluded.original_hanzi,
                    original_pinyin=excluded.original_pinyin,
                    corrected_hanzi=excluded.corrected_hanzi,
                    corrected_pinyin=excluded.corrected_pinyin,
                    decision=excluded.decision,
                    review_note=excluded.review_note,
                    reviewer=excluded.reviewer,
                    reviewed_at_utc=excluded.reviewed_at_utc
                """,
                (
                    item.document_id,
                    item.table_number,
                    item.source_index,
                    current["entry_id_at_review"],
                    current["original_hanzi"],
                    current["original_pinyin"],
                    current["corrected_hanzi"],
                    current["corrected_pinyin"],
                    current["decision"],
                    current["review_note"],
                    current["reviewer"],
                    current["reviewed_at_utc"],
                ),
            )
            self.conn.execute(
                """
                INSERT INTO manual_review_history(
                    document_id, table_number, source_index, action,
                    previous_json, current_json, occurred_at_utc
                ) VALUES(?,?,?,?,?,?,?)
                """,
                (
                    item.document_id,
                    item.table_number,
                    item.source_index,
                    "save",
                    previous_json,
                    json.dumps(current, ensure_ascii=False),
                    utc_now(),
                ),
            )

    def clear(self, item: ReviewItem) -> None:
        previous = self.conn.execute(
            """
            SELECT * FROM manual_corrections
             WHERE document_id=? AND table_number=? AND source_index=?
            """,
            item.key,
        ).fetchone()
        if not previous:
            return
        with self.conn:
            self.conn.execute(
                """
                DELETE FROM manual_corrections
                 WHERE document_id=? AND table_number=? AND source_index=?
                """,
                item.key,
            )
            self.conn.execute(
                """
                INSERT INTO manual_review_history(
                    document_id, table_number, source_index, action,
                    previous_json, current_json, occurred_at_utc
                ) VALUES(?,?,?,?,?,NULL,?)
                """,
                (
                    item.document_id,
                    item.table_number,
                    item.source_index,
                    "clear",
                    json.dumps(dict(previous), ensure_ascii=False),
                    utc_now(),
                ),
            )

    def stats(self) -> dict[str, int]:
        result = {key: 0 for key in DECISION_LABELS}
        result["pending"] = int(
            self.conn.execute(
                """
                SELECT COUNT(*)
                  FROM entries AS e
                  LEFT JOIN manual_corrections AS c
                    ON c.document_id=e.document_id
                   AND c.table_number=e.table_number
                   AND c.source_index=e.source_index
                 WHERE e.status='needs_review' AND c.decision IS NULL
                """
            ).fetchone()[0]
        )
        for row in self.conn.execute(
            "SELECT decision, COUNT(*) AS count FROM manual_corrections GROUP BY decision"
        ):
            result[str(row["decision"])] = int(row["count"])
        return result


def resolve_image_path(item: ReviewItem, database: Path, image_dir: Path | None) -> Path:
    candidates: list[Path] = []
    if image_dir:
        candidates.append(image_dir / f"page-{item.page_number:04d}.png")
    if item.image_path:
        stored_path = Path(item.image_path)
        if not stored_path.is_absolute():
            candidates.append(database.parent / stored_path)
    candidates.append(database.parent / "pages" / f"page-{item.page_number:04d}.png")
    for candidate in candidates:
        if candidate.is_file():
            return candidate.resolve()
    return candidates[0] if candidates else Path(item.image_path)


def create_review_crop(
    image_path: Path,
    column_number: int,
    evidence_boxes: Sequence[sqlite3.Row],
    continuation_boxes: Sequence[sqlite3.Row] = (),
    maximum_size: tuple[int, int] = (1000, 300),
) -> Any:
    from PIL import Image, ImageDraw

    image = Image.open(image_path).convert("RGBA")
    width, height = image.size
    all_boxes = list(evidence_boxes) + list(continuation_boxes)
    if all_boxes:
        y1 = min(float(row["y1"]) for row in all_boxes)
        y2 = max(float(row["y2"]) for row in all_boxes)
        center_y = (y1 + y2) / 2.0
    else:
        center_y = height / 2.0
    column_width = width / 3.0
    crop_left = max(0, int((column_number - 1) * column_width - 30))
    crop_right = min(width, int(column_number * column_width + 30))
    crop_top = max(0, int(center_y - 100))
    crop_bottom = min(height, int(center_y + 100))

    overlay = Image.new("RGBA", image.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    draw.rectangle(
        (crop_left, max(0, int(center_y - 28)), crop_right, min(height, int(center_y + 28))),
        fill=(255, 230, 80, 45),
        outline=(230, 170, 0, 180),
        width=2,
    )
    for row in evidence_boxes:
        draw.rectangle(
            (float(row["x1"]), float(row["y1"]), float(row["x2"]), float(row["y2"])),
            outline=(220, 35, 35, 255),
            width=3,
        )
    for row in continuation_boxes:
        draw.rectangle(
            (float(row["x1"]), float(row["y1"]), float(row["x2"]), float(row["y2"])),
            outline=(25, 105, 210, 255),
            width=3,
        )
    marked = Image.alpha_composite(image, overlay).crop(
        (crop_left, crop_top, crop_right, crop_bottom)
    ).convert("RGB")
    scale = min(maximum_size[0] / marked.width, maximum_size[1] / marked.height, 2.5)
    target = (max(1, round(marked.width * scale)), max(1, round(marked.height * scale)))
    return marked.resize(target, Image.Resampling.LANCZOS)


class ReviewApplication:
    def __init__(self, store: ReviewStore, image_dir: Path | None) -> None:
        import tkinter as tk
        from tkinter import ttk

        self.tk = tk
        self.ttk = ttk
        self.store = store
        self.database = store.database
        self.image_dir = image_dir.resolve() if image_dir else None
        self.all_items = store.load_items()
        self.items: list[ReviewItem] = []
        self.position = 0
        self.current_photo = None
        self.current_image_path: Path | None = None
        self.current_suggestion: ContinuationSuggestion | None = None

        self.root = tk.Tk()
        self.root.title("普通话纲要 OCR 校对")
        self.root.geometry("1120x760")
        self.root.minsize(900, 650)
        self.root.option_add("*Font", ("Microsoft YaHei UI", 11))
        self.root.protocol("WM_DELETE_WINDOW", self.close)

        style = ttk.Style(self.root)
        if "vista" in style.theme_names():
            style.theme_use("vista")
        style.configure("Title.TLabel", font=("Microsoft YaHei UI", 16, "bold"))
        style.configure("Value.TEntry", font=("Microsoft YaHei UI", 16))

        self.filter_var = tk.StringVar(value="待处理")
        self.location_var = tk.StringVar()
        self.progress_var = tk.StringVar()
        self.metadata_var = tk.StringVar()
        self.hanzi_var = tk.StringVar()
        self.pinyin_var = tk.StringVar()
        self.search_var = tk.StringVar()
        self.suggestion_var = tk.StringVar()

        self._build_ui()
        self._bind_keys()
        self.apply_filter(select_key=None)

    def _build_ui(self) -> None:
        tk, ttk = self.tk, self.ttk
        top = ttk.Frame(self.root, padding=(12, 10))
        top.pack(fill="x")
        ttk.Label(top, text="普通话纲要 OCR 校对", style="Title.TLabel").pack(side="left")
        ttk.Label(top, textvariable=self.progress_var).pack(side="right")

        controls = ttk.Frame(self.root, padding=(12, 0, 12, 8))
        controls.pack(fill="x")
        ttk.Label(controls, text="显示：").pack(side="left")
        filter_box = ttk.Combobox(
            controls,
            textvariable=self.filter_var,
            values=("待处理", "全部", "已修改", "确认无误", "暂无法判断"),
            state="readonly",
            width=12,
        )
        filter_box.pack(side="left")
        filter_box.bind("<<ComboboxSelected>>", lambda _event: self.apply_filter(None))
        ttk.Label(controls, text="跳转（如 1-248）：").pack(side="left", padx=(20, 4))
        search_entry = ttk.Entry(controls, textvariable=self.search_var, width=14)
        search_entry.pack(side="left")
        search_entry.bind("<Return>", lambda _event: self.jump_to())
        ttk.Button(controls, text="跳转", command=self.jump_to).pack(side="left", padx=4)
        ttk.Button(controls, text="打开整页", command=self.open_full_page).pack(side="right")

        location = ttk.Frame(self.root, padding=(12, 2, 12, 8))
        location.pack(fill="x")
        ttk.Label(location, textvariable=self.location_var, style="Title.TLabel").pack(side="left")
        ttk.Label(location, textvariable=self.metadata_var).pack(side="right")

        self.suggestion_label = tk.Label(
            self.root,
            textvariable=self.suggestion_var,
            anchor="w",
            fg="#005a9c",
            font=("Microsoft YaHei UI", 11, "bold"),
            padx=12,
            pady=2,
        )
        self.suggestion_label.pack(fill="x")

        image_frame = ttk.LabelFrame(
            self.root,
            text="原始 PNG 局部（黄色为所在行，红框为原证据，蓝框为检测到的换行拼音）",
            padding=8,
        )
        image_frame.pack(fill="both", expand=True, padx=12, pady=(0, 8))
        self.image_label = ttk.Label(image_frame, anchor="center")
        self.image_label.pack(fill="both", expand=True)

        form = ttk.Frame(self.root, padding=(12, 0, 12, 6))
        form.pack(fill="x")
        ttk.Label(form, text="汉字：", width=8).grid(row=0, column=0, sticky="w", pady=4)
        self.hanzi_entry = ttk.Entry(form, textvariable=self.hanzi_var, style="Value.TEntry")
        self.hanzi_entry.grid(row=0, column=1, sticky="ew", pady=4)
        ttk.Label(form, text="拼音：", width=8).grid(row=1, column=0, sticky="w", pady=4)
        self.pinyin_entry = ttk.Entry(form, textvariable=self.pinyin_var, style="Value.TEntry")
        self.pinyin_entry.grid(row=1, column=1, sticky="ew", pady=4)
        ttk.Label(form, text="问题：", width=8).grid(row=2, column=0, sticky="nw", pady=4)
        self.issue_text = tk.Text(form, height=3, wrap="word", font=("Microsoft YaHei UI", 10))
        self.issue_text.grid(row=2, column=1, sticky="ew", pady=4)
        ttk.Label(form, text="备注：", width=8).grid(row=3, column=0, sticky="nw", pady=4)
        self.note_text = tk.Text(form, height=2, wrap="word", font=("Microsoft YaHei UI", 10))
        self.note_text.grid(row=3, column=1, sticky="ew", pady=4)
        form.columnconfigure(1, weight=1)

        buttons = ttk.Frame(self.root, padding=(12, 4, 12, 12))
        buttons.pack(fill="x")
        ttk.Button(buttons, text="◀ 上一条", command=self.previous).pack(side="left")
        ttk.Button(buttons, text="下一条 ▶", command=self.next).pack(side="left", padx=6)
        ttk.Button(buttons, text="撤销本条校对", command=self.clear_current).pack(side="left", padx=(14, 0))
        ttk.Button(buttons, text="暂无法判断", command=self.mark_unresolved).pack(side="right")
        ttk.Button(buttons, text="确认无误并下一条", command=self.confirm_and_next).pack(side="right", padx=6)
        ttk.Button(buttons, text="保存修改并下一条", command=self.save_and_next).pack(side="right")

    def _bind_keys(self) -> None:
        self.root.bind("<F7>", lambda _event: self.previous())
        self.root.bind("<F8>", lambda _event: self.next())
        self.root.bind("<Control-Return>", lambda _event: self.save_and_next())
        self.root.bind("<Control-Shift-Return>", lambda _event: self.confirm_and_next())

    def decision_for_filter(self) -> str | None:
        mapping = {
            "待处理": "pending",
            "全部": None,
            "已修改": "corrected",
            "确认无误": "confirmed",
            "暂无法判断": "unresolved",
        }
        return mapping[self.filter_var.get()]

    def apply_filter(self, select_key: tuple[int, int, int] | None) -> None:
        self.all_items = self.store.load_items()
        decision = self.decision_for_filter()
        self.items = [item for item in self.all_items if decision is None or item.decision == decision]
        self.position = 0
        if select_key:
            for index, item in enumerate(self.items):
                if item.key == select_key:
                    self.position = index
                    break
        self.show_current()

    def current(self) -> ReviewItem | None:
        if not self.items:
            return None
        return self.items[self.position]

    def show_current(self) -> None:
        item = self.current()
        stats = self.store.stats()
        self.progress_var.set(
            f"待处理 {stats['pending']} / 已修改 {stats['corrected']} / "
            f"确认 {stats['confirmed']} / 未决 {stats['unresolved']}"
        )
        if not item:
            self.location_var.set("当前筛选条件下没有记录")
            self.metadata_var.set("")
            self.hanzi_var.set("")
            self.pinyin_var.set("")
            self.suggestion_var.set("")
            self.current_suggestion = None
            self.image_label.configure(image="", text="没有待显示的记录")
            return

        self.location_var.set(
            f"表{item.table_number} · 第 {item.source_index} 条 · "
            f"PDF 第 {item.page_number} 页 · 第 {item.column_number} 栏"
        )
        confidence = "—" if item.minimum_confidence is None else f"{item.minimum_confidence:.3f}"
        self.metadata_var.set(
            f"{self.position + 1}/{len(self.items)}　"
            f"状态：{DECISION_LABELS[item.decision]}　最低置信度：{confidence}"
        )
        evidence_boxes = self.store.evidence_boxes(item)
        self.current_suggestion = self.store.continuation_suggestion(item, evidence_boxes)
        self.hanzi_var.set(item.corrected_hanzi)
        suggested_pinyin = (
            self.current_suggestion.text
            if self.current_suggestion and not item.corrected_pinyin and item.decision == "pending"
            else item.corrected_pinyin
        )
        self.pinyin_var.set(suggested_pinyin)
        if self.current_suggestion:
            self.suggestion_var.set(
                "检测到换行拼音，已预填："
                f"{self.current_suggestion.text}　"
                f"（最低置信度 {self.current_suggestion.minimum_confidence:.3f}，蓝框）"
            )
        else:
            self.suggestion_var.set("")
        self.note_text.delete("1.0", "end")
        self.note_text.insert("1.0", item.review_note)
        self.issue_text.configure(state="normal")
        self.issue_text.delete("1.0", "end")
        self.issue_text.insert(
            "1.0",
            f"OCR 原文：{item.raw_text or '（空）'}\n{item.issue_summary}",
        )
        self.issue_text.configure(state="disabled")
        self._show_image(item, evidence_boxes)
        self.hanzi_entry.focus_set()
        self.hanzi_entry.selection_range(0, "end")

    def _show_image(
        self, item: ReviewItem, evidence_boxes: Sequence[sqlite3.Row] | None = None
    ) -> None:
        from PIL import ImageTk

        path = resolve_image_path(item, self.database, self.image_dir)
        self.current_image_path = path
        if not path.is_file():
            self.current_photo = None
            self.image_label.configure(
                image="", text=f"找不到第 {item.page_number} 页 PNG：\n{path}"
            )
            return
        try:
            crop = create_review_crop(
                path,
                item.column_number,
                evidence_boxes if evidence_boxes is not None else self.store.evidence_boxes(item),
                self.current_suggestion.boxes if self.current_suggestion else (),
            )
            self.current_photo = ImageTk.PhotoImage(crop)
            self.image_label.configure(image=self.current_photo, text="")
        except Exception as error:
            self.current_photo = None
            self.image_label.configure(image="", text=f"图片加载失败：{error}")

    def _values(self) -> tuple[str, str, str]:
        hanzi = self.hanzi_var.get().strip()
        pinyin = self.pinyin_var.get().strip()
        note = self.note_text.get("1.0", "end").strip()
        if (
            self.current_suggestion
            and pinyin == self.current_suggestion.text
            and not note
        ):
            note = (
                "采用工具检测的换行拼音；OCR span_ids="
                + ",".join(str(value) for value in self.current_suggestion.span_ids)
            )
        return hanzi, pinyin, note

    def _save_decision(self, decision: str) -> bool:
        from tkinter import messagebox

        item = self.current()
        if not item:
            return False
        hanzi, pinyin, note = self._values()
        if decision in {"corrected", "confirmed"} and (not hanzi or not pinyin):
            messagebox.showwarning("内容未完整", "汉字和拼音都填写后才能保存或确认。")
            return False
        if decision == "confirmed" and (hanzi != item.hanzi or pinyin != item.pinyin):
            messagebox.showinfo(
                "内容已有变化",
                "当前内容与 OCR 原值不同；请使用“保存修改并下一条”。",
            )
            return False
        if decision == "corrected" and hanzi == item.hanzi and pinyin == item.pinyin:
            messagebox.showinfo("没有修改", "内容与 OCR 原值相同；如原值正确，请使用“确认无误”。")
            return False
        self.store.save(item, decision, hanzi, pinyin, note)
        return True

    def save_and_next(self) -> None:
        if self._save_decision("corrected"):
            self._after_save()

    def confirm_and_next(self) -> None:
        if self._save_decision("confirmed"):
            self._after_save()

    def mark_unresolved(self) -> None:
        if self._save_decision("unresolved"):
            self._after_save()

    def _after_save(self) -> None:
        current_position = self.position
        self.all_items = self.store.load_items()
        decision = self.decision_for_filter()
        self.items = [item for item in self.all_items if decision is None or item.decision == decision]
        if self.items:
            self.position = min(current_position, len(self.items) - 1)
        else:
            self.position = 0
        self.show_current()

    def clear_current(self) -> None:
        from tkinter import messagebox

        item = self.current()
        if not item or item.decision == "pending":
            return
        if not messagebox.askyesno("撤销校对", "撤销本条人工校对，使其重新进入待处理队列？"):
            return
        self.store.clear(item)
        self.apply_filter(select_key=item.key)

    def previous(self) -> None:
        if self.items:
            self.position = (self.position - 1) % len(self.items)
            self.show_current()

    def next(self) -> None:
        if self.items:
            self.position = (self.position + 1) % len(self.items)
            self.show_current()

    def jump_to(self) -> None:
        from tkinter import messagebox

        value = self.search_var.get().strip().replace("：", "-").replace(":", "-")
        try:
            table_text, index_text = value.split("-", 1)
            table_number, source_index = int(table_text), int(index_text)
        except ValueError:
            messagebox.showwarning("格式不正确", "请输入“表号-序号”，例如：1-248。")
            return
        self.filter_var.set("全部")
        self.apply_filter(None)
        for position, item in enumerate(self.items):
            if item.table_number == table_number and item.source_index == source_index:
                self.position = position
                self.show_current()
                return
        messagebox.showinfo("未找到", "这个编号不在待复核条目中。")

    def open_full_page(self) -> None:
        from tkinter import messagebox

        if not self.current_image_path or not self.current_image_path.is_file():
            messagebox.showwarning("找不到图片", "当前记录没有可用的 PNG 页面。")
            return
        os.startfile(self.current_image_path)  # type: ignore[attr-defined]

    def close(self) -> None:
        self.store.close()
        self.root.destroy()

    def run(self) -> None:
        self.root.mainloop()


def run_self_test(database: Path, image_dir: Path | None) -> int:
    store = ReviewStore(database)
    try:
        items = store.load_items()
        if not items:
            raise RuntimeError("database contains no entries needing review")
        item = items[0]
        evidence_boxes = store.evidence_boxes(item)
        suggestion = store.continuation_suggestion(item, evidence_boxes)
        for candidate in items:
            if candidate.decision != "pending":
                continue
            candidate_boxes = store.evidence_boxes(candidate)
            candidate_suggestion = store.continuation_suggestion(candidate, candidate_boxes)
            if candidate_suggestion:
                item = candidate
                evidence_boxes = candidate_boxes
                suggestion = candidate_suggestion
                break
        if not suggestion:
            raise RuntimeError("database contains no detectable wrapped-pinyin example")
        before_entries = store.conn.execute("SELECT COUNT(*) FROM entries").fetchone()[0]
        original = (item.hanzi, item.pinyin)
        test_hanzi = item.hanzi or "挨"
        test_pinyin = suggestion.text
        store.save(item, "corrected", test_hanzi, test_pinyin, "automated self-test")
        saved = store.conn.execute(
            """
            SELECT decision, corrected_hanzi, corrected_pinyin
              FROM manual_corrections
             WHERE document_id=? AND table_number=? AND source_index=?
            """,
            item.key,
        ).fetchone()
        assert saved and saved["decision"] == "corrected"
        assert (saved["corrected_hanzi"], saved["corrected_pinyin"]) == (
            test_hanzi,
            test_pinyin,
        )
        assert store.conn.execute("SELECT COUNT(*) FROM entries").fetchone()[0] == before_entries
        path = resolve_image_path(item, database, image_dir)
        crop = create_review_crop(
            path,
            item.column_number,
            evidence_boxes,
            suggestion.boxes if suggestion else (),
        )
        assert crop.width > 0 and crop.height > 0
        store.clear(item)
        assert (
            store.conn.execute(
                """
                SELECT COUNT(*) FROM manual_corrections
                 WHERE document_id=? AND table_number=? AND source_index=?
                """,
                item.key,
            ).fetchone()[0]
            == 0
        )
        print(
            json.dumps(
                {
                    "database": str(database.resolve()),
                    "queue_entries": len(items),
                    "tested_entry": f"{item.table_number}-{item.source_index}",
                    "original": original,
                    "image": str(path),
                    "crop_size": crop.size,
                    "continuation_suggestion": suggestion.text if suggestion else None,
                    "entries_unchanged": True,
                    "result": "ok",
                },
                ensure_ascii=False,
                indent=2,
            )
        )
        return 0
    finally:
        store.close()


def build_argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "database",
        nargs="?",
        type=Path,
        default=DEFAULT_DATABASE,
    )
    parser.add_argument("--image-dir", type=Path)
    parser.add_argument("--self-test", action="store_true")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_argument_parser().parse_args(argv)
    database = args.database.resolve()
    if not database.is_file():
        print(f"database not found: {database}", file=sys.stderr)
        return 2
    image_dir = args.image_dir.resolve() if args.image_dir else None
    if args.self_test:
        return run_self_test(database, image_dir)
    store = ReviewStore(database)
    application = ReviewApplication(store, image_dir)
    application.run()
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except SystemExit:
        raise
    except Exception as error:
        try:
            import tkinter as tk
            from tkinter import messagebox

            root = tk.Tk()
            root.withdraw()
            messagebox.showerror("校对工具无法启动", f"{type(error).__name__}: {error}")
            root.destroy()
        finally:
            raise
