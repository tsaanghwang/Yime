"""Build and review pronunciation-coverage additions from orthoepy lists.

The workflow deliberately answers one narrow input-method question: does the
canonical source lexicon already contain a source-attested ``text + reading``
pair?  It never deletes readings, changes primary ranking, or interprets the
2016 consultation draft as an official replacement for the 1985 list.
"""

from __future__ import annotations

import hashlib
import json
import re
import sqlite3
import unicodedata
from dataclasses import dataclass, replace
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable, Iterator, Sequence

from yime.utils.marked_pinyin import (
    marked_pinyin_to_numeric,
    marked_syllable_to_numeric,
)

from .gate import ReadingGate
from .psc_audit import normalize_marked_pinyin


DATASET_KEY = "putonghua-orthoepy-1985-with-2016-draft"
VALID_DECISIONS = frozenset({"approve", "corrected_approve", "defer", "reject"})
_CJK_CLASS = r"\u3400-\u9fff\uf900-\ufaff\U00020000-\U000323af〇"
_LEXEME_RE = re.compile(rf"[{_CJK_CLASS}～]+")
_NUMBERED_RE = re.compile(r"[（(][一二三四五六七八九十]+[）)]")
_PINYIN_RE = re.compile(
    r"[A-Za-züÜêÊāáǎàēéěèīíǐìōóǒòūúǔùǖǘǚǜńňǹḿ]+"
)
_PINYIN_VOWELS = frozenset("aeiouüêāáǎàēéěèīíǐìōóǒòūúǔùǖǘǚǜ")


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(8 * 1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def _snapshot(path: Path) -> dict[str, object]:
    resolved = path.resolve(strict=True)
    stat = resolved.stat()
    return {
        "path": str(resolved),
        "size": stat.st_size,
        "mtime_ns": stat.st_mtime_ns,
        "sha256": _sha256(resolved),
    }


def _assert_unchanged(snapshot: dict[str, object]) -> None:
    path = Path(str(snapshot["path"]))
    current = _snapshot(path)
    for key in ("size", "mtime_ns", "sha256"):
        if current[key] != snapshot[key]:
            raise RuntimeError(f"input changed during orthoepy audit: {path}")


def _connect_read_only(path: Path) -> sqlite3.Connection:
    connection = sqlite3.connect(f"file:{path.resolve().as_posix()}?mode=ro", uri=True)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA query_only = ON")
    connection.execute("PRAGMA busy_timeout = 5000")
    return connection


def _normalize_text(value: object) -> str:
    text = unicodedata.normalize("NFC", str(value or ""))
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    return "\n".join(line.strip() for line in text.splitlines()).strip()


def _first_pinyin(text: str) -> tuple[str, int, int] | None:
    for match in _PINYIN_RE.finditer(unicodedata.normalize("NFC", text)):
        token = match.group(0).lower().replace("u:", "ü").replace("v", "ü")
        if any(character in _PINYIN_VOWELS for character in token):
            return token, match.start(), match.end()
    return None


def _reading_sections(entry_text: str, headword: str) -> tuple[tuple[str, str], ...]:
    """Return ``(headword reading, following evidence segment)`` pairs.

    Numbered groups are the structural boundary in the official list.  Only the
    first Pinyin token in each group is a headword reading; parenthetical Pinyin
    later in examples (for example ``伯伯（bo）``) is not promoted accidentally.
    """

    text = _normalize_text(entry_text)
    markers = tuple(_NUMBERED_RE.finditer(text))
    chunks: list[str]
    if markers:
        chunks = []
        for index, marker in enumerate(markers):
            end = markers[index + 1].start() if index + 1 < len(markers) else len(text)
            chunks.append(text[marker.end() : end])
    else:
        start = text.find(headword)
        chunks = [text[start + len(headword) :] if start >= 0 else text]

    result: list[tuple[str, str]] = []
    for chunk in chunks:
        pinyin = _first_pinyin(chunk)
        if pinyin is None:
            continue
        reading, _, end = pinyin
        pair = (reading, chunk[end:])
        if pair not in result:
            result.append(pair)
    return tuple(result)


@dataclass(frozen=True)
class CandidateSeed:
    version_key: str
    authority_status: str
    source_row: int
    word_page_number: int
    section_label: str
    candidate_kind: str
    text: str
    target_reading: str
    target_indexes: tuple[int, ...]
    source_entry_text: str
    extraction_note: str = ""


def extract_entry_seeds(row: sqlite3.Row) -> tuple[CandidateSeed, ...]:
    headword = str(row["headword"] or "").strip()
    if len(headword) != 1:
        return ()
    base = {
        "version_key": str(row["version_key"]),
        "authority_status": str(row["authority_status"]),
        "source_row": int(row["source_row"]),
        "word_page_number": int(row["word_page_number"]),
        "section_label": str(row["section_label"]),
        "source_entry_text": str(row["entry_text"]),
    }
    result: list[CandidateSeed] = []
    for reading, evidence_segment in _reading_sections(str(row["entry_text"]), headword):
        direct = CandidateSeed(
            **base,
            candidate_kind="single_char",
            text=headword,
            target_reading=reading,
            target_indexes=(0,),
        )
        if direct not in result:
            result.append(direct)
        for match in _LEXEME_RE.finditer(evidence_segment):
            token = match.group(0)
            if "～" not in token or len(token) < 2:
                continue
            indexes = tuple(index for index, character in enumerate(token) if character == "～")
            expanded = token.replace("～", headword)
            phrase = CandidateSeed(
                **base,
                candidate_kind="example_phrase",
                text=expanded,
                target_reading=reading,
                target_indexes=indexes,
                extraction_note=(
                    "multiple_headword_placeholders" if len(indexes) != 1 else ""
                ),
            )
            if phrase not in result:
                result.append(phrase)
    return tuple(result)


@dataclass(frozen=True)
class SourceReading:
    marked: str
    numeric: str
    is_primary: bool
    reading_rank: int

    @property
    def marked_syllables(self) -> tuple[str, ...]:
        return tuple(self.marked.split())

    @property
    def numeric_syllables(self) -> tuple[str, ...]:
        return tuple(self.numeric.split())


def restore_missing_syllable_spaces(
    reading: str,
    expected_count: int,
    decoder_inventory: Path,
) -> str | None:
    """Return the unique inventory-backed syllable split, if one exists."""
    normalized = unicodedata.normalize("NFC", reading.strip())
    if len(normalized.split()) == expected_count:
        return " ".join(normalized.split())
    compact = re.sub(r"[\s·'’\-]+", "", normalized)
    if not compact or expected_count <= 0:
        return None
    if any(
        character == "r" and index > 0 and compact[index - 1] in _PINYIN_VOWELS
        for index, character in enumerate(compact)
    ):
        # An attached orthographic erhua r is not an independent syllable.
        # Splitting e.g. juér as "ju ér" would move the tone mark and invent
        # a different reading, so leave it for the separate erhua policy.
        return None
    inventory = json.loads(decoder_inventory.read_text(encoding="utf-8"))
    tokens = tuple(
        sorted(
            {
                unicodedata.normalize("NFC", str(marked))
                for marked in inventory.values()
                if str(marked)
            },
            key=lambda token: (-len(token), token),
        )
    )
    memo: dict[tuple[int, int], tuple[tuple[str, ...], ...]] = {}

    def visit(offset: int, remaining: int) -> tuple[tuple[str, ...], ...]:
        key = (offset, remaining)
        if key in memo:
            return memo[key]
        if remaining == 0:
            return ((),) if offset == len(compact) else ()
        if offset >= len(compact):
            return ()
        paths: list[tuple[str, ...]] = []
        for token in tokens:
            if not compact.startswith(token, offset):
                continue
            for suffix in visit(offset + len(token), remaining - 1):
                paths.append((token, *suffix))
                if len(paths) > 1:
                    memo[key] = tuple(paths)
                    return memo[key]
        memo[key] = tuple(paths)
        return memo[key]

    parses = visit(0, expected_count)
    return " ".join(parses[0]) if len(parses) == 1 else None


def _chunks(values: Sequence[str], size: int = 350) -> Iterator[Sequence[str]]:
    for offset in range(0, len(values), size):
        yield values[offset : offset + size]


def load_canonical_readings(
    connection: sqlite3.Connection, texts: Iterable[str]
) -> dict[str, tuple[SourceReading, ...]]:
    result: dict[str, list[SourceReading]] = {}
    canonical_columns = {
        str(row[1])
        for row in connection.execute("PRAGMA table_info(canonical_readings)")
    }
    source_expression = "pinyin_sources" if "pinyin_sources" in canonical_columns else "''"
    unique = sorted({text for text in texts if text})
    for chunk in _chunks(unique):
        placeholders = ",".join("?" for _ in chunk)
        for row in connection.execute(
            f"""
            SELECT text, marked_pinyin, numeric_pinyin, is_primary, reading_rank,
                   {source_expression} AS pinyin_sources
              FROM canonical_readings
             WHERE text IN ({placeholders})
             ORDER BY text, reading_rank, marked_pinyin
            """,
            tuple(chunk),
        ):
            sources = {
                source.strip()
                for source in str(row["pinyin_sources"] or "").split(",")
                if source.strip()
            }
            if sources and all(source.startswith("psc_orthoepy_") for source in sources):
                # Compare against the baseline lexicon, not against additions
                # previously exported by this workflow. This keeps --apply
                # idempotent after the source bundle is rebuilt.
                continue
            result.setdefault(str(row["text"]), []).append(
                SourceReading(
                    str(row["marked_pinyin"]),
                    str(row["numeric_pinyin"]),
                    bool(row["is_primary"]),
                    int(row["reading_rank"]),
                )
            )
    return {key: tuple(value) for key, value in result.items()}


@dataclass(frozen=True)
class CoverageCandidate:
    candidate_key: str
    fingerprint: str
    version_key: str
    authority_status: str
    source_row: int
    word_page_number: int
    section_label: str
    candidate_kind: str
    text: str
    target_reading: str
    target_numeric: str
    target_indexes: tuple[int, ...]
    proposed_marked_pinyin: str
    proposed_numeric_pinyin: str
    proposal_options: tuple[str, ...]
    coverage_status: str
    derivation: str
    auto_eligible: bool
    requires_review: bool
    gate_accepted: bool
    gate_reason: str
    source_entry_text: str
    explanation: str


def _candidate_key(seed: CandidateSeed) -> str:
    payload = "\0".join(
        (
            seed.version_key,
            str(seed.source_row),
            seed.candidate_kind,
            seed.text,
            seed.target_reading,
            ",".join(str(index) for index in seed.target_indexes),
        )
    )
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def _candidate_fingerprint(seed: CandidateSeed, proposal: str, status: str) -> str:
    payload = "\0".join(
        (
            _candidate_key(seed),
            seed.source_entry_text,
            proposal,
            status,
        )
    )
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def _primary_single(readings: Sequence[SourceReading]) -> str:
    values = {
        reading.marked
        for reading in readings
        if reading.is_primary and len(reading.marked_syllables) == 1
    }
    return next(iter(values)) if len(values) == 1 else ""


def _resolve_seed(
    seed: CandidateSeed,
    readings: dict[str, tuple[SourceReading, ...]],
    gate: ReadingGate,
) -> CoverageCandidate:
    target_numeric = marked_syllable_to_numeric(seed.target_reading)
    source_readings = readings.get(seed.text, ())
    proposed = ""
    options: tuple[str, ...] = ()
    derivation = ""
    explanation = ""

    if seed.candidate_kind == "single_char":
        exact = any(reading.numeric == target_numeric for reading in source_readings)
        if exact:
            status = "covered_exact"
            derivation = "direct_headword_reading"
            explanation = "原型已有相同单字读音。"
        else:
            status = "missing_reading" if source_readings else "missing_text"
            proposed = seed.target_reading
            derivation = "direct_headword_reading"
            explanation = "审音表直接列出该字音，原型尚未覆盖。"
    elif not seed.target_indexes:
        status = "unresolved"
        derivation = "missing_headword_placeholder"
        explanation = "例词没有可定位的代字号。"
    else:
        exact = tuple(
            reading
            for reading in source_readings
            if len(reading.numeric_syllables) == len(seed.text)
            and all(
                reading.numeric_syllables[target_index] == target_numeric
                for target_index in seed.target_indexes
            )
        )
        if exact:
            status = "covered_exact"
            derivation = "existing_phrase_reading"
            explanation = "原型已有该例词且目标字读音一致。"
        else:
            proposals: set[str] = set()
            for reading in source_readings:
                syllables = list(reading.marked_syllables)
                if len(syllables) != len(seed.text):
                    continue
                for target_index in seed.target_indexes:
                    syllables[target_index] = seed.target_reading
                proposals.add(" ".join(syllables))
            if proposals:
                derivation = "existing_phrase_target_substitution"
            else:
                syllables: list[str] = []
                for index, character in enumerate(seed.text):
                    if index in seed.target_indexes:
                        syllables.append(seed.target_reading)
                        continue
                    value = _primary_single(readings.get(character, ()))
                    if not value:
                        syllables = []
                        break
                    syllables.append(value)
                if syllables:
                    proposals.add(" ".join(syllables))
                    derivation = "primary_character_composition"
            options = tuple(sorted(proposals))
            if len(options) == 1:
                proposed = options[0]
                status = "missing_reading" if source_readings else "missing_text"
                explanation = (
                    "审音表证明目标字在该例词中的读音；完整词音由原型既有读音组合提出，需复核。"
                )
            elif options:
                status = "ambiguous_proposal"
                explanation = "可以形成多个完整词音，需要人工选择或校正。"
            else:
                status = "unresolved"
                explanation = "缺少形成完整词音所需的其他字音。"

    gate_accepted = False
    gate_reason = ""
    proposed_numeric = ""
    if proposed:
        gate_result = gate.admit(
            seed.text,
            proposed,
            codepoint_context=seed.candidate_kind == "single_char",
            source=(
                "psc_orthoepy_1985"
                if seed.version_key == "official_1985"
                else "psc_orthoepy_2016_draft"
            ),
        )
        gate_accepted = gate_result.accepted
        gate_reason = gate_result.reason
        if gate_result.accepted:
            proposed = gate_result.marked
            proposed_numeric = gate_result.numeric
        else:
            status = "gate_rejected"
            explanation = "拟新增读音未通过现有拼音与编码门禁：" + gate_result.reason

    direct_official_single = bool(
        seed.candidate_kind == "single_char" and not target_numeric.endswith("5")
    )
    official_existing_phrase_substitution = bool(
        seed.candidate_kind == "example_phrase"
        and derivation == "existing_phrase_target_substitution"
        and len(seed.target_indexes) == 1
    )
    auto_eligible = bool(
        seed.version_key == "official_1985"
        and status in {"missing_reading", "missing_text"}
        and gate_accepted
        and (direct_official_single or official_existing_phrase_substitution)
    )
    requires_review = bool(
        status not in {"covered_exact"} and not auto_eligible
    )
    key = _candidate_key(seed)
    return CoverageCandidate(
        key,
        _candidate_fingerprint(seed, proposed, status),
        seed.version_key,
        seed.authority_status,
        seed.source_row,
        seed.word_page_number,
        seed.section_label,
        seed.candidate_kind,
        seed.text,
        seed.target_reading,
        target_numeric,
        seed.target_indexes,
        proposed,
        proposed_numeric,
        options,
        status,
        derivation,
        auto_eligible,
        requires_review,
        gate_accepted,
        gate_reason,
        seed.source_entry_text,
        explanation,
    )


def _load_seeds(connection: sqlite3.Connection) -> tuple[CandidateSeed, ...]:
    available = {
        str(row[0])
        for row in connection.execute(
            "SELECT name FROM sqlite_master WHERE type IN ('table','view')"
        )
    }
    required = {"orthoepy_entries", "orthoepy_source_rows", "orthoepy_datasets"}
    if not required.issubset(available):
        raise ValueError(f"PSC database lacks orthoepy objects: {sorted(required - available)}")
    rows = connection.execute(
        """
        SELECT e.version_key, e.authority_status, e.source_row,
               e.word_page_number, e.section_label, e.entry_text, e.headword,
               e.inherited_from_1985
          FROM orthoepy_entries AS e
          JOIN orthoepy_datasets AS d ON d.id=e.dataset_id
         WHERE d.dataset_key=?
           AND (e.version_key='official_1985'
                OR (e.version_key='draft_2016' AND e.inherited_from_1985=0))
         ORDER BY e.version_key, e.source_row
        """,
        (DATASET_KEY,),
    )
    seeds: list[CandidateSeed] = []
    for row in rows:
        seeds.extend(extract_entry_seeds(row))
    return tuple(seeds)


def _create_audit_schema(connection: sqlite3.Connection) -> None:
    connection.executescript(
        """
        PRAGMA foreign_keys = ON;
        CREATE TABLE audit_run (
            id INTEGER PRIMARY KEY CHECK(id=1),
            created_at_utc TEXT NOT NULL,
            workflow TEXT NOT NULL,
            psc_db_json TEXT NOT NULL,
            source_db_json TEXT NOT NULL,
            candidate_count INTEGER NOT NULL
        );
        CREATE TABLE candidates (
            candidate_key TEXT PRIMARY KEY,
            fingerprint TEXT NOT NULL,
            version_key TEXT NOT NULL,
            authority_status TEXT NOT NULL,
            source_row INTEGER NOT NULL,
            word_page_number INTEGER NOT NULL,
            section_label TEXT NOT NULL,
            candidate_kind TEXT NOT NULL,
            text TEXT NOT NULL,
            target_reading TEXT NOT NULL,
            target_numeric TEXT NOT NULL,
            target_indexes_json TEXT NOT NULL,
            proposed_marked_pinyin TEXT NOT NULL,
            proposed_numeric_pinyin TEXT NOT NULL,
            proposal_options_json TEXT NOT NULL,
            coverage_status TEXT NOT NULL,
            derivation TEXT NOT NULL,
            auto_eligible INTEGER NOT NULL CHECK(auto_eligible IN (0,1)),
            requires_review INTEGER NOT NULL CHECK(requires_review IN (0,1)),
            gate_accepted INTEGER NOT NULL CHECK(gate_accepted IN (0,1)),
            gate_reason TEXT NOT NULL,
            source_entry_text TEXT NOT NULL,
            explanation TEXT NOT NULL
        ) WITHOUT ROWID;
        CREATE INDEX candidate_status_idx
            ON candidates(coverage_status, version_key, candidate_kind, source_row);
        CREATE VIEW missing_candidates AS
        SELECT * FROM candidates WHERE coverage_status <> 'covered_exact';
        CREATE VIEW automatic_official_additions AS
        SELECT * FROM candidates WHERE auto_eligible=1;
        CREATE VIEW review_queue AS
        SELECT * FROM candidates WHERE requires_review=1;
        CREATE VIEW coverage_summary AS
        SELECT version_key, candidate_kind, coverage_status,
               COUNT(*) AS record_count,
               SUM(auto_eligible) AS automatic_count,
               SUM(requires_review) AS review_count
          FROM candidates
         GROUP BY version_key, candidate_kind, coverage_status
         ORDER BY version_key, candidate_kind, coverage_status;
        """
    )


def run_coverage_audit(
    psc_database: Path,
    source_database: Path,
    output_database: Path,
    *,
    decoder_inventory: Path,
) -> dict[str, object]:
    psc_snapshot = _snapshot(psc_database)
    source_snapshot = _snapshot(source_database)
    psc = _connect_read_only(psc_database)
    source = _connect_read_only(source_database)
    try:
        seeds = _load_seeds(psc)
        required_texts = {seed.text for seed in seeds}
        required_texts.update(character for seed in seeds for character in seed.text)
        readings = load_canonical_readings(source, required_texts)
        gate = ReadingGate(decoder_inventory)
        candidates = tuple(_resolve_seed(seed, readings, gate) for seed in seeds)
    finally:
        source.close()
        psc.close()

    output_database.parent.mkdir(parents=True, exist_ok=True)
    temporary = output_database.with_name(f".{output_database.name}.{id(candidates)}.tmp")
    if temporary.exists():
        temporary.unlink()
    connection = sqlite3.connect(temporary)
    try:
        _create_audit_schema(connection)
        connection.execute(
            "INSERT INTO audit_run VALUES (1,?,?,?,?,?)",
            (
                _utc_now(),
                "psc-orthoepy-candidate-coverage-v1",
                json.dumps(psc_snapshot, ensure_ascii=False, sort_keys=True),
                json.dumps(source_snapshot, ensure_ascii=False, sort_keys=True),
                len(candidates),
            ),
        )
        connection.executemany(
            """
            INSERT INTO candidates (
                candidate_key, fingerprint, version_key, authority_status,
                source_row, word_page_number, section_label, candidate_kind,
                text, target_reading, target_numeric, target_indexes_json,
                proposed_marked_pinyin, proposed_numeric_pinyin,
                proposal_options_json, coverage_status, derivation,
                auto_eligible, requires_review, gate_accepted, gate_reason,
                source_entry_text, explanation
            ) VALUES (
                ?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?
            )
            """,
            (
                (
                    item.candidate_key,
                    item.fingerprint,
                    item.version_key,
                    item.authority_status,
                    item.source_row,
                    item.word_page_number,
                    item.section_label,
                    item.candidate_kind,
                    item.text,
                    item.target_reading,
                    item.target_numeric,
                    json.dumps(item.target_indexes),
                    item.proposed_marked_pinyin,
                    item.proposed_numeric_pinyin,
                    json.dumps(item.proposal_options, ensure_ascii=False),
                    item.coverage_status,
                    item.derivation,
                    int(item.auto_eligible),
                    int(item.requires_review),
                    int(item.gate_accepted),
                    item.gate_reason,
                    item.source_entry_text,
                    item.explanation,
                )
                for item in candidates
            ),
        )
        connection.commit()
        if connection.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
            raise RuntimeError("orthoepy coverage audit integrity check failed")
    finally:
        connection.close()
    temporary.replace(output_database)
    _assert_unchanged(psc_snapshot)
    _assert_unchanged(source_snapshot)

    counts: dict[str, int] = {}
    for candidate in candidates:
        counts[candidate.coverage_status] = counts.get(candidate.coverage_status, 0) + 1
    return {
        "database": str(output_database.resolve()),
        "candidate_count": len(candidates),
        "status_counts": dict(sorted(counts.items())),
        "automatic_official_additions": sum(item.auto_eligible for item in candidates),
        "review_queue": sum(item.requires_review for item in candidates),
        "psc_sha256": psc_snapshot["sha256"],
        "source_sha256": source_snapshot["sha256"],
    }


@dataclass(frozen=True)
class ReviewItem:
    candidate: CoverageCandidate
    decision: str = "pending"
    corrected_text: str = ""
    corrected_pinyin: str = ""
    note: str = ""
    stale_decision: bool = False

    @property
    def effective_text(self) -> str:
        return self.corrected_text if self.decision == "corrected_approve" else self.candidate.text

    @property
    def effective_pinyin(self) -> str:
        return (
            self.corrected_pinyin
            if self.decision == "corrected_approve"
            else self.candidate.proposed_marked_pinyin
        )


def _candidate_from_row(row: sqlite3.Row) -> CoverageCandidate:
    return CoverageCandidate(
        str(row["candidate_key"]),
        str(row["fingerprint"]),
        str(row["version_key"]),
        str(row["authority_status"]),
        int(row["source_row"]),
        int(row["word_page_number"]),
        str(row["section_label"]),
        str(row["candidate_kind"]),
        str(row["text"]),
        str(row["target_reading"]),
        str(row["target_numeric"]),
        tuple(json.loads(str(row["target_indexes_json"]))),
        str(row["proposed_marked_pinyin"]),
        str(row["proposed_numeric_pinyin"]),
        tuple(json.loads(str(row["proposal_options_json"]))),
        str(row["coverage_status"]),
        str(row["derivation"]),
        bool(row["auto_eligible"]),
        bool(row["requires_review"]),
        bool(row["gate_accepted"]),
        str(row["gate_reason"]),
        str(row["source_entry_text"]),
        str(row["explanation"]),
    )


class CoverageReviewStore:
    """Persist coverage-only decisions without modifying either source DB."""

    def __init__(self, audit_database: Path, decision_database: Path | None = None) -> None:
        self.audit_database = audit_database.resolve(strict=True)
        self.decision_database = (
            decision_database.resolve()
            if decision_database
            else self.audit_database.with_name("orthoepy_coverage_decisions.sqlite3")
        )
        self.audit = _connect_read_only(self.audit_database)
        self.decision_database.parent.mkdir(parents=True, exist_ok=True)
        self.decisions = sqlite3.connect(self.decision_database)
        self.decisions.row_factory = sqlite3.Row
        self.decisions.execute("PRAGMA busy_timeout = 5000")
        with self.decisions:
            self.decisions.executescript(
                """
                CREATE TABLE IF NOT EXISTS coverage_decisions (
                    candidate_key TEXT PRIMARY KEY,
                    candidate_fingerprint TEXT NOT NULL,
                    decision TEXT NOT NULL CHECK(decision IN (
                        'approve','corrected_approve','defer','reject'
                    )),
                    corrected_text TEXT NOT NULL DEFAULT '',
                    corrected_pinyin TEXT NOT NULL DEFAULT '',
                    note TEXT NOT NULL DEFAULT '',
                    reviewer TEXT NOT NULL DEFAULT 'manual',
                    updated_at_utc TEXT NOT NULL
                ) WITHOUT ROWID;
                CREATE TABLE IF NOT EXISTS coverage_decision_history (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    candidate_key TEXT NOT NULL,
                    action TEXT NOT NULL CHECK(action IN ('save','clear')),
                    previous_json TEXT,
                    current_json TEXT,
                    occurred_at_utc TEXT NOT NULL
                );
                """
            )

    def close(self) -> None:
        self.audit.close()
        self.decisions.close()

    def load_items(self, *, include_covered: bool = False) -> list[ReviewItem]:
        query = "SELECT * FROM candidates"
        if not include_covered:
            query += " WHERE coverage_status <> 'covered_exact'"
        query += " ORDER BY auto_eligible DESC, requires_review DESC, version_key, source_row, candidate_kind, text"
        saved = {
            str(row["candidate_key"]): row
            for row in self.decisions.execute("SELECT * FROM coverage_decisions")
        }
        result: list[ReviewItem] = []
        for row in self.audit.execute(query):
            candidate = _candidate_from_row(row)
            decision = saved.get(candidate.candidate_key)
            if decision is None:
                result.append(ReviewItem(candidate))
                continue
            stale = str(decision["candidate_fingerprint"]) != candidate.fingerprint
            result.append(
                ReviewItem(
                    candidate,
                    "pending" if stale else str(decision["decision"]),
                    str(decision["corrected_text"]),
                    str(decision["corrected_pinyin"]),
                    str(decision["note"]),
                    stale,
                )
            )
        return result

    def save(
        self,
        candidate_key: str,
        decision: str,
        *,
        corrected_text: str = "",
        corrected_pinyin: str = "",
        note: str = "",
        reviewer: str = "manual",
    ) -> None:
        if decision not in VALID_DECISIONS:
            raise ValueError(f"invalid coverage decision: {decision}")
        row = self.audit.execute(
            "SELECT * FROM candidates WHERE candidate_key=?", (candidate_key,)
        ).fetchone()
        if row is None:
            raise KeyError(candidate_key)
        candidate = _candidate_from_row(row)
        corrected_text = corrected_text.strip()
        corrected_pinyin = " ".join(corrected_pinyin.split())
        if decision == "corrected_approve" and not (corrected_text and corrected_pinyin):
            raise ValueError("corrected approval requires complete text and Pinyin")
        previous = self.decisions.execute(
            "SELECT * FROM coverage_decisions WHERE candidate_key=?", (candidate_key,)
        ).fetchone()
        now = _utc_now()
        current = {
            "candidate_key": candidate_key,
            "candidate_fingerprint": candidate.fingerprint,
            "decision": decision,
            "corrected_text": corrected_text,
            "corrected_pinyin": corrected_pinyin,
            "note": note.strip(),
            "reviewer": reviewer,
            "updated_at_utc": now,
        }
        with self.decisions:
            self.decisions.execute(
                """
                INSERT INTO coverage_decisions VALUES (?,?,?,?,?,?,?,?)
                ON CONFLICT(candidate_key) DO UPDATE SET
                    candidate_fingerprint=excluded.candidate_fingerprint,
                    decision=excluded.decision,
                    corrected_text=excluded.corrected_text,
                    corrected_pinyin=excluded.corrected_pinyin,
                    note=excluded.note,
                    reviewer=excluded.reviewer,
                    updated_at_utc=excluded.updated_at_utc
                """,
                tuple(current.values()),
            )
            self.decisions.execute(
                "INSERT INTO coverage_decision_history(candidate_key,action,previous_json,current_json,occurred_at_utc) VALUES (?, 'save', ?, ?, ?)",
                (
                    candidate_key,
                    json.dumps(dict(previous), ensure_ascii=False) if previous else None,
                    json.dumps(current, ensure_ascii=False),
                    now,
                ),
            )

    def clear(self, candidate_key: str) -> None:
        previous = self.decisions.execute(
            "SELECT * FROM coverage_decisions WHERE candidate_key=?", (candidate_key,)
        ).fetchone()
        with self.decisions:
            self.decisions.execute(
                "DELETE FROM coverage_decisions WHERE candidate_key=?", (candidate_key,)
            )
            self.decisions.execute(
                "INSERT INTO coverage_decision_history(candidate_key,action,previous_json,current_json,occurred_at_utc) VALUES (?, 'clear', ?, NULL, ?)",
                (
                    candidate_key,
                    json.dumps(dict(previous), ensure_ascii=False) if previous else None,
                    _utc_now(),
                ),
            )


def export_approved_catalog(
    store: CoverageReviewStore,
    output_path: Path,
    *,
    decoder_inventory: Path,
) -> dict[str, object]:
    gate = ReadingGate(decoder_inventory)
    grouped: dict[tuple[str, str, str], dict[str, object]] = {}
    rejected: list[dict[str, str]] = []
    for item in store.load_items():
        candidate = item.candidate
        automatic = candidate.auto_eligible and item.decision in {"pending", "approve"}
        manual = item.decision in {"approve", "corrected_approve"} and not item.stale_decision
        if not (automatic or manual):
            continue
        text = item.effective_text.strip()
        pinyin = " ".join(item.effective_pinyin.split())
        restored = restore_missing_syllable_spaces(
            pinyin, len(text), decoder_inventory
        )
        if restored is not None:
            pinyin = restored
        source = (
            "psc_orthoepy_1985"
            if candidate.version_key == "official_1985"
            else "psc_orthoepy_2016_draft"
        )
        result = gate.admit(
            text,
            pinyin,
            codepoint_context=len(text) == 1,
            source=source,
        )
        if not result.accepted:
            rejected.append(
                {"candidate_key": candidate.candidate_key, "reason": result.reason}
            )
            continue
        key = (text, result.marked, source)
        evidence = {
            "candidate_key": candidate.candidate_key,
            "source_row": candidate.source_row,
            "word_page_number": candidate.word_page_number,
            "section_label": candidate.section_label,
            "candidate_kind": candidate.candidate_kind,
            "target_reading": candidate.target_reading,
            "approval": "automatic_direct_official" if automatic else item.decision,
            "note": item.note,
        }
        record = grouped.setdefault(
            key,
            {
                "text": text,
                "marked_pinyin": result.marked,
                "numeric_pinyin": result.numeric,
                "source": source,
                "source_category": (
                    "official_orthoepy"
                    if candidate.version_key == "official_1985"
                    else "consultation_draft"
                ),
                "source_rank": 90 if candidate.version_key == "official_1985" else 95,
                "source_primary": False,
                "evidence": [],
            },
        )
        record["evidence"].append(evidence)
    records = sorted(
        grouped.values(),
        key=lambda item: (str(item["text"]), str(item["marked_pinyin"]), str(item["source"])),
    )
    payload = {
        "schema_version": "yime-reviewed-orthoepy-readings-v1",
        "policy": {
            "purpose": "Add source-attested input coverage only.",
            "ranking": "Never mark an orthoepy addition as source-primary.",
            "official_1985": "Direct missing single-character readings may be admitted automatically.",
            "draft_2016": "Consultation-draft records require an explicit manual approval.",
        },
        "records": records,
        "rejected_at_export": rejected,
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    return {
        "output": str(output_path.resolve()),
        "record_count": len(records),
        "rejected_count": len(rejected),
    }
