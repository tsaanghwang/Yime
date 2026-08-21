from __future__ import annotations

import json
from pathlib import Path

import pytest

from syllable.codec.neutral_tone_encoding import (
    NeutralToneEncodingPolicy,
    load_neutral_tone_exceptions,
)
from syllable.codec.yinjie_encoder import YinjieEncoder, YinjieEncodingError


INVENTORY_PATH = Path(
    "internal_data/pinyin_source_db/lexicon_exports/pinyin_normalized.json"
)
CODEBOOK_PATH = Path("syllable/codec/yinjie_code.json")


def test_current_neutral_inventory_splits_into_regular_and_reviewed_routes() -> None:
    inventory = json.loads(INVENTORY_PATH.read_text(encoding="utf-8"))
    policy = NeutralToneEncodingPolicy(inventory)
    resolutions = [
        policy.resolve(syllable)
        for syllable in inventory
        if syllable.endswith("5")
    ]

    assert len(resolutions) == 306
    assert sum(item.kind == "regular" for item in resolutions) == 303
    assert {
        item.syllable
        for item in resolutions
        if item.kind == "special_exception"
    } == {"hm5", "hng5", "lo5"}
    assert all(item.admitted for item in resolutions)


def test_neutral_exception_registry_contains_no_code_or_layout_mapping() -> None:
    exceptions = load_neutral_tone_exceptions()

    assert set(exceptions) == {"hm5", "hng5", "lo5"}
    payload = json.loads(
        Path(
            "internal_data/pinyin_source_db/neutral_tone_encoding_exceptions.json"
        ).read_text(encoding="utf-8")
    )
    serialized = json.dumps(payload, ensure_ascii=False)
    for prohibited in ("yinyuan_ids", "symbol_code", "yime_code", "layout_key", "vk_key"):
        assert f'"{prohibited}"' not in serialized


@pytest.mark.parametrize("syllable", ["lai5", "qiao5", "chuo5", "hm5", "hng5", "lo5"])
def test_neutral_routes_keep_the_existing_formal_encoding(syllable: str) -> None:
    inventory = json.loads(INVENTORY_PATH.read_text(encoding="utf-8"))
    codebook = json.loads(CODEBOOK_PATH.read_text(encoding="utf-8"))
    encoder = YinjieEncoder()

    resolution = encoder.resolve_neutral_tone(syllable, list(inventory))

    assert resolution.admitted
    assert encoder.encode_single_yinjie(syllable) == codebook[syllable]


def test_batch_inventory_rejects_unreviewed_neutral_only_form() -> None:
    encoder = YinjieEncoder()

    with pytest.raises(
        YinjieEncodingError,
        match="既无一至四声常规家族，也未登记为特殊例外",
    ):
        encoder.validate_neutral_tone_inventory(["made5"])
