import json
from pathlib import Path

import pytest

from tools.generate_ascii_layout import generated_payloads
from yime.utils.yinyuan_id_chain import (
    DisabledYinyuanError, encode_numeric_pinyin_to_yinyuan_ids,
    load_active_yinyuan_id_to_layout_key, load_disabled_yinyuan_ids,
    load_yinyuan_id_to_layout_key, yinyuan_ids_to_layout_keys,
)

ROOT = Path(__file__).resolve().parents[2]


def test_inventory_active_projection_and_shared_reservations():
    all_ids = load_yinyuan_id_to_layout_key(ROOT)
    active = load_active_yinyuan_id_to_layout_key(ROOT)
    assert len(all_ids) == 60 and len(active) == len(set(active.values())) == 57
    assert load_disabled_yinyuan_ids(ROOT) == {"M25", "M26", "M27"}
    for owner, reserved, key in (("M28", "M25", "["), ("M29", "M26", "N"), ("M30", "M27", "]")):
        assert all_ids[owner] == all_ids[reserved] == key
        assert reserved not in active
    assert active["N12"] == "'" and active["N26"] == "Q"
    assert not set("123456789!@#$%^&*(") & set(active.values())


@pytest.mark.parametrize("pinyin", ["hm5", "m1", "m2", "m4"])
def test_disabled_semantic_syllables_fail_before_projection(pinyin):
    ids = encode_numeric_pinyin_to_yinyuan_ids(pinyin)
    with pytest.raises(DisabledYinyuanError):
        yinyuan_ids_to_layout_keys(ids)


def test_case_sensitive_ansi_projection():
    assert yinyuan_ids_to_layout_keys(encode_numeric_pinyin_to_yinyuan_ids("ba1")) == "bAAA"
    assert yinyuan_ids_to_layout_keys(("M10", "M12")) == "Aa"


def test_generated_runtime_projection_is_current():
    for path, content in generated_payloads(ROOT).items():
        assert (ROOT / path).read_text(encoding="utf-8") == content, str(path)
