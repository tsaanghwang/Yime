import unittest
from syllable_codec import interactive_yinjie as interactive_entry_module
from syllable_codec import yinjie_encoder as facade_yinjie_encoder
from syllable_codec.interactive_yinjie import interactive_encoder
from syllable.analysis.slice import yinjie_encoder as package_yinjie_encoder
from syllable.analysis.slice.interactive_yinjie_session import interactive_encoder as package_interactive_encoder
from syllable.analysis.slice.yinjie_api_manifest import (
    YINJIE_COMPOSITION_EXPORTS,
    YINJIE_FACADE_EXPORTS,
    YINJIE_INTERACTIVE_ENTRY_EXPORTS,
    YINJIE_IMPLEMENTATION_EXPORTS,
    YINJIE_ROOT_ENTRY_EXPORTS,
)


class TestYinjieEntryManifests(unittest.TestCase):
    def test_package_implementation_exports_match_manifest(self):
        self.assertEqual(package_yinjie_encoder.__all__, YINJIE_IMPLEMENTATION_EXPORTS)

    def test_facade_exports_match_api_manifest(self):
        self.assertEqual(facade_yinjie_encoder.__all__, YINJIE_ROOT_ENTRY_EXPORTS)

    def test_interactive_entry_exports_match_manifest(self):
        self.assertEqual(interactive_entry_module.__all__, YINJIE_INTERACTIVE_ENTRY_EXPORTS)

    def test_interactive_entry_facade_reexports_package_session(self):
        self.assertIs(interactive_entry_module.interactive_encoder, package_interactive_encoder)
        self.assertIs(interactive_encoder, package_interactive_encoder)

    def test_facade_manifest_extends_implementation_with_composition_exports(self):
        self.assertEqual(
            YINJIE_FACADE_EXPORTS,
            [*YINJIE_IMPLEMENTATION_EXPORTS, *YINJIE_COMPOSITION_EXPORTS],
        )

    def test_root_entry_manifest_matches_facade_exports(self):
        self.assertEqual(YINJIE_ROOT_ENTRY_EXPORTS, YINJIE_FACADE_EXPORTS)


if __name__ == '__main__':
    unittest.main()
