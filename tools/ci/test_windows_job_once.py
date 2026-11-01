"""Portable state-machine tests; do not execute or certify Windows Job APIs."""
from pathlib import Path
import unittest
from unittest.mock import patch

import windows_job_once as jobs


class Backend:
    def __init__(self, active=0, stopped_after_terminate=True, fail=None, exit_code=0):
        self.active = active
        self.stopped_after_terminate = stopped_after_terminate
        self.fail = fail
        self.code = exit_code
        self.calls = []

    def step(self, name):
        self.calls.append(name)
        if self.fail == name:
            raise OSError(5, 'injected failure')

    def start_suspended_assigned(self): self.step('assign')
    def root_identity(self):
        self.step('identity')
        return {'pid': 42, 'creationFileTime': '133000000000000000'}
    def resume(self): self.step('resume')
    def active_processes(self):
        self.step('query')
        return self.active
    def terminate(self):
        self.step('terminate')
        if self.stopped_after_terminate: self.active = 0
    def exit_code(self):
        self.step('exit')
        return self.code
    def close(self): self.step('close')


class JobOnceTests(unittest.TestCase):
    def run_backend(self, backend, callback=None):
        # Advancing fake clock avoids actual sleeps and Windows process launch.
        with patch.object(jobs.time, 'monotonic', side_effect=range(0, 1000, 10)), patch.object(jobs.time, 'sleep'):
            return jobs.run_once([str(Path('/fake-owned-helper').resolve())], '.', 'out', 'err', 1, backend, on_root_created=callback)

    def test_zero_and_nonzero_exit_preserved(self):
        for code in (0, 3, 1):
            b=Backend(exit_code=code)
            r=self.run_backend(b)
            self.assertEqual((r['started'], r['treeStopped'], r['exitCode'], r['timedOut']), (True, True, code, False))
            self.assertEqual(b.calls[:3], ['assign', 'identity', 'resume'])
            self.assertEqual(b.calls[-1], 'close')
            self.assertNotIn('terminate', b.calls)

    def test_timeout_once_with_verified_tree_stop(self):
        b=Backend(active=1, exit_code=124)
        r=self.run_backend(b)
        self.assertTrue(r['timedOut']); self.assertTrue(r['treeStopped'])
        self.assertEqual(r['exitCode'], 124)
        self.assertEqual(b.calls.count('terminate'), 1)
        self.assertEqual(b.calls.count('resume'), 1)

    def test_timeout_without_quiescence_never_proves_exit(self):
        b=Backend(active=1, stopped_after_terminate=False)
        r=self.run_backend(b)
        self.assertTrue(r['timedOut']); self.assertFalse(r['treeStopped'])
        self.assertIsNone(r['exitCode']); self.assertNotIn('exit', b.calls)
        self.assertEqual(b.calls.count('terminate'), 1)
        self.assertEqual(b.calls[-1], 'close')

    def test_ownership_failure_does_not_resume_or_retry(self):
        b=Backend(fail='assign')
        r=self.run_backend(b)
        self.assertEqual(b.calls, ['assign', 'close'])
        self.assertFalse(r['started']); self.assertFalse(r['treeStopped'])
        self.assertEqual(r['errorCode'], 5)

    def test_query_failure_does_not_claim_quiescence(self):
        b=Backend(fail='query')
        r=self.run_backend(b)
        self.assertTrue(r['started']); self.assertFalse(r['treeStopped'])
        self.assertIsNone(r['exitCode']); self.assertEqual(r['errorCode'], 5)
        self.assertEqual(b.calls[-1], 'close')

    def test_invalid_command_or_deadline_never_starts(self):
        for command, timeout in (([], 1), (['relative.exe'], 1), ([str(Path('/abs').resolve())], 0)):
            b=Backend()
            with self.assertRaises(ValueError): jobs.run_once(command, '.', 'out', 'err', timeout, b)
            self.assertEqual(b.calls, [])


if __name__ == '__main__': unittest.main()
