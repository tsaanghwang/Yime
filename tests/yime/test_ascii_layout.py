import json
from pathlib import Path

import pytest

from tools.generate_ascii_layout import generated_payloads
from yime.utils.yinyuan_id_chain import (
    encode_numeric_pinyin_to_yinyuan_ids, load_active_yinyuan_id_to_layout_key,
    load_disabled_yinyuan_ids, load_yinyuan_id_to_layout_key, yinyuan_ids_to_layout_keys,
    load_input_id_to_layout_key, load_erhua_id_to_layout_key, load_erhua_input_registry,
    load_erhua_key_class_to_layout_key,
)

ROOT = Path(__file__).resolve().parents[2]


def test_canonical_60_and_input_75_are_separate_unique_inventories():
    base = load_yinyuan_id_to_layout_key(ROOT)
    active = load_active_yinyuan_id_to_layout_key(ROOT)
    inputs = load_input_id_to_layout_key(ROOT)
    assert len(base) == len(active) == len(set(base.values())) == 60
    assert len(inputs) == len(set(inputs.values())) == 75
    assert load_disabled_yinyuan_ids(ROOT) == set()
    for owner, enabled, key, upper in (("M28", "M25", "T", "B"), ("M29", "M26", "L", "M"), ("M30", "M27", "N", "P")):
        assert base[owner] == key and base[enabled] == upper
    assert base["N12"] == "'" and base["N26"] == "`"
    assert not set("0123456789") & set(inputs.values())


@pytest.mark.parametrize("pinyin", ["hm5", "m1", "m2", "m4"])
def test_previously_disabled_canonical_syllables_are_enabled(pinyin):
    ids = encode_numeric_pinyin_to_yinyuan_ids(pinyin)
    assert len(yinyuan_ids_to_layout_keys(ids)) == 4
    assert set(ids) & {"M25", "M26", "M27"}


def test_erhua_projection_joins_reviewed_sound_metadata_not_base_catalog():
    registry = load_erhua_input_registry(ROOT)
    mapping = load_erhua_id_to_layout_key(ROOT)
    classes = load_erhua_key_class_to_layout_key(ROOT)
    assert len(registry) == len(mapping) == 15
    assert len(classes) == 18
    for identifier, unit in registry.items():
        assert classes[unit["key_class_id"]] == mapping[identifier]
        assert unit["tone_grade"] in ("high", "mid", "low")
    assert classes["ERHUA-KEY-HIGH"] == "!"
    assert mapping["R04"] == "{" and mapping["R10"] == "["
    assert not set(registry) & set(load_yinyuan_id_to_layout_key(ROOT))


def test_case_sensitive_ansi_projection():
    assert yinyuan_ids_to_layout_keys(encode_numeric_pinyin_to_yinyuan_ids("ba1")) == "bAAA"
    assert yinyuan_ids_to_layout_keys(("M10", "M12")) == "Aa"


def test_generated_runtime_projection_is_current():
    for path, content in generated_payloads(ROOT).items():
        assert (ROOT / path).read_text(encoding="utf-8") == content, str(path)


def test_handoff_digest_includes_derived_carriers_without_changing_legacy_shape(tmp_path):
    from tools.lexicon.promote_handoff_target import _layout_digest
    from tools.lexicon.verify_target_lock import _layout_projection_digest
    from yime.utils.yinyuan_id_chain import layout_projection_digest
    payload = json.loads((ROOT / "go-backend/input_methods/yime/data/yime_yinyuan_layout.json").read_text(encoding="utf-8"))
    target = tmp_path / "layout.json"
    target.write_text(json.dumps(payload), encoding="utf-8")
    digest = layout_projection_digest(ROOT)
    assert _layout_digest(target) == _layout_projection_digest(target) == digest
    payload["input_id_to_key"]["R04"], payload["input_id_to_key"]["R05"] = payload["input_id_to_key"]["R05"], payload["input_id_to_key"]["R04"]
    target.write_text(json.dumps(payload), encoding="utf-8")
    assert _layout_digest(target) == _layout_projection_digest(target) != digest
