from __future__ import annotations

from datetime import date

import pytest

from yime.utils.reproducible_build import build_date


def test_build_date_uses_source_date_epoch_in_utc(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("SOURCE_DATE_EPOCH", "1787270400")

    assert build_date() == date(2026, 8, 21)


def test_build_date_rejects_invalid_source_date_epoch(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("SOURCE_DATE_EPOCH", "not-a-timestamp")

    with pytest.raises(ValueError, match="integer Unix timestamp"):
        build_date()
