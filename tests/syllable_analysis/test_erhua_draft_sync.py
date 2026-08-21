from __future__ import annotations

from copy import deepcopy
from datetime import datetime, timezone
import json
from pathlib import Path
import shutil

from syllable.analysis.erhua_draft_sync import sync_erhua_draft_foundations
from syllable.analysis.erhua_final_review import ErhuaFinalDraftStore


ROOT = Path(__file__).resolve().parents[2]
DRAFT = ROOT / "external_data" / "tmp" / "final_styles_erhua_draft.json"
STYLES = ROOT / "syllable" / "yinyuan" / "final_styles.json"
DECOMPOSITION = (
    ROOT
    / "internal_data"
    / "yinyuan_derived"
    / "ganyin_to_pianyin_sequence.json"
)


def _entries(payload: dict) -> dict[str, dict]:
    return {
        final: entry
        for group in payload["finals"].values()
        for final, entry in group.items()
    }


def test_sync_updates_only_foundations_and_preserves_manual_erhua_work(
    tmp_path: Path,
) -> None:
    draft = tmp_path / "draft.json"
    styles = tmp_path / "final_styles.json"
    decomposition = tmp_path / "decomposition.json"
    shutil.copyfile(DRAFT, draft)
    shutil.copyfile(STYLES, styles)
    shutil.copyfile(DECOMPOSITION, decomposition)

    before_payload = json.loads(draft.read_text(encoding="utf-8"))
    for group in before_payload["finals"].values():
        group.pop("io", None)
    before_entries = _entries(before_payload)
    ao_before = deepcopy(before_entries["ao"])
    first_group = next(iter(before_payload["finals"].values()))
    first_group["obsolete"] = deepcopy(ao_before)
    draft.write_text(
        json.dumps(before_payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    style_payload = json.loads(styles.read_text(encoding="utf-8"))
    for group in style_payload["finals"].values():
        if "ao" in group:
            group["ao"]["ipa"] = "ɑTEST"
    styles.write_text(
        json.dumps(style_payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    decomposition_payload = json.loads(decomposition.read_text(encoding="utf-8"))
    for group in decomposition_payload.values():
        if "ao1" in group:
            group["ao1"]["主音"] = "ɑX˥"
    decomposition.write_text(
        json.dumps(decomposition_payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    result = sync_erhua_draft_foundations(
        draft_path=draft,
        final_styles_path=styles,
        decomposition_path=decomposition,
        now=datetime(2026, 8, 14, 10, 0, tzinfo=timezone.utc),
    )
    after_payload = json.loads(draft.read_text(encoding="utf-8"))
    after_entries = _entries(after_payload)
    ao_after = after_entries["ao"]

    assert result.actual_count == 42
    assert result.added == ("io",)
    assert result.archived == ("obsolete",)
    assert "ao" in result.ipa_changed
    assert "ao" in result.base_segments_changed
    assert "ao" in result.surface_review_required
    assert len(after_entries) == 42
    assert after_entries["io"]["erhua_review_status"] == "no_psc_source_pending_review"
    assert "three_segment_review" not in after_entries["io"]
    assert after_payload["archived_final_entries"]["obsolete"]["entry"] == ao_before

    assert ao_after["ipa"] == "ɑTEST"
    assert ao_after["base_foundation"]["segments"]["主音"] == "ɑX"
    assert ao_after["three_segment_review"]["base_segments"]["主音"] == "ɑX"
    for preserved in (
        "erhua_final",
        "erhua_review_status",
        "erhua_surface_class",
    ):
        assert ao_after.get(preserved) == ao_before.get(preserved)
    for preserved in (
        "decision",
        "surface_segments",
        "surface_ipa",
        "note",
        "revision",
        "updated_utc",
    ):
        assert ao_after["three_segment_review"][preserved] == ao_before[
            "three_segment_review"
        ][preserved]

    second = sync_erhua_draft_foundations(
        draft_path=draft,
        final_styles_path=styles,
        decomposition_path=decomposition,
    )
    assert second.changed is False


def test_real_draft_foundations_match_current_sources() -> None:
    result = sync_erhua_draft_foundations(write=False)
    assert result.changed is False
    assert result.actual_count == 42

    store = ErhuaFinalDraftStore(DRAFT, DECOMPOSITION)
    items = {item.final: item for item in store.load_items()}
    assert len(items) == 43
    assert items["ueng"].base_ipa == "uɤŋ"
    assert items["ueng"].base_segments == {"呼音": "u", "主音": "ɤ", "末音": "ŋ"}


def test_saving_review_acknowledges_foundation_change(tmp_path: Path) -> None:
    draft = tmp_path / "draft.json"
    shutil.copyfile(DRAFT, draft)
    payload = json.loads(draft.read_text(encoding="utf-8"))
    payload["draft_foundation_sync"]["surface_review_required"] = ["ao", "ueng"]
    draft.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    store = ErhuaFinalDraftStore(draft, DECOMPOSITION)
    item = {row.final: row for row in store.load_items()}["ao"]
    store.save_review("ao", surface_segments=item.review["surface_segments"])
    after = json.loads(draft.read_text(encoding="utf-8"))

    assert after["draft_foundation_sync"]["surface_review_required"] == ["ueng"]
