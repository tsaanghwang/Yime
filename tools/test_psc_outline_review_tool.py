import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from psc_outline_review_tool import (
    DEFAULT_DATABASE,
    INTERNAL_PSC_ROOT,
    ReviewItem,
    build_argument_parser,
    resolve_image_path,
)


class PortablePscOutlineReviewToolTests(unittest.TestCase):
    def test_default_database_is_the_internal_snapshot(self) -> None:
        arguments = build_argument_parser().parse_args([])
        self.assertEqual(arguments.database, DEFAULT_DATABASE)
        self.assertEqual(DEFAULT_DATABASE.parent, INTERNAL_PSC_ROOT)
        self.assertTrue(DEFAULT_DATABASE.is_file())

    def test_absolute_stored_image_path_cannot_restore_machine_dependency(self) -> None:
        item = ReviewItem(
            document_id=1,
            entry_id=1,
            table_number=1,
            source_index=1,
            page_number=1,
            column_number=1,
            hanzi="",
            pinyin="",
            raw_text="",
            index_origin="ocr",
            minimum_confidence=None,
            evidence_span_ids=[],
            issue_summary="",
            image_path=r"C:\foreign\pages\page-0001.png",
            decision="pending",
            corrected_hanzi="",
            corrected_pinyin="",
            review_note="",
        )
        resolved = resolve_image_path(item, DEFAULT_DATABASE, None)
        self.assertEqual(
            resolved,
            (INTERNAL_PSC_ROOT / "pages" / "page-0001.png").resolve(),
        )
        self.assertTrue(resolved.is_file())

    def test_relative_stored_image_path_resolves_from_database(self) -> None:
        item = ReviewItem(
            document_id=1,
            entry_id=1,
            table_number=1,
            source_index=1,
            page_number=2,
            column_number=1,
            hanzi="",
            pinyin="",
            raw_text="",
            index_origin="ocr",
            minimum_confidence=None,
            evidence_span_ids=[],
            issue_summary="",
            image_path="pages/page-0002.png",
            decision="pending",
            corrected_hanzi="",
            corrected_pinyin="",
            review_note="",
        )
        resolved = resolve_image_path(item, DEFAULT_DATABASE, None)
        self.assertEqual(
            resolved,
            (INTERNAL_PSC_ROOT / "pages" / "page-0002.png").resolve(),
        )


if __name__ == "__main__":
    unittest.main()
