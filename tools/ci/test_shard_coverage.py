import copy
import unittest
from verify_shard_coverage import EXPECTED, verify


class CoverageTests(unittest.TestCase):
    def records(self):
        names = ['a', 'b', 'c', 'd', 'e', 'f', 'g']
        return [dict(schema_version='yime-ci-test-shard-v1', suite=suite, shell=shell,
                     index=index, count=3, all_names=names.copy(), executed_names=names[index::3],
                     passed=True, installed_acceptance_passed=False, commit='source', source_sha256='hash')
                for suite, shell, index in sorted(EXPECTED)]

    def check(self, records):
        return verify(records, 'source', {'real-rime': 'hash', 'installer-transaction': 'hash'})

    def test_complete_union_passes_without_installed_acceptance(self):
        result = self.check(self.records())
        self.assertTrue(result['ci_test_coverage_passed'])
        self.assertFalse(result['installed_acceptance_passed'])
        self.assertEqual(set(result['test_counts'].values()), {7})

    def test_missing_duplicate_failed_and_stale_shards_are_rejected(self):
        records = self.records()
        for i in range(len(records)):
            with self.subTest(missing=i), self.assertRaises(ValueError):
                self.check(records[:i] + records[i+1:])
        with self.assertRaises(ValueError):
            self.check(records + [records[0]])
        for field, value in [('passed', False), ('passed', 'true'), ('commit', 'old'),
                             ('source_sha256', 'old'), ('count', 1), ('index', True),
                             ('installed_acceptance_passed', True), ('all_names', ['a','b','c']),
                             ('executed_names', []), ('executed_names', ['a','a'])]:
            changed = copy.deepcopy(records); changed[0][field] = value
            with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                self.check(changed)

    def test_individually_valid_but_different_inventories_are_rejected(self):
        records = self.records()
        r = records[0]; r['all_names'] = list(reversed(r['all_names']))
        r['executed_names'] = r['all_names'][r['index']::3]
        with self.assertRaises(ValueError):
            self.check(records)


if __name__ == '__main__':
    unittest.main()
