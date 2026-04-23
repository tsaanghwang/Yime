import unittest

from verify_classification import collect_classification_results


class TestVerifyClassification(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.results = collect_classification_results()

    def test_new_finals_have_expected_categories(self):
        self.assertEqual(self.results['mismatches'], {})

    def test_expected_categories_snapshot(self):
        self.assertEqual(
            self.results['actual_categories'],
            {
                'ian': '三质干音',
                'iong': '三质干音',
                'iu': '三质干音',
                'ong': '三质干音',
                'ua': '后长干音',
                'uai': '三质干音',
                'ue': '后长干音',
                'ui': '三质干音',
                'un': '三质干音',
                'v': '单质干音',
                'van': '三质干音',
                've': '后长干音',
            },
        )

    def test_category_statistics_snapshot(self):
        self.assertEqual(self.results['total'], 50)
        self.assertEqual(
            {category: stats['count'] for category, stats in self.results['category_stats'].items()},
            {
                '单质韵母': 13,
                '前长韵母': 8,
                '后长韵母': 8,
                '三质韵母': 21,
            },
        )


if __name__ == '__main__':
    unittest.main()
