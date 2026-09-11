"""Require all nine source-bound real-Rime/transaction shards; fail on any gap."""
import argparse
import hashlib
import json
from pathlib import Path

SCRIPTS = {'real-rime': 'tools/test-real-rime.ps1',
           'installer-transaction': 'tools/dual-product/test-rime-pime-installer-receipt-transaction.ps1'}
EXPECTED = {(suite, shell, index) for suite, shells in
            [('real-rime', ['pwsh']), ('installer-transaction', ['powershell', 'pwsh'])]
            for shell in shells for index in range(3)}


def verify(records, commit, source_hashes):
    found = {}
    for r in records:
        key = (r['suite'], r['shell'], r['index'])
        if key not in EXPECTED or key in found or type(r['index']) is not int:
            raise ValueError('Unknown or duplicate shard')
        if (r['schema_version'] != 'yime-ci-test-shard-v1' or r['count'] != 3 or
                type(r['count']) is not int or r['passed'] is not True or
                r['installed_acceptance_passed'] is not False or r['commit'] != commit or
                r['source_sha256'] != source_hashes[r['suite']]):
            raise ValueError('Failed, stale or unsupported shard')
        names, executed = r['all_names'], r['executed_names']
        if (not isinstance(names, list) or len(names) < 3 or
                not all(isinstance(n, str) and n for n in names) or len(set(names)) != len(names) or
                not isinstance(executed, list) or len(set(executed)) != len(executed) or
                sorted(executed) != sorted(names[r['index']::3])):
            raise ValueError('Shard test membership differs')
        found[key] = r
    if set(found) != EXPECTED:
        raise ValueError('Missing required shards')
    counts = {}
    for suite, shell in sorted({k[:2] for k in EXPECTED}):
        group = [found[suite, shell, i] for i in range(3)]
        names = group[0]['all_names']
        if any(r['all_names'] != names for r in group):
            raise ValueError('Shard source inventories disagree')
        union = [n for r in group for n in r['executed_names']]
        if sorted(union) != sorted(names):
            raise ValueError('Aggregate has missing or duplicated tests')
        counts[suite + '/' + shell] = len(union)
    return {'ci_test_coverage_passed': True, 'test_counts': counts, 'installed_acceptance_passed': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    parser.add_argument('--commit', required=True)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    hashes = {s: hashlib.sha256((repo / p).read_bytes()).hexdigest() for s, p in SCRIPTS.items()}
    records = []
    for path in args.root.rglob('*.json'):
        if path.name.startswith('real-rime-shard-'):
            records.append(json.loads(path.read_text(encoding='utf-8-sig')))
        elif path.name == 'transaction-result.json':
            records.append(json.loads(path.read_text(encoding='utf-8-sig'))['ci_shard'])
    print(json.dumps(verify(records, args.commit, hashes)))


if __name__ == '__main__':
    main()
