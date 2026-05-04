"""Helpers for normalizing keyboard modifier state across input paths."""

from __future__ import annotations


def is_alt_gr_active(states: dict[str, bool]) -> bool:
    """Treat Right Alt and Ctrl+Alt as the AltGr layer on Windows layouts."""

    return bool(states.get("alt_r") or (states.get("ctrl") and states.get("alt")))
