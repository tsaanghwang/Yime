"""Actual isolated Windows process-tree checks, never simulated PS mutation."""
import os
from pathlib import Path
import sys
import tempfile
import unittest
import windows_job_once as job


@unittest.skipUnless(os.name == 'nt', 'actual Windows Job Object gate')
class WindowsJobTests(unittest.TestCase):
    def test_normal_exit(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root)
            seen = []
            def before_resume(identity):
                self.assertEqual((path/'out').stat().st_size, 0)
                self.assertGreater(identity['pid'], 0)
                self.assertGreater(int(identity['creationFileTime']), 0)
                seen.append(identity)
            result = job.run_once([sys.executable, '-c', 'print("owned-child")'], root, path/'out', path/'err', 10, on_root_created=before_resume)
            self.assertEqual(result['rootIdentity'], seen[0])
            self.assertTrue(result['started']); self.assertTrue(result['treeStopped'])
            self.assertFalse(result['timedOut']); self.assertEqual(result['exitCode'], 0)
            self.assertEqual((path/'out').read_text().strip(), 'owned-child')
    def test_timeout_stops_descendant(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root)
            child = 'import time;time.sleep(60)'
            parent = 'import subprocess,sys,time;subprocess.Popen([sys.executable,"-c",'+repr(child)+']);print("spawned",flush=True);time.sleep(60)'
            result = job.run_once([sys.executable, '-c', parent], root, path/'out', path/'err', 2)
            self.assertTrue(result['started']); self.assertTrue(result['timedOut'])
            self.assertTrue(result['treeStopped']); self.assertEqual((path/'out').read_text().strip(), 'spawned')


if __name__ == '__main__': unittest.main()
