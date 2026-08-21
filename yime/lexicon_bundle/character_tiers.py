"""Build the auditable nine-level character classification in the unified source DB."""

from __future__ import annotations

import csv
import json
import sqlite3
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


TIER_NAMES = {
    1: "tgh_level_1",
    2: "tgh_level_2",
    3: "tgh_level_3",
    4: "xhc1983_extension",
    5: "modern_dictionary_estimated",
    6: "hanyu_dazidian",
    7: "mandarin_regional",
    8: "project_encoded",
    9: "unencoded_unihan",
}

TIER_MEMBERSHIP_SOURCES = {
    1: "Unihan kTGH 2013:1-3500",
    2: "Unihan kTGH 2013:3501-6500",
    3: "Unihan kTGH 2013:6501-8105",
    4: "Unihan kXHC1983 excluding prior tiers",
    5: "Unihan kHanyuPinyin/kMandarin candidates ranked by BCC to cumulative cap",
    6: "Unihan kHanyuPinyin excluding prior tiers",
    7: "Unihan kMandarin excluding prior tiers; regional Mandarin coverage evidence",
    8: "project standalone reading passed source gate and has generated Yinyuan encoding",
    9: "Unihan character catalog excluding prior tiers and non-character structural blocks",
}


@dataclass(frozen=True)
class CharacterTierSources:
    other_mappings: Path
    readings: Path
    character_catalog_db: Path
    yinjie_codebook: Path

    def paths(self) -> tuple[Path, ...]:
        return (
            self.other_mappings,
            self.readings,
            self.character_catalog_db,
            self.yinjie_codebook,
        )


@dataclass(frozen=True)
class CharacterTierPolicy:
    tgh_level_ends: tuple[int, int, int] = (3500, 6500, 8105)
    modern_dictionary_estimated_cap: int = 14_000


DEFAULT_POLICY = CharacterTierPolicy()


