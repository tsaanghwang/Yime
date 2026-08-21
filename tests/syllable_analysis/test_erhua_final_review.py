from __future__ import annotations

import json
import shutil
from datetime import datetime, timezone
from pathlib import Path

import pytest

from syllable.analysis.erhua_final_review import (
    ErhuaFinalDraftStore,
    SEGMENT_NAMES,
    build_psc_result_group_index,
    review_variant_source_annotations,
    render_surface_segment,
)


ROOT = Path(__file__).resolve().parents[2]
DRAFT = ROOT / "external_data" / "tmp" / "final_styles_erhua_draft.json"
DECOMPOSITION = (
    ROOT
    / "internal_data"
    / "yinyuan_derived"
    / "ganyin_to_pianyin_sequence.json"
)


def segment(
    quality: str,
    *,
    rhotic: bool = False,
    nasalized: bool = False,
) -> dict[str, object]:
    return {
        "quality": quality,
        "features": {"rhotic": rhotic, "nasalized": nasalized},
    }


def test_real_draft_has_complete_three_segment_foundations() -> None:
    store = ErhuaFinalDraftStore(DRAFT, DECOMPOSITION)
    items = {item.final: item for item in store.load_items()}

    assert len(items) == 43
    assert {"v", "ve", "van", "vn"}.isdisjoint(items)
    assert items["ao"].base_segments == {"呼音": "ɑ", "主音": "ɑ", "末音": "ʊ"}
    assert items["ao"].base_segment_ganyin == "ao1"
    assert items["ao"].base_segment_text == "ɑ｜ɑ｜ʊ"
    assert items["ian"].base_ipa == "iɛ̞n"
    assert items["ian"].base_segments == {"呼音": "i", "主音": "ɛ̞", "末音": "n"}
    assert items["üan"].base_ipa == "ʏɛ̞n"
    assert items["üan"].base_segments == {"呼音": "ʏ", "主音": "ɛ̞", "末音": "n"}
    assert items["uai"].base_ipa == "uaɪ"
    assert items["uai"].base_segments == {"呼音": "u", "主音": "a", "末音": "ɪ"}
    assert items["in"].base_segments == {
        "\u547c\u97f3": "i",
        "\u4e3b\u97f3": "ə̆",
        "\u672b\u97f3": "n",
    }
    assert items["ong"].base_segments == {"呼音": "ʊ", "主音": "ɘ̠̆", "末音": "ŋ"}
    assert items["ueng"].base_segments == {"呼音": "u", "主音": "ɤ", "末音": "ŋ"}
    assert items["ueng"].decision == "reviewed"
    assert [row["source_base_final"] for row in items["ong"].source_annotations] == ["ong"]
    assert [row["source_base_final"] for row in items["ueng"].source_annotations] == ["ueng"]
    assert "uong" not in items
    assert "ue" not in items
    assert items["io"].decision == "not_applicable"
    assert items["io"].base_ipa == "io"
    assert items["io"].base_segments == {"呼音": "i", "主音": "o", "末音": "o"}
    assert items["ê"].base_segments == {"呼音": "e̞", "主音": "e̞", "末音": "e̞"}
    assert items["ie"].base_segments == {"呼音": "i", "主音": "e̞", "末音": "e̞"}
    assert items["üe"].base_segments == {"呼音": "ʏ", "主音": "e̞", "末音": "e̞"}
    assert items["_i_front"].display_final == "i[ɿ]"
    assert items["_i_front"].base_segments == {name: "ɿ" for name in SEGMENT_NAMES}
    assert [row["source_index"] for row in items["_i_front"].source_annotations] == [21]
    assert items["_i_back"].display_final == "i[ʅ]"
    assert items["_i_back"].base_segments == {name: "ʅ" for name in SEGMENT_NAMES}
    assert [row["source_index"] for row in items["_i_back"].source_annotations] == [22]
    assert items["ang"].psc_result_group_text == "ãr"
    assert items["e"].psc_result_group_text == "er[ɤr]"
    assert items["a"].psc_result_group_keys == ("ar|oral",)
    assert items["er"].psc_result_group_text == "—"

    payload = json.loads(DRAFT.read_text(encoding="utf-8"))
    group_index = build_psc_result_group_index(payload)
    assert len(group_index) == 26
    assert next(row for row in group_index if row["key"] == "ãr|nasalized")[
        "project_finals"
    ] == ["ang"]

    canonical_un = items["ün"].source_annotations[0]
    assert canonical_un["source_index"] == 27
    assert canonical_un["source_rule"] == "ün>ü:er"
    assert canonical_un["source_base_final"] == "ün"
    assert canonical_un["alignment"]["status"] == "exact_umlaut_form"
    assert canonical_un["source_transcription_correction"] == {
        "text_layer_extraction": "üe>ü:er",
        "verified_visible_rule": "ün>ü:er",
        "verification_method": "manual_visual_review_of_source_page",
        "reason": "PDF 文本层把可见字母 n 错映为 e；保留抽取值并以可见原页核定值参与对齐。",
        "source_page": 2,
    }
    for item in items.values():
        review = item.review
        assert review["schema_version"] == 2
        assert review["surface_segment_schema"] == "quality_features_v1"
        assert "rhotic_positions" not in review
        assert "nasalized_positions" not in review
        for value in review["surface_segments"].values():
            assert set(value) == {"quality", "features"}
            assert set(value["features"]) == {"rhotic", "nasalized"}
            assert all(
                marker not in value["quality"]
                for marker in ("ɚ", "ɝ", "˞", "᷊", "ͬ", "̃")
            )

    assert items["er"].decision == "not_applicable"
    assert items["er"].review["surface_ipa"] == ""

    draft_text = DRAFT.read_text(encoding="utf-8")
    assert "ᵊ" not in draft_text
    assert "ᶹ" not in draft_text


