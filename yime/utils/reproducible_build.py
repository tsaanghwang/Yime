"""Small helpers for byte-reproducible generated artifacts."""

from __future__ import annotations

import os
from datetime import UTC, date, datetime


def build_date() -> date:
    """Return the UTC build date, honoring the standard reproducible-build input."""

    source_date_epoch = os.environ.get("SOURCE_DATE_EPOCH")
    if source_date_epoch is None:
        return date.today()
    try:
        epoch = int(source_date_epoch)
    except ValueError as exc:
        raise ValueError("SOURCE_DATE_EPOCH must be an integer Unix timestamp") from exc
    return datetime.fromtimestamp(epoch, tz=UTC).date()


def build_date_text() -> str:
    return build_date().isoformat()
