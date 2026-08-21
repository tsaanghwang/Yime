"""Parse external_data/hanzi_pinyin.txt (Unihan merged export, tab-separated)."""

from __future__ import annotations

import csv
from dataclasses import dataclass
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_SOURCE_FILE = SCRIPT_DIR.parents[1] / "external_data" / "hanzi_pinyin.txt"

TSV_COLUMNS = (
    "codepoint",
    "hanzi",
    "common_reading",
    "readings",
    "common_reading_source",
    "is_single",
)

STAGING_DDL = """
    CREATE TABLE pinyin_source_staging (
        codepoint               TEXT PRIMARY KEY REFERENCES hanzi(codepoint) ON DELETE RESTRICT,
        hanzi                   TEXT NOT NULL,
        common_reading          TEXT,
        readings                TEXT,
        common_reading_source   TEXT,
        is_single               INTEGER NOT NULL DEFAULT 0
    )
"""

HANZI_PINYIN_DDL = """
    CREATE TABLE hanzi_pinyin (
        codepoint               TEXT PRIMARY KEY REFERENCES hanzi(codepoint) ON DELETE RESTRICT,
        hanzi                   TEXT NOT NULL,
        common_reading          TEXT NOT NULL,
        readings                TEXT NOT NULL,
        common_reading_source   TEXT,
        is_single               INTEGER NOT NULL DEFAULT 0
    )
"""


@dataclass(frozen=True)
class PinyinSourceRow:
    codepoint: str
    hanzi: str
    common_reading: str
    readings: str
    common_reading_source: str
    is_single: int

    @classmethod
    def from_tsv_fields(cls, fields: dict[str, str]) -> PinyinSourceRow | None:
        codepoint = (fields.get("codepoint") or "").strip().upper()
        if not codepoint.startswith("U+"):
            return None
        hanzi = (fields.get("hanzi") or "").strip()
        if not hanzi:
            return None
        common_reading = (fields.get("common_reading") or "").strip()
        readings = (fields.get("readings") or "").strip()
        if not readings:
            return None
        source = (fields.get("common_reading_source") or "").strip()
        raw_single = (fields.get("is_single") or "").strip()
        try:
            is_single = 1 if int(raw_single) != 0 else 0
        except ValueError:
            is_single = 0 if "," in readings else 1
        return cls(
            codepoint=codepoint,
            hanzi=hanzi,
            common_reading=common_reading,
            readings=readings,
            common_reading_source=source,
            is_single=is_single,
        )


def parse_hanzi_pinyin_txt(path: Path) -> list[PinyinSourceRow]:
    """Read TSV export from export_hanzi_pinyin_txt.py / unihan build_all."""
    if not path.exists():
        raise FileNotFoundError(f"拼音源文件未找到: {path}")

    rows: list[PinyinSourceRow] = []
    data_lines: list[str] = []
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("codepoint\t"):
            continue
        data_lines.append(line)

    for line in data_lines:
        parts = line.split("\t")
        if len(parts) < 4:
            continue
        field_map = {name: parts[i] if i < len(parts) else "" for i, name in enumerate(TSV_COLUMNS)}
        parsed = PinyinSourceRow.from_tsv_fields(field_map)
        if parsed is not None:
            rows.append(parsed)

    if rows:
        return rows

    with path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(
            (line for line in handle if line.strip() and not line.lstrip().startswith("#")),
            delimiter="\t",
        )
        for record in reader:
            if not record:
                continue
            parsed = PinyinSourceRow.from_tsv_fields(record)
            if parsed is not None:
                rows.append(parsed)
    return rows