def test_apical_variants_are_selected_from_psc_content_not_row_number() -> None:
    annotations = [
        {"source_index": 9001, "source_base_final": "i(后)"},
        {"source_index": 9002, "source_base_final": "i(前)"},
    ]

    front = review_variant_source_annotations(
        annotations, {"source_base_final": "i(前)"}
    )
    back = review_variant_source_annotations(
        annotations, {"source_base_final": "i(后)"}
    )

    assert [row["source_index"] for row in front] == [9002]
    assert [row["source_index"] for row in back] == [9001]


def test_prune_deferred_internal_finals_removes_technical_and_merge_forms(
    tmp_path: Path,
) -> None:
    draft = tmp_path / "draft.json"
    draft.write_text(DRAFT.read_text(encoding="utf-8"), encoding="utf-8")
    payload = json.loads(draft.read_text(encoding="utf-8"))
    category = next(iter(payload["finals"]))
    sample = next(iter(payload["finals"][category].values()))
    for final in ("ue", "v", "ve", "van", "vn", "uong"):
        payload["finals"][category][final] = sample
    draft.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")

    store = ErhuaFinalDraftStore(draft, DECOMPOSITION)
    removed = store.prune_deferred_internal_finals()
    after = json.loads(draft.read_text(encoding="utf-8"))
    finals = {final for group in after["finals"].values() for final in group}

    assert set(removed) == {"ue", "uong", "v", "ve", "van", "vn"}
    assert set(removed).isdisjoint(finals)


@pytest.fixture()
def copied_store(tmp_path: Path) -> ErhuaFinalDraftStore:
    target = tmp_path / "draft.json"
    shutil.copyfile(DRAFT, target)
    return ErhuaFinalDraftStore(target, DECOMPOSITION)


def test_review_save_is_atomic_and_preserves_research_boundary(
    copied_store: ErhuaFinalDraftStore,
) -> None:
    original = json.loads(copied_store.draft_path.read_text(encoding="utf-8"))
    item = copied_store.save_review(
        "ao",
        surface_segments={
            "呼音": segment("ɑ"),
            "主音": segment("ɑ"),
            "末音": segment("ʊ", rhotic=True),
        },
        note="末段卷舌工作标注。",
        now=datetime(2026, 8, 11, 12, 0, tzinfo=timezone.utc),
    )
    saved = json.loads(copied_store.draft_path.read_text(encoding="utf-8"))

    assert item.decision == "reviewed"
    assert item.review["surface_ipa"] == "ɑɑʊ˞"
    assert item.review["base_segments_ganyin"] == "ao1"
    assert item.review["schema_version"] == 2
    assert item.review["surface_segments"]["末音"] == segment("ʊ", rhotic=True)
    assert "rhotic_positions" not in item.review
    assert "nasalized_positions" not in item.review
    assert item.review["runtime_enabled"] is False
    assert saved["runtime_enabled"] is False
    assert saved["review_summary"] == original["review_summary"]
    assert saved["source_material"] == original["source_material"]
    assert saved["three_segment_review_progress"]["runtime_aliases_generated"] == 0
    assert not list(copied_store.draft_path.parent.glob(".*.tmp"))


def test_review_save_uses_current_generated_base_segments(
    copied_store: ErhuaFinalDraftStore,
) -> None:
    before = {item.final: item for item in copied_store.load_items()}["ian"]
    saved = copied_store.save_review(
        "ian",
        surface_segments=before.review["surface_segments"],
        now=datetime(2026, 8, 12, 12, 0, tzinfo=timezone.utc),
    )

    assert saved.base_segments == {"呼音": "i", "主音": "ɛ̞", "末音": "n"}
    assert saved.review["base_segments"] == {
        "呼音": "i",
        "主音": "ɛ̞",
        "末音": "n",
    }


