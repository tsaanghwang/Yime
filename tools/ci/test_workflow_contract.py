"""Check retained CI scheduling and complete success aggregation, without builds."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
REQUIRED = {'build-contract', 'lexicon-offline-tooling', 'rust-i686-host', 'native-build',
            'go-tests', 'real-rime-tests', 'go-race-msys2', 'shard-coverage', 'simple-installer'}

def validate(text):
    jobs = {m[1]: m[0] for m in re.finditer(r'^  ([a-z][a-z0-9-]+):\n.*?(?=^  [a-z][a-z0-9-]+:|\Z)', text.split('\njobs:\n')[1], re.M|re.S)}
    if set(jobs) != REQUIRED | {'core-build'}: raise ValueError('Missing or unexpected job')
    for name, body in jobs.items():
        if not re.search(r'^    timeout-minutes: [1-9][0-9]?$', body, re.M): raise ValueError('Unbounded job')
        match = re.search(r'^    needs: \[([^]]+)\]', body, re.M)
        dependencies = set(match[1].split(', ')) if match else set()
        if not dependencies <= jobs.keys(): raise ValueError('Dangling dependency')
        if name == 'core-build' and dependencies != REQUIRED: raise ValueError('Incomplete aggregate')
    if "all(v['result']=='success'" not in jobs['core-build'] or 'toJSON(needs)' not in jobs['core-build']: raise ValueError('Aggregate permits failures')
    if 'cancel-in-progress:' not in text: raise ValueError('Superseded runs are not cancelled')
    if re.search(r'uses:\s+[^\s]+/\.github/workflows/', text): raise ValueError('External reusable workflow')

class WorkflowTests(unittest.TestCase):
    def test_current(self): validate((ROOT/'.github/workflows/ci.yaml').read_text())
    def test_missing_and_weakened_aggregate(self):
        text=(ROOT/'.github/workflows/ci.yaml').read_text()
        for changed in [text.replace('native-build, ', ''), text.replace("=='success'", "!='failure'")]:
            with self.assertRaises(ValueError): validate(changed)

if __name__ == '__main__': unittest.main()