def create_character_tier_schema(conn: sqlite3.Connection) -> None:
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS unihan_character_inventory (
            codepoint TEXT PRIMARY KEY,
            hanzi TEXT NOT NULL,
            block TEXT,
            block_order INTEGER,
            is_classifiable INTEGER NOT NULL CHECK (is_classifiable IN (0, 1)),
            source_catalog TEXT NOT NULL
        ) WITHOUT ROWID;
        CREATE INDEX IF NOT EXISTS unihan_character_inventory_classifiable_idx
            ON unihan_character_inventory(is_classifiable, codepoint);

        CREATE TABLE IF NOT EXISTS unihan_mandarin_evidence (
            codepoint TEXT PRIMARY KEY,
            kTGH_index INTEGER,
            kXHC1983 TEXT,
            kHanyuPinyin TEXT,
            kMandarin TEXT
        ) WITHOUT ROWID;
        CREATE INDEX IF NOT EXISTS unihan_mandarin_evidence_tgh_idx
            ON unihan_mandarin_evidence(kTGH_index);

        CREATE TABLE IF NOT EXISTS character_tiers (
            codepoint TEXT PRIMARY KEY,
            hanzi TEXT NOT NULL,
            tier_number INTEGER NOT NULL CHECK (tier_number BETWEEN 1 AND 9),
            tier_name TEXT NOT NULL,
            tier_rank INTEGER NOT NULL,
            source_rank INTEGER,
            membership_source TEXT NOT NULL,
            bcc_frequency INTEGER NOT NULL DEFAULT 0,
            accepted_reading_count INTEGER NOT NULL DEFAULT 0,
            encoded_reading_count INTEGER NOT NULL DEFAULT 0,
            decision_note TEXT NOT NULL
        ) WITHOUT ROWID;
        CREATE INDEX IF NOT EXISTS character_tiers_number_rank_idx
            ON character_tiers(tier_number, tier_rank);
        CREATE INDEX IF NOT EXISTS character_tiers_name_rank_idx
            ON character_tiers(tier_name, tier_rank);

        CREATE VIEW IF NOT EXISTS v_character_tier_summary AS
        SELECT tier_number, tier_name, COUNT(*) AS character_count,
               MIN(bcc_frequency) AS min_bcc_frequency,
               MAX(bcc_frequency) AS max_bcc_frequency
        FROM character_tiers
        GROUP BY tier_number, tier_name
        ORDER BY tier_number;
        """
    )


def _parse_unihan_properties(
    path: Path,
    wanted_fields: set[str],
) -> dict[str, dict[str, str]]:
    rows: dict[str, dict[str, str]] = {}
    with path.open("r", encoding="utf-8") as stream:
        for raw_line in stream:
            if not raw_line.startswith("U+"):
                continue
            parts = raw_line.rstrip("\r\n").split("\t", 2)
            if len(parts) != 3:
                continue
            codepoint, field, value = parts
            if field not in wanted_fields:
                continue
            current = rows.setdefault(codepoint, {})
            if field in current:
                current[field] += ";" + value
            else:
                current[field] = value
    return rows


def _parse_tgh_indexes(path: Path, expected_count: int) -> dict[str, int]:
    fields = _parse_unihan_properties(path, {"kTGH"})
    result: dict[str, int] = {}
    for codepoint, values in fields.items():
        raw_value = values["kTGH"].strip()
        prefix = "2013:"
        if not raw_value.startswith(prefix):
            raise ValueError(f"unsupported kTGH value for {codepoint}: {raw_value}")
        result[codepoint] = int(raw_value[len(prefix):])

    expected_indexes = set(range(1, expected_count + 1))
    actual_indexes = set(result.values())
    if len(result) != expected_count or actual_indexes != expected_indexes:
        missing = sorted(expected_indexes - actual_indexes)[:10]
        unexpected = sorted(actual_indexes - expected_indexes)[:10]
        raise ValueError(
            "kTGH index coverage mismatch: "
            f"records={len(result)} expected={expected_count} "
            f"missing={missing} unexpected={unexpected}"
        )
    return result


def _codepoint_int(codepoint: str) -> int:
    return int(codepoint[2:], 16)


def _is_classifiable_catalog_codepoint(codepoint: str) -> bool:
    value = _codepoint_int(codepoint)
    if 0x2F00 <= value <= 0x2FDF:  # Kangxi radicals
        return False
    if 0x2FF0 <= value <= 0x2FFF:  # Ideographic description characters
        return False
    if 0x31C0 <= value <= 0x31EF:  # CJK strokes
        return False
    return True


def _load_character_catalog(
    path: Path,
) -> dict[str, tuple[str, str | None, int | None, int]]:
    uri = f"file:{path.resolve().as_posix()}?mode=ro"
    with sqlite3.connect(uri, uri=True) as catalog:
        table = catalog.execute(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name='hanzi'"
        ).fetchone()
        if table is None:
            raise ValueError(f"character catalog database has no hanzi table: {path}")
        result = {}
        for codepoint, hanzi, block, block_order in catalog.execute(
            "SELECT codepoint, hanzi, block, block_order FROM hanzi"
        ):
            key = str(codepoint)
            result[key] = (
                str(hanzi),
                None if block is None else str(block),
                None if block_order is None else int(block_order),
                int(_is_classifiable_catalog_codepoint(key)),
            )
        return result


def _load_encoded_readings(
    conn: sqlite3.Connection,
    codebook_path: Path,
) -> tuple[dict[str, int], dict[str, int]]:
    payload = json.loads(codebook_path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError(f"Yinjie codebook must be an object: {codebook_path}")
    encoded_syllables = {str(key).strip() for key in payload if str(key).strip()}

    accepted_counts: dict[str, int] = {}
    encoded_counts: dict[str, int] = {}
    for codepoint, numeric_pinyin in conn.execute(
        """
        SELECT codepoint, numeric_pinyin
        FROM canonical_readings
        WHERE text_length = 1
          AND pronunciation_scope = 'standalone'
          AND codepoint IS NOT NULL
        """
    ):
        key = str(codepoint)
        accepted_counts[key] = accepted_counts.get(key, 0) + 1
        if str(numeric_pinyin).strip() in encoded_syllables:
            encoded_counts[key] = encoded_counts.get(key, 0) + 1
    return accepted_counts, encoded_counts


def _load_bcc_char_frequencies(conn: sqlite3.Connection) -> dict[str, int]:
    result: dict[str, int] = {}
    for text, frequency in conn.execute(
        "SELECT text, frequency FROM bcc_frequency WHERE LENGTH(text) = 1"
    ):
        character = str(text)
        result[f"U+{ord(character):04X}"] = int(frequency or 0)
    return result


def _rank_codepoints(
    codepoints: Iterable[str],
    frequencies: dict[str, int],
    evidence_strength: dict[str, int],
) -> list[str]:
    return sorted(
        set(codepoints),
        key=lambda codepoint: (
            -frequencies.get(codepoint, 0),
            -evidence_strength.get(codepoint, 0),
            _codepoint_int(codepoint),
        ),
    )


def rebuild_character_tiers(
    conn: sqlite3.Connection,
    sources: CharacterTierSources,
    *,
    policy: CharacterTierPolicy = DEFAULT_POLICY,
) -> dict[str, int]:
    """Rebuild all tier evidence and mutually exclusive membership rows."""

    create_character_tier_schema(conn)
    first_end, second_end, third_end = policy.tgh_level_ends
    if not (0 < first_end < second_end < third_end):
        raise ValueError("TGH level boundaries must be strictly increasing")
    if policy.modern_dictionary_estimated_cap <= third_end:
        raise ValueError("modern dictionary cap must exceed the TGH total")

    tgh_indexes = _parse_tgh_indexes(sources.other_mappings, third_end)
    reading_fields = _parse_unihan_properties(
        sources.readings,
        {"kXHC1983", "kHanyuPinyin", "kMandarin"},
    )
    xhc = {cp for cp, values in reading_fields.items() if values.get("kXHC1983")}
    hanyu = {
        cp for cp, values in reading_fields.items() if values.get("kHanyuPinyin")
    }
    mandarin = {
        cp for cp, values in reading_fields.items() if values.get("kMandarin")
    }
    catalog = _load_character_catalog(sources.character_catalog_db)
    accepted_counts, encoded_counts = _load_encoded_readings(
        conn, sources.yinjie_codebook
    )
    frequencies = _load_bcc_char_frequencies(conn)

    all_evidence_codepoints = set(tgh_indexes) | set(reading_fields)
    for codepoint in all_evidence_codepoints - set(catalog):
        catalog[codepoint] = (
            chr(_codepoint_int(codepoint)),
            "Unihan evidence outside local catalog",
            None,
            1,
        )
    for codepoint in set(accepted_counts) - set(catalog):
        catalog[codepoint] = (
            chr(_codepoint_int(codepoint)),
            "project encoded character outside local catalog",
            None,
            1,
        )

    conn.execute("DELETE FROM unihan_character_inventory")
    conn.executemany(
        """
        INSERT INTO unihan_character_inventory (
            codepoint, hanzi, block, block_order, is_classifiable, source_catalog
        ) VALUES (?, ?, ?, ?, ?, ?)
        """,
        (
            (
                codepoint,
                values[0],
                values[1],
                values[2],
                values[3],
                str(sources.character_catalog_db),
            )
            for codepoint, values in sorted(
                catalog.items(), key=lambda item: _codepoint_int(item[0])
            )
        ),
    )

    conn.execute("DELETE FROM unihan_mandarin_evidence")
    conn.executemany(
        """
        INSERT INTO unihan_mandarin_evidence (
            codepoint, kTGH_index, kXHC1983, kHanyuPinyin, kMandarin
        ) VALUES (?, ?, ?, ?, ?)
        """,
        (
            (
                codepoint,
                tgh_indexes.get(codepoint),
                reading_fields.get(codepoint, {}).get("kXHC1983"),
                reading_fields.get(codepoint, {}).get("kHanyuPinyin"),
                reading_fields.get(codepoint, {}).get("kMandarin"),
            )
            for codepoint in sorted(
                all_evidence_codepoints, key=_codepoint_int
            )
        ),
    )

    tiers: dict[int, set[str]] = {
        1: {
            cp for cp, index in tgh_indexes.items()
            if 1 <= index <= first_end
        },
        2: {
            cp for cp, index in tgh_indexes.items()
            if first_end < index <= second_end
        },
        3: {
            cp for cp, index in tgh_indexes.items()
            if second_end < index <= third_end
        },
    }
    assigned = set().union(*tiers.values())
    tiers[4] = xhc - assigned
    assigned |= tiers[4]

    fifth_count = policy.modern_dictionary_estimated_cap - len(assigned)
    fifth_candidates = (hanyu | mandarin) - assigned
    fifth_candidates &= set(encoded_counts)
    if len(fifth_candidates) < fifth_count:
        raise ValueError(
            "not enough encoded kHanyuPinyin/kMandarin candidates for tier 5: "
            f"need={fifth_count} available={len(fifth_candidates)}"
        )
    evidence_strength = {
        cp: int(cp in hanyu) + int(cp in mandarin)
        for cp in fifth_candidates
    }
    tiers[5] = set(
        _rank_codepoints(fifth_candidates, frequencies, evidence_strength)[
            :fifth_count
        ]
    )
    assigned |= tiers[5]

    tiers[6] = hanyu - assigned
    assigned |= tiers[6]
    tiers[7] = mandarin - assigned
    assigned |= tiers[7]
    tiers[8] = set(encoded_counts) - assigned
    assigned |= tiers[8]
    classifiable_catalog = {
        cp for cp, values in catalog.items() if values[3] == 1
    }
    tiers[9] = classifiable_catalog - assigned

    conn.execute("DELETE FROM character_tiers")
    output_rows: list[tuple[object, ...]] = []
    for tier_number in range(1, 10):
        members = tiers[tier_number]
        tier_evidence_strength = {
            cp: int(cp in hanyu) + int(cp in mandarin) + int(cp in xhc)
            for cp in members
        }
        ranked = _rank_codepoints(
            members, frequencies, tier_evidence_strength
        )
        for tier_rank, codepoint in enumerate(ranked, start=1):
            tgh_index = tgh_indexes.get(codepoint)
            note = TIER_MEMBERSHIP_SOURCES[tier_number]
            if tier_number == 5:
                note += (
                    f"; cumulative_cap={policy.modern_dictionary_estimated_cap}"
                )
            output_rows.append(
                (
                    codepoint,
                    catalog.get(
                        codepoint,
                        (chr(_codepoint_int(codepoint)), None, None, 1),
                    )[0],
                    tier_number,
                    TIER_NAMES[tier_number],
                    tier_rank,
                    tgh_index,
                    TIER_MEMBERSHIP_SOURCES[tier_number],
                    frequencies.get(codepoint, 0),
                    accepted_counts.get(codepoint, 0),
                    encoded_counts.get(codepoint, 0),
                    note,
                )
            )
    conn.executemany(
        """
        INSERT INTO character_tiers (
            codepoint, hanzi, tier_number, tier_name, tier_rank,
            source_rank, membership_source, bcc_frequency,
            accepted_reading_count, encoded_reading_count, decision_note
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        output_rows,
    )
    conn.executemany(
        "INSERT OR REPLACE INTO metadata (key, value) VALUES (?, ?)",
        (
            ("character_tier_schema", "yime-character-tiers-v1"),
            (
                "character_tier_modern_dictionary_estimated_cap",
                str(policy.modern_dictionary_estimated_cap),
            ),
            (
                "character_tier_catalog_rows",
                str(len(catalog)),
            ),
            (
                "character_tier_excluded_structure_rows",
                str(sum(1 for values in catalog.values() if values[3] == 0)),
            ),
        ),
    )
    conn.commit()
    return {
        TIER_NAMES[tier_number]: len(tiers[tier_number])
        for tier_number in range(1, 10)
    }


def export_character_tiers(
    conn: sqlite3.Connection,
    path: Path,
) -> int:
    fields = (
        "codepoint",
        "hanzi",
        "tier_number",
        "tier_name",
        "tier_rank",
        "source_rank",
        "membership_source",
        "bcc_frequency",
        "accepted_reading_count",
        "encoded_reading_count",
        "decision_note",
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    count = 0
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t", lineterminator="\n")
        writer.writerow(fields)
        for row in conn.execute(
            """
            SELECT codepoint, hanzi, tier_number, tier_name, tier_rank,
                   source_rank, membership_source, bcc_frequency,
                   accepted_reading_count, encoded_reading_count, decision_note
            FROM character_tiers
            ORDER BY tier_number, tier_rank
            """
        ):
            writer.writerow(tuple(row))
            count += 1
    return count
