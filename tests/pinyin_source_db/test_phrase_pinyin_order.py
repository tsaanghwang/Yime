from __future__ import annotations

import csv
import sqlite3
import unicodedata
from pathlib import Path

import pytest

from internal_data.phrase_pinyin.phrase_source_staging import import_to_staging
from yime.utils.dictionary_pinyin_compliance import (
    TONE_MARKS,
    canonicalize_reading,
    load_policy,
)


REPO_ROOT = Path(__file__).resolve().parents[2]


def test_staging_preserves_phrase_syllable_order(tmp_path: Path) -> None:
    source = tmp_path / "phrase_pinyin.txt"
    source.write_text(
        "听不见: tīng bu jiàn\n"
        "一再地吼: yī zài de hǒu\n"
        "一个劲地问: yí gè jìn de wèn\n"
        "一块石头落了地: yī kuài shí tou luò le dì\n",
        encoding="utf-8",
    )
    database = tmp_path / "phrase_pinyin.db"

    import_to_staging(str(source), database)

    with sqlite3.connect(database) as connection:
        rows = dict(
            connection.execute(
                "SELECT phrase, common_reading FROM phrase_source_staging ORDER BY phrase"
            )
        )

    assert rows == {
        "一个劲地问": "yí gè jìn de wèn",
        "一再地吼": "yī zài de hǒu",
        "一块石头落了地": "yī kuài shí tou luò le dì",
        "听不见": "tīng bu jiàn",
    }


def test_checked_in_phrase_export_keeps_internal_neutral_syllables_in_place() -> None:
    expected = {
        "听不见": "tīng bu jiàn",
        "一再地吼": "yī zài de hǒu",
        "一个劲地问": "yí gè jìn de wèn",
        "一块石头落了地": "yī kuài shí tou luò le dì",
    }
    export_path = REPO_ROOT / "internal_data" / "phrase_pinyin" / "phrase_pinyin.txt"

    actual: dict[str, str] = {}
    with export_path.open("r", encoding="utf-8", newline="") as stream:
        rows = csv.DictReader(
            (line for line in stream if not line.startswith("#")),
            delimiter="\t",
        )
        for row in rows:
            phrase = row["phrase"]
            if phrase in expected:
                actual[phrase] = row["common_reading"]

    assert actual == expected


def test_all_internal_untoned_source_syllables_keep_their_positions_in_export() -> None:
    source_path = REPO_ROOT / "external_data" / "phrase_pinyin.txt"
    export_path = REPO_ROOT / "internal_data" / "phrase_pinyin" / "phrase_pinyin.txt"
    if not source_path.is_file():
        pytest.skip("requires external_data/phrase_pinyin.txt")
    policy = load_policy()
    expected: dict[str, list[str]] = {}

    for raw_line in source_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or ":" not in line:
            continue
        phrase_part, pinyin_part = line.split(":", 1)
        pinyin_part = pinyin_part.split("#", 1)[0]
        phrase = phrase_part.strip()
        source_syllables = pinyin_part.split()
        is_untoned = [
            not any(char in TONE_MARKS for char in unicodedata.normalize("NFD", syllable))
            for syllable in source_syllables
        ]
        has_internal_untoned = any(
            untoned and any(not later for later in is_untoned[index + 1 :])
            for index, untoned in enumerate(is_untoned)
        )
        if len(phrase) <= 1 or not has_internal_untoned:
            continue

        canonical, _ = canonicalize_reading(" ".join(source_syllables), policy)
        readings = expected.setdefault(phrase, [])
        if canonical not in readings:
            readings.append(canonical)

    assert "听不见" in expected

    actual: dict[str, list[str]] = {}
    with export_path.open("r", encoding="utf-8", newline="") as stream:
        rows = csv.DictReader(
            (line for line in stream if not line.startswith("#")),
            delimiter="\t",
        )
        for row in rows:
            phrase = row["phrase"]
            if phrase in expected:
                actual[phrase] = row["readings"].split("|")

    assert actual.keys() == expected.keys()
    for phrase, readings in expected.items():
        assert actual[phrase] == readings, phrase
