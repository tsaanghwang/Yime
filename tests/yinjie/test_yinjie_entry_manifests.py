import unittest

from syllable.analysis import interactive_yinjie_session as interactive_entry_module
from syllable.analysis import yinjie_composition as package_yinjie_composition
from syllable.analysis import yinjie_encoder as package_yinjie_encoder
from syllable.analysis.interactive_yinjie_session import interactive_encoder
from syllable.analysis.yinjie_api_manifest import (
    YINJIE_COMPOSITION_EXPORTS,
    YINJIE_FACADE_EXPORTS,
    YINJIE_INTERACTIVE_ENTRY_EXPORTS,
    YINJIE_IMPLEMENTATION_EXPORTS,
)


class TestYinjieEntryManifests(unittest.TestCase):
    def test_package_implementation_exports_match_manifest(self):
        self.assertEqual(package_yinjie_encoder.__all__, YINJIE_IMPLEMENTATION_EXPORTS)

    def test_composition_exports_match_manifest(self):
        self.assertEqual(package_yinjie_composition.__all__, YINJIE_COMPOSITION_EXPORTS)

    def test_interactive_entry_exports_match_manifest(self):
        self.assertEqual(interactive_entry_module.__all__, YINJIE_INTERACTIVE_ENTRY_EXPORTS)

    def test_facade_manifest_extends_implementation_with_composition_exports(self):
        self.assertEqual(
            YINJIE_FACADE_EXPORTS,
            [*YINJIE_IMPLEMENTATION_EXPORTS, *YINJIE_COMPOSITION_EXPORTS],
        )

    def test_interactive_session_exposes_encoder(self):
        self.assertIsNotNone(interactive_encoder)


if __name__ == "__main__":
    unittest.main()
