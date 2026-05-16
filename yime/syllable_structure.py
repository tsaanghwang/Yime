"""Legacy shim for the old syllable-structure helpers.

The real compatibility implementation now lives next to the retained
legacy pinyin reference-table rebuild chain.
"""

from yime.utils.legacy_pinyin_tables.syllable_structure import SyllableStructure

__all__ = ["SyllableStructure"]
