import unittest

from syllable.analysis.syllable_analyzer import _remove_tone_from_ganyin
from tools.syllable_analysis.verify_classification import collect_classification_results


class TestVerifyClassification(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.results = collect_classification_results()

    def test_new_finals_have_expected_categories(self):
        self.assertEqual(self.results['mismatches'], {})

    def test_umlaut_survives_numeric_and_marked_tone_removal(self):
        self.assertEqual(_remove_tone_from_ganyin('üe1'), 'üe')
        self.assertEqual(_remove_tone_from_ganyin('üè'), 'üe')

    def test_expected_categories_snapshot(self):
        self.assertEqual(
            self.results['actual_categories'],
            {
                'ian': '三质干音',
                'iong': '三质干音',
                'iou': '三质干音',
                'ong': '三质干音',
                'ua': '后长干音',
                'uai': '三质干音',
                'uei': '三质干音',
                'uen': '三质干音',
                'ueng': '三质干音',
                'üe': '后长干音',
                'üan': '三质干音',
                'ün': '三质干音',
            },
        )

    def test_category_statistics_snapshot(self):
        self.assertEqual(self.results['total'], 42)
        self.assertEqual(
            {category: stats['count'] for category, stats in self.results['category_stats'].items()},
            {
                '单质韵母': 12,
                '前长韵母': 8,
                '后长韵母': 6,
                '三质韵母': 16,
            },
        )


if __name__ == '__main__':
    unittest.main()
