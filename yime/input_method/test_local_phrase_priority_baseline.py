from __future__ import annotations

import json
from pathlib import Path

import pytest

from yime.input_method.core.decoders import (
    RuntimeCandidateDecoder,
    SQLiteRuntimeCandidateDecoder,
)


REPO_ROOT = Path(__file__).resolve().parents[2]
APP_DIR = REPO_ROOT / "yime"
SAMPLES_PATH = REPO_ROOT / "internal_data" / "local_phrase_priority_samples.json"
RULES_PATH = REPO_ROOT / "internal_data" / "local_phrase_priority_rules.json"


def _load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _build_expected_top5_by_pinyin() -> dict[str, list[str]]:
    samples_payload = _load_json(SAMPLES_PATH)
    rules_payload = _load_json(RULES_PATH)

    sample_map = {
        str(bucket["lookup_pinyin_tone"]): [str(text) for text in bucket["sample_phrases"]]
        for bucket in samples_payload.get("buckets", [])
    }
    rule_map = {
        str(rule["lookup_pinyin_tone"]): [str(target["text"]) for target in rule.get("targets", [])]
        for rule in rules_payload.get("rules", [])
    }

    expected: dict[str, list[str]] = {}
    for pinyin_tone, sample_phrases in sample_map.items():
        assert len(sample_phrases) >= 5, f"样本集 {pinyin_tone} 至少应提供 5 条词语样本"
        rule_targets = rule_map.get(pinyin_tone)
        assert rule_targets, f"规则文件缺少 {pinyin_tone} 的局部词语优先规则"
        assert len(rule_targets) >= 5, f"规则文件 {pinyin_tone} 至少应提供 5 条定点规则"
        missing_targets = [text for text in rule_targets[:5] if text not in sample_phrases]
        assert not missing_targets, (
            f"样本集未覆盖规则目标: {pinyin_tone} missing={missing_targets} sample_pool={sample_phrases}"
        )
        expected[pinyin_tone] = rule_targets[:5]
    return expected


EXPECTED_TOP5_BY_PINYIN = _build_expected_top5_by_pinyin()


@pytest.fixture(scope="module")
def runtime_decoder() -> RuntimeCandidateDecoder:
    return RuntimeCandidateDecoder(APP_DIR)


@pytest.fixture(scope="module")
def sqlite_decoder() -> SQLiteRuntimeCandidateDecoder:
    return SQLiteRuntimeCandidateDecoder(APP_DIR)


@pytest.mark.parametrize(
    ("decoder_fixture", "lookup_pinyin_tone", "expected_top5"),
    [
        (decoder_fixture, lookup_pinyin_tone, expected_top5)
        for decoder_fixture in ("runtime_decoder", "sqlite_decoder")
        for lookup_pinyin_tone, expected_top5 in EXPECTED_TOP5_BY_PINYIN.items()
    ],
)
def test_local_phrase_priority_sample_hits_top5(
    request: pytest.FixtureRequest,
    decoder_fixture: str,
    lookup_pinyin_tone: str,
    expected_top5: list[str],
) -> None:
    decoder = request.getfixturevalue(decoder_fixture)
    canonical_code = decoder.pinyin_to_canonical[lookup_pinyin_tone]

    canonical, active, _pinyin, candidates, status = decoder.decode_text(canonical_code)

    assert canonical == canonical_code
    assert active == canonical_code
    assert candidates[:5] == expected_top5, (
        f"{decoder_fixture} {lookup_pinyin_tone} top5 mismatch: actual={candidates[:5]} expected={expected_top5}"
    )
    assert "找到" in status
