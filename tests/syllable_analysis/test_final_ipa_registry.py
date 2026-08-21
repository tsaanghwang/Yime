from __future__ import annotations

import json
from pathlib import Path

from syllable.analysis.final_ipa_registry import (
    PLACEHOLDER_IPA,
    collect_attested_finals,
    load_final_ipa_mapping,
    sync_final_ipa_registry,
)


ROOT = Path(__file__).resolve().parents[2]


def _write(path: Path, payload: object) -> None:
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def test_legacy_registry_is_inverted_and_full_forms_are_restored(tmp_path: Path) -> None:
    registry = tmp_path / "registry.json"
    _write(
        registry,
        {
            "ɿ": "i",
            "ʅ": "i",
            "i": "i",
            "iɤʊ": "iu",
            "ueɪ": "ui",
            "uən": "un",
            "uɤŋ": "uenɡ",
        },
    )

    mapping, migrated = load_final_ipa_mapping(registry)

    assert migrated is True
    assert mapping == {
        "_i": "ɿ/ʅ",
        "i": "i",
        "iou": "iɤʊ",
        "uei": "ueɪ",
        "uen": "uən",
        "ueng": "uɤŋ",
    }


def test_sync_adds_placeholders_removes_extras_and_derives_styles(tmp_path: Path) -> None:
    ganyin = tmp_path / "ganyin.json"
    registry = tmp_path / "registry.json"
    styles = tmp_path / "final_styles.json"
    _write(
        ganyin,
        {
            "ganyin": {
                "single quality ganyin": {"a1": "ā"},
                "front long ganyin": {"ai1": "āi"},
                "back long ganyin": {"uo1": "uō"},
                "triple quality ganyin": {"ueng1": "uēng"},
            }
        },
    )
    _write(
        registry,
        {
            "schema_version": 2,
            "mapping_direction": "final_to_ipa",
            "finals": {"a": "ä", "ai": "aɪ", "extra": "x"},
        },
    )

    result = sync_final_ipa_registry(
        ganyin_path=ganyin,
        registry_path=registry,
        final_styles_path=styles,
    )

    assert result.added == ("uo", "ueng")
    assert result.removed == ("extra",)
    assert result.placeholders == ("uo", "ueng")
    saved, migrated = load_final_ipa_mapping(registry)
    assert migrated is False
    assert saved == {
        "a": "ä",
        "ai": "aɪ",
        "uo": PLACEHOLDER_IPA,
        "ueng": PLACEHOLDER_IPA,
    }
    derived = json.loads(styles.read_text(encoding="utf-8"))
    assert derived["generated_from"] == "external_data/finals_IPA_mapping.json"
    assert derived["finals"]["triple quality finals"]["ueng"]["ipa"] == PLACEHOLDER_IPA


def test_repository_registry_exactly_covers_current_attested_finals() -> None:
    categorized = collect_attested_finals()
    actual = {final for finals in categorized.values() for final in finals}
    mapping, migrated = load_final_ipa_mapping()

    assert migrated is False
    assert len(actual) == 42
    assert set(mapping) == actual
    assert PLACEHOLDER_IPA not in mapping.values()
    assert mapping["ueng"] == "uɤŋ"


def test_repository_final_styles_is_current_derived_view() -> None:
    result = sync_final_ipa_registry(write=False)
    assert result.registry_changed is False
    assert result.final_styles_changed is False
    assert result.placeholders == ()
