"""Compatibility wrapper for the unified syllable analyzer implementation."""

from tools.syllable_analysis.ganyin_analyzer import GanyinAnalyzer


class YinjieAnalyzer(GanyinAnalyzer):
    """Backward-compatible public entrypoint for the syllable analyzer."""


__all__ = ["YinjieAnalyzer"]
