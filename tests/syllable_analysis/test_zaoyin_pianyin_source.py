import json
from pathlib import Path

from syllable.analysis.zaoyin_pianyin_source import (
    DEFAULT_REGISTRY_PATH,
    DEFAULT_SOURCE_PATH,
    audit_zaoyin_pianyin_source,
    build_proposed_registry,
    runtime_compatibility_aliases,
)


def test_structured_zaoyin_source_has_27_complete_entries() -> None:
    result = audit_zaoyin_pianyin_source()

    assert result.passed, result.issues
    assert result.entry_count == 27
    assert result.articulatory_group_count == 7
    assert result.memory_sequence_count == 27
    assert result.runtime_entry_count == 27
    assert result.deferred_entry_count == 0
    assert result.compatibility_alias_count == 0


def test_articulatory_memory_order_has_six_groups_of_four_then_three_remainders() -> None:
    source = json.loads(DEFAULT_SOURCE_PATH.read_text(encoding="utf-8"))
    groups = source["articulatory_memory_groups"]["groups"]

    assert [len(group["members"]) for group in groups] == [4, 4, 4, 4, 4, 4, 3]
    assert [number for group in groups for number in group["memory_numbers"]] == list(
        range(1, 28)
    )
    assert [member for group in groups for member in group["members"]] == [
        "b", "p", "f", "m",
        "d", "t", "l", "n",
        "g", "k", "h", "ŋ",
        "z", "c", "s", "a_apical",
        "zh", "ch", "sh", "r",
        "j", "q", "x", "y",
        "'", "w", "ɥ",
    ]


def test_last_memory_group_is_a_mnemonic_tail_not_a_complete_class() -> None:
    source = json.loads(DEFAULT_SOURCE_PATH.read_text(encoding="utf-8"))
    group = source["articulatory_memory_groups"]["groups"][-1]

    assert group["name"] == "后置组三项"
    assert group["group_kind"] == "mnemonic_tail"
    assert group["members"] == ["'", "w", "ɥ"]
    assert group["member_descriptions"] == {
        "'": "舌位为非高的乐音前的虚首音",
        "w": "音质为 [u] 的高乐音前的虚首音",
        "ɥ": "音质为 [y] 的高乐音前的虚首音",
    }


def test_virtual_initial_role_crosses_memory_group_boundary() -> None:
    source = json.loads(DEFAULT_SOURCE_PATH.read_text(encoding="utf-8"))
    entries = source["entries"]
    virtual_initials = {
        label
        for label, entry in entries.items()
        if entry.get("structural_role") == "virtual_initial"
    }

    assert virtual_initials == {"'", "y", "w", "ɥ"}
    assert source["articulatory_memory_groups"]["groups"][5]["members"][-1] == "y"
    assert entries["y"]["ipa"] == ["j"]


def test_memory_order_does_not_renumber_stable_yinyuan_ids() -> None:
    source = json.loads(DEFAULT_SOURCE_PATH.read_text(encoding="utf-8"))

    assert source["entries"]["ŋ"]["yinyuan_id"] == "N26"
    assert source["entries"]["a_apical"]["yinyuan_id"] == "N27"
    assert source["entries"]["y"]["yinyuan_id"] == "N23"
    assert source["entries"]["'"]["yinyuan_id"] == "N12"


def test_a_apical_is_front_only_and_retroflex_stays_on_r() -> None:
    source = json.loads(DEFAULT_SOURCE_PATH.read_text(encoding="utf-8"))
    entry = source["entries"]["a_apical"]

    assert entry["yinyuan_id"] == "N27"
    assert entry["ipa"] == ["ɹ", "z"]
    assert entry["conditions"]["conditional_realizations"] == [
        {
            "when": {"left_surface_final": ["ɿ"]},
            "surface_forms": ["ɹa", "za"],
        }
    ]
    assert source["entries"]["r"]["ipa"] == ["ɻ", "ʐ"]


def test_source_rejects_collapsed_a_apical_realizations(tmp_path: Path) -> None:
    source = json.loads(DEFAULT_SOURCE_PATH.read_text(encoding="utf-8"))
    source["entries"]["a_apical"]["conditions"]["conditional_realizations"] = []
    source_path = tmp_path / "zaoyin_pianyin.json"
    source_path.write_text(json.dumps(source, ensure_ascii=False), encoding="utf-8")

    result = audit_zaoyin_pianyin_source(source_path)

    assert not result.passed
    assert any("ɿ 后的 ɹa/za" in issue for issue in result.issues)


def test_source_rejects_duplicate_member_in_memory_groups(tmp_path: Path) -> None:
    source = json.loads(DEFAULT_SOURCE_PATH.read_text(encoding="utf-8"))
    source["articulatory_memory_groups"]["groups"][2]["members"][3] = "h"
    source_path = tmp_path / "zaoyin_pianyin.json"
    source_path.write_text(json.dumps(source, ensure_ascii=False), encoding="utf-8")

    result = audit_zaoyin_pianyin_source(source_path)

    assert not result.passed
    assert any("重复成员" in issue for issue in result.issues)


def test_contextual_entries_restore_to_canonical_pinyin() -> None:
    source = json.loads(DEFAULT_SOURCE_PATH.read_text(encoding="utf-8"))

    assert source["entries"]["ɥ"]["canonical_restore"] == {
        "strategy": "yu_family_orthography",
        "target_pinyin_initial": "y",
    }
    for label in ("ŋ", "a_apical"):
        assert source["entries"][label]["activation"] == "runtime_compatible"
        assert source["entries"][label]["canonical_restore"] == {
            "strategy": "particle_a_zero_initial",
            "target_pinyin_initial": "'",
        }


def test_yu_family_no_longer_uses_compatibility_projection() -> None:
    assert runtime_compatibility_aliases() == {}


def test_proposal_has_27_entries_without_changing_live_registry() -> None:
    before = DEFAULT_REGISTRY_PATH.read_bytes()
    proposal = build_proposed_registry()
    after = DEFAULT_REGISTRY_PATH.read_bytes()

    assert before == after
    assert len(proposal["entries"]) == 27
    assert proposal["entries"]["ɥ"]["yinyuan_id"] == "N25"
    assert proposal["entries"]["ŋ"]["yinyuan_id"] == "N26"
    assert proposal["entries"]["a_apical"]["yinyuan_id"] == "N27"
    assert proposal["entries"]["ɥ"]["activation"] == "runtime_compatible"


def test_source_rejects_runtime_demotion_without_registry_migration(tmp_path: Path) -> None:
    source = json.loads(DEFAULT_SOURCE_PATH.read_text(encoding="utf-8"))
    source["entries"]["ɥ"]["activation"] = "research_only"
    source["runtime_projection"]["active_yinyuan_ids"].remove("N25")
    source["runtime_projection"]["deferred_yinyuan_ids"].append("N25")
    source_path = tmp_path / "zaoyin_pianyin.json"
    source_path.write_text(json.dumps(source, ensure_ascii=False), encoding="utf-8")

    result = audit_zaoyin_pianyin_source(source_path)

    assert not result.passed
    assert any("延后登记" in issue or "稳定登记表" in issue for issue in result.issues)
