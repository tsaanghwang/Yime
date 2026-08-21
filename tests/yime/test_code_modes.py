import pytest

from yime.utils.code_modes import (
    YimeCodeMode,
    build_code_mode_record,
    code_mode_label,
    normalize_code_mode,
)


def test_build_code_mode_record_outputs_full_variable_and_shorthand_codes() -> None:
    metadata = {
        "A": {"quality_group": 1, "tone_level": "high"},
        "B": {"quality_group": 1, "tone_level": "mid"},
        "C": {"quality_group": 1, "tone_level": "low"},
    }

    record = build_code_mode_record(
        "XABC",
        ganyin_symbol_metadata=metadata,
    )

    assert record.full_code == "XABC"
    assert record.variable_code == "XABC"
    assert record.shorthand_code == "XAC"
    assert record.lookup_code(YimeCodeMode.FULL) == "XABC"
    assert record.lookup_code(YimeCodeMode.VARIABLE) == "XABC"
    assert record.lookup_code(YimeCodeMode.SHORTHAND) == "XAC"


def test_build_code_mode_record_keeps_nonvirtual_initial_in_shorthand() -> None:
    metadata = {
        "A": {"quality_group": 1, "tone_level": "high"},
        "B": {"quality_group": 1, "tone_level": "mid"},
        "C": {"quality_group": 1, "tone_level": "low"},
    }

    record = build_code_mode_record(
        "NABC",
        ganyin_symbol_metadata=metadata,
    )

    assert record.variable_code == "NABC"
    assert record.shorthand_code == "NAC"


def test_build_code_mode_record_rejects_incomplete_full_syllable() -> None:
    with pytest.raises(ValueError, match="divisible by 4"):
        build_code_mode_record("ABC")


def test_normalize_code_mode_defaults_to_variable() -> None:
    assert normalize_code_mode("等长模式") == YimeCodeMode.FULL
    assert normalize_code_mode("省键") == YimeCodeMode.SHORTHAND
    assert normalize_code_mode("unknown") == YimeCodeMode.VARIABLE
    assert code_mode_label("shorthand") == "省键模式"