def test_apical_i_variants_are_saved_independently(
    copied_store: ErhuaFinalDraftStore,
) -> None:
    items = {item.final: item for item in copied_store.load_items()}
    back_note = str(items["_i_back"].review.get("note") or "")
    saved = copied_store.save_review(
        "_i_front",
        surface_segments=items["_i_front"].review["surface_segments"],
        note="舌尖前韵母独立复核。",
    )
    payload = json.loads(copied_store.draft_path.read_text(encoding="utf-8"))
    entry = next(
        entry
        for group in payload["finals"].values()
        for final, entry in group.items()
        if final == "_i"
    )

    assert saved.final == "_i_front"
    assert saved.display_final == "i[ɿ]"
    assert entry["three_segment_review_variants"]["apical_front"]["note"] == "舌尖前韵母独立复核。"
    assert str(
        (entry.get("three_segment_review_variants") or {})
        .get("apical_back", {})
        .get("note")
        or ""
    ) == back_note


def test_reviewed_requires_all_three_positions(
    copied_store: ErhuaFinalDraftStore,
) -> None:
    with pytest.raises(ValueError, match="都必须填写"):
        copied_store.save_review(
            "ao",
            surface_segments={
                "呼音": segment("ɑ"),
                "主音": segment(""),
                "末音": segment("ʊ", rhotic=True),
            },
        )


def test_deferred_may_preserve_partial_work_and_can_be_cleared(
    copied_store: ErhuaFinalDraftStore,
) -> None:
    item = copied_store.save_review(
        "ong",
        surface_segments={name: segment("") for name in SEGMENT_NAMES},
        decision="deferred",
        note="保留部分标注，等待继续核对。",
    )
    assert item.decision == "deferred"
    assert item.review["note"] == "保留部分标注，等待继续核对。"

    cleared = copied_store.clear_review("ong")
    assert cleared.decision == "pending"
    assert not cleared.review


def test_not_applicable_requires_reason(copied_store: ErhuaFinalDraftStore) -> None:
    with pytest.raises(ValueError, match="必须填写理由"):
        copied_store.save_review(
            "er",
            surface_segments={name: segment("") for name in SEGMENT_NAMES},
            decision="not_applicable",
        )


def test_display_markers_cannot_leak_back_into_quality(
    copied_store: ErhuaFinalDraftStore,
) -> None:
    with pytest.raises(ValueError, match="只能填写基础音质"):
        copied_store.save_review(
            "ao",
            surface_segments={
                "呼音": segment("ɑ"),
                "主音": segment("ɑ"),
                "末音": segment("ʊ˞", rhotic=True),
            },
        )
    assert render_surface_segment(segment("ə", rhotic=True)) == "ɚ"
    assert render_surface_segment(segment("ɘ̠", rhotic=True, nasalized=True)) == "ɘ̠̃˞"
    assert (
        render_surface_segment(
            segment("ɘ̠", rhotic=True, nasalized=True),
            notation="yime_combining_r",
        )
        == "ɘ̠᷊̃"
    )
    assert [f"U+{ord(char):04X}" for char in "ə᷊́"] == [
        "U+0259",
        "U+1DCA",
        "U+0301",
    ]


def test_legacy_display_ipa_migrates_to_parallel_features(
    copied_store: ErhuaFinalDraftStore,
) -> None:
    payload = json.loads(copied_store.draft_path.read_text(encoding="utf-8"))
    entry = next(
        entry
        for group in payload["finals"].values()
        for final, entry in group.items()
        if final == "ao"
    )
    review = entry["three_segment_review"]
    review["schema_version"] = 1
    review.pop("surface_segment_schema", None)
    review["surface_segments"] = {"呼音": "ɑ", "主音": "ɑ̃", "末音": "ʊͬ"}
    review["surface_ipa"] = "ɑɑ̃ʊͬ"
    review["rhotic_positions"] = []
    review["nasalized_positions"] = []
    copied_store.draft_path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    summary = copied_store.migrate_surface_segment_schema()
    migrated = next(item for item in copied_store.load_items() if item.final == "ao")

    assert summary["migrated_reviews"] == 1
    assert migrated.review["surface_segments"] == {
        "呼音": segment("ɑ"),
        "主音": segment("ɑ", nasalized=True),
        "末音": segment("ʊ", rhotic=True),
    }
    assert migrated.review["surface_ipa"] == "ɑɑ̃ʊ˞"
