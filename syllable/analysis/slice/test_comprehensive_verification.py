import unittest

from comprehensive_verification import collect_verification_results


class TestComprehensiveVerification(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.results = collect_verification_results()

    def test_missing_ganyin_reasons(self):
        self.assertEqual(self.results['extra_ganyin'], [])
        self.assertEqual(self.results['mismatched_ganyin'], [])
        self.assertEqual(
            self.results['missing_by_status'],
            {
                '拼写规则导致缺失': ['iou', 'ue', 'uei', 'uen', 'ueng'],
                '当前导入过滤导致缺失': ['io'],
                '真异常缺失': [],
            },
        )

    def test_missing_ganyin_full_list(self):
        self.assertEqual(
            self.results['missing_ganyin'],
            [
                'io1', 'io2', 'io3', 'io4', 'io5',
                'iou1', 'iou2', 'iou3', 'iou4', 'iou5',
                'ue1', 'ue2', 'ue3', 'ue4', 'ue5',
                'uei1', 'uei2', 'uei3', 'uei4', 'uei5',
                'uen1', 'uen2', 'uen3', 'uen4', 'uen5',
                'ueng1', 'ueng2', 'ueng3', 'ueng4', 'ueng5',
            ],
        )

    def test_missing_ganyin_grouping(self):
        self.assertEqual(
            self.results['missing_by_final'],
            {
                'io': ['io1', 'io2', 'io3', 'io4', 'io5'],
                'iou': ['iou1', 'iou2', 'iou3', 'iou4', 'iou5'],
                'ue': ['ue1', 'ue2', 'ue3', 'ue4', 'ue5'],
                'uei': ['uei1', 'uei2', 'uei3', 'uei4', 'uei5'],
                'uen': ['uen1', 'uen2', 'uen3', 'uen4', 'uen5'],
                'ueng': ['ueng1', 'ueng2', 'ueng3', 'ueng4', 'ueng5'],
            },
        )


if __name__ == '__main__':
    unittest.main()
