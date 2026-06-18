from __future__ import annotations

from yime.utils.runtime_candidates_export import normalize_sort_weight_for_export


def test_normalize_sort_weight_for_export_rounds_binary_tail() -> None:
    assert normalize_sort_weight_for_export(3.7152000000000003) == 3.7152


def test_normalize_sort_weight_for_export_keeps_integer_weight_stable() -> None:
    assert normalize_sort_weight_for_export(120) == 120.0
