"""One bounded preparation, one independent restore, one verification. No retries."""
import argparse
import json
from pathlib import Path
import sys
from windows_job_once import run_once

SCOPE = 'user-language-defaults-and-observed-pinyin-profile-only'


def read_result(path, mode):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result: raise ValueError('duplicate field')
            result[key] = value
        return result
    try:
        data = json.loads(path.read_text(encoding='utf-8-sig'), object_pairs_hook=unique)
        if not isinstance(data, dict) or data.get('schema') != 'chinese-environment-result-v1' or data.get('mode') != mode or data.get('scope') != SCOPE or data.get('componentServicingRollbackClaimed') is not False or type(data.get('mutationAttempted')) is not bool or type(data.get('configurationAppended')) is not bool:
            return None
        return data
    except (OSError, ValueError):
        return None


def run_prepare(root, evidence, query_executable, runner=run_once):
    root, evidence, query_executable = Path(root).resolve(), Path(evidence).resolve(), Path(query_executable).resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    ledger = evidence / 'transaction'
    if ledger.exists(): raise ValueError('fresh transaction directory required; never reuse a preparation')
    states, records = {}, {}
    summary = {'status': 'failed', 'preparationInvocations': 0, 'restoreInvocations': 0, 'verifyInvocations': 0, 'mutationAttempted': None, 'configurationAppended': None, 'restorationStatus': 'not-verified', 'freshProcessChineseEnvironmentVerified': False, 'observedRestorationVerified': False, 'componentServicingRollbackClaimed': False}
    def invoke(mode, timeout):
        params = evidence / (mode.lower() + '-params.json')
        params.write_text(json.dumps({'Mode': mode, 'LedgerDirectory': str(ledger), 'QueryExecutable': str(query_executable)}), encoding='utf-8')
        args = [str(Path(sys.executable).resolve()), str(root / 'tools/powershell/run_checked.py'), '--edition', 'ps5', '--script', str(root / 'tools/ci/prepare_chinese_environment.ps1'), '--params-file', str(params)]
        key = {'Prepare': 'preparationInvocations', 'Restore': 'restoreInvocations', 'Verify': 'verifyInvocations'}[mode]
        summary[key] += 1
        state = {'started': False, 'timedOut': False, 'treeStopped': False, 'exitCode': None, 'errorCode': None}
        try:
            state = runner(args, root, evidence / (mode.lower() + '-stdout.log'), evidence / (mode.lower() + '-stderr.log'), timeout)
        except (OSError, ValueError):
            state['errorCode'] = 1
        states[mode] = state
        (evidence / (mode.lower() + '-process.json')).write_text(json.dumps(state, indent=2), encoding='utf-8')
        records[mode] = read_result(ledger / (mode.lower() + '-result.json'), mode)
    try:
        invoke('Prepare', 240)
    finally:
        # Never restore concurrently with an unconfirmed live preparation tree.
        if states.get('Prepare', {}).get('treeStopped') is True and (ledger / 'ledger.json').is_file():
            try:
                invoke('Restore', 180)
            finally:
                if states.get('Restore', {}).get('treeStopped') is True:
                    invoke('Verify', 120)
    def completed(mode, codes):
        state = states.get(mode, {})
        return state.get('started') is True and state.get('treeStopped') is True and state.get('timedOut') is False and state.get('errorCode') is None and state.get('exitCode') in codes
    prep, restore, verify = (records.get(mode) for mode in ['Prepare', 'Restore', 'Verify'])
    if prep:
        summary['mutationAttempted'] = prep['mutationAttempted']
        summary['configurationAppended'] = prep['configurationAppended']
    native = (prep.get('observation') or {}).get('native', {}) if prep and isinstance(prep.get('observation'), dict) else {}
    query = native.get('query', {}) if isinstance(native, dict) else {}
    actual_chinese = isinstance(native, dict) and isinstance(query, dict) and native.get('verified') is True and type(query.get('actualHklLanguageHint')) is int and query['actualHklLanguageHint'] == 2052 and type(query.get('actualTsfLanguage')) is int and query['actualTsfLanguage'] == 2052
    summary['freshProcessChineseEnvironmentVerified'] = bool(prep and completed('Prepare', [0]) and prep.get('status') == 'prepared' and prep['configurationAppended'] and actual_chinese)
    summary['observedRestorationVerified'] = bool(restore and verify and completed('Restore', [0]) and completed('Verify', [0]) and restore.get('status') in ['verified', 'unchanged-no-mutation'] and verify.get('status') in ['verified', 'unchanged-no-mutation'])
    if summary['observedRestorationVerified']:
        summary['restorationStatus'] = verify['status']
    if summary['freshProcessChineseEnvironmentVerified'] and summary['observedRestorationVerified']:
        summary['status'] = 'prepared-and-restored'
    elif prep and completed('Prepare', [3]) and prep.get('status') == 'blocked' and (summary['observedRestorationVerified'] or not (ledger / 'ledger.json').exists() and prep['mutationAttempted'] is False):
        summary['status'] = 'blocked'
    (evidence / 'workflow-result.json').write_text(json.dumps(summary, indent=2), encoding='utf-8')
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--evidence', type=Path, required=True)
    parser.add_argument('--query-executable', type=Path, required=True)
    args = parser.parse_args()
    summary = run_prepare(args.root, args.evidence, args.query_executable)
    print(json.dumps(summary))
    return 0 if summary['status'] == 'prepared-and-restored' else 1


if __name__ == '__main__': sys.exit(main())
