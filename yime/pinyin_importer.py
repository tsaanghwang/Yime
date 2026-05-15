"""Legacy-compatible wrapper for rebuilding the 音元拼音 structure table.

This module is kept so older entrypoints that still import `yime.pinyin_importer`
continue to work, but the actual implementation now lives in
`yime.rebuild_yinyuan_structure_table`.

Current mainline rebuild chain:
- `source_pinyin.db -> prototype tables -> refresh_runtime_yime_codes`

This wrapper keeps the older `PinyinImporter` / `main()` surface while routing all
work through the strict, DB-backed structure-table rebuild implementation.
"""

from __future__ import annotations

from pathlib import Path

try:
    from rebuild_yinyuan_structure_table import PinyinImporter as _StrictPinyinImporter
    from rebuild_yinyuan_structure_table import main as _strict_main
except ModuleNotFoundError:
    from yime.rebuild_yinyuan_structure_table import PinyinImporter as _StrictPinyinImporter
    from yime.rebuild_yinyuan_structure_table import main as _strict_main


class PinyinImporter(_StrictPinyinImporter):
    """Compatibility facade over the strict structure-table rebuild importer."""

    def __init__(self, db_path: str | Path | None = None):
        super().__init__(db_path)

    def load_from_mapping_table(self):
        """Compatibility alias for the DB-backed mapping loader."""
        return self.load_mapping_rows_from_db()


def main() -> None:
    """Compatibility entrypoint delegating to the strict rebuild script."""
    _strict_main()


if __name__ == "__main__":
    main()
