"""Additional process-identity contracts; separate from the pinned legacy test gate."""
from pathlib import Path
import unittest
from unittest.mock import patch
import windows_job_once as jobs
from test_windows_job_once import Backend

class JobIdentityTests(unittest.TestCase):
    def run_backend(self, backend, callback=None):
        with patch.object(jobs.time, 'monotonic', side_effect=range(0, 1000, 10)), patch.object(jobs.time, 'sleep'):
            return jobs.run_once([str(Path('/fake-owned-helper').resolve())], '.', 'out', 'err', 1, backend, on_root_created=callback)

    def test_receipt_callback_before_resume_and_same_identity(self):
        b = Backend()
        seen = []
        def save(identity):
            self.assertEqual(b.calls, ['assign', 'identity'])
            seen.append(dict(identity))
            identity['pid'] = 999  # callback cannot mutate returned process proof
        result = self.run_backend(b, save)
        self.assertEqual(result['rootIdentity'], seen[0])
        self.assertEqual(result['rootIdentity']['pid'], 42)

    def test_callback_failure_never_resumes_or_claims_tree_stop(self):
        b = Backend()
        def failed(identity): raise RuntimeError('receipt persistence failed')
        result = self.run_backend(b, failed)
        self.assertEqual(b.calls, ['assign', 'identity', 'close'])
        self.assertFalse(result['started'])
        self.assertFalse(result['treeStopped'])
        self.assertIsNotNone(result['rootIdentity'])
        self.assertIsNone(result['exitCode'])

    def test_identity_failure_never_resumes(self):
        b = Backend(fail='identity')
        result = self.run_backend(b)
        self.assertEqual(b.calls, ['assign', 'identity', 'close'])
        self.assertIsNone(result['rootIdentity'])
        self.assertFalse(result['started'])


if __name__ == '__main__': unittest.main()
